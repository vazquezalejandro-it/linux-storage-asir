#!/bin/bash
# =============================================================================
# monitor-storage.sh
# Monitorización de almacenamiento: espacio en disco, estado RAID y salud S.M.A.R.T.
# Envía alertas por email o escribe en syslog si detecta problemas.
#
# Uso: ./monitor-storage.sh
# Recomendado: ejecutar cada hora desde cron
#   0 * * * * /opt/scripts/monitor-storage.sh
#
# Configuración: editar la sección CONFIGURACIÓN más abajo
#
# Autor: Alejandro — ASIR
# =============================================================================

set -euo pipefail

# =============================================================================
# CONFIGURACIÓN — Editar según el entorno
# =============================================================================
DISK_THRESHOLD=80          # Porcentaje de uso que dispara la alerta
INODE_THRESHOLD=80         # Porcentaje de uso de inodos que dispara la alerta
ALERT_EMAIL="admin@empresa.com"
HOSTNAME_REAL=$(hostname)
LOG_FILE="/var/log/monitor-storage.log"
SEND_EMAIL=false           # Cambiar a true si hay un MTA configurado (sendmail, postfix)

# Discos físicos a comprobar con S.M.A.R.T. (ajustar según el sistema)
SMART_DISKS=("/dev/sda" "/dev/sdb" "/dev/sdc" "/dev/sdd")

# Arrays RAID a comprobar (dejar vacío si no hay RAID)
RAID_ARRAYS=("/dev/md0")
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ALERTS=()   # Array donde se acumulan todas las alertas del script
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

log() { echo "[$TIMESTAMP] $1" | tee -a "$LOG_FILE"; }

add_alert() {
    ALERTS+=("$1")
    log "ALERTA: $1"
}

# =============================================================================
# COMPROBACIÓN 1: Espacio en disco
# =============================================================================
log "--- Comprobando espacio en disco ---"

while IFS= read -r line; do
    # Extraer datos de la línea de df
    FILESYSTEM=$(echo "$line" | awk '{print $1}')
    USE_PCT=$(echo "$line" | awk '{print $5}' | tr -d '%')
    MOUNTPOINT=$(echo "$line" | awk '{print $6}')

    # Ignorar tmpfs, devtmpfs y otros sistemas virtuales
    [[ "$FILESYSTEM" == tmpfs* ]] && continue
    [[ "$FILESYSTEM" == devtmpfs* ]] && continue
    [[ "$FILESYSTEM" == udev* ]] && continue

    if [ "$USE_PCT" -ge "$DISK_THRESHOLD" ] 2>/dev/null; then
        AVAIL=$(echo "$line" | awk '{print $4}')
        add_alert "DISCO LLENO: $MOUNTPOINT ($FILESYSTEM) al ${USE_PCT}% — Disponible: $AVAIL"
    else
        log "OK: $MOUNTPOINT al ${USE_PCT}%"
    fi
done < <(df -h | tail -n +2)

# =============================================================================
# COMPROBACIÓN 2: Uso de inodos
# =============================================================================
log "--- Comprobando uso de inodos ---"

while IFS= read -r line; do
    FILESYSTEM=$(echo "$line" | awk '{print $1}')
    IUSE_PCT=$(echo "$line" | awk '{print $5}' | tr -d '%')
    MOUNTPOINT=$(echo "$line" | awk '{print $6}')

    [[ "$FILESYSTEM" == tmpfs* ]] && continue
    [[ "$FILESYSTEM" == devtmpfs* ]] && continue

    if [ "$IUSE_PCT" -ge "$INODE_THRESHOLD" ] 2>/dev/null; then
        IFREE=$(echo "$line" | awk '{print $4}')
        add_alert "INODOS AGOTADOS: $MOUNTPOINT al ${IUSE_PCT}% de inodos — Libres: $IFREE"
    fi
done < <(df -i | tail -n +2)

# =============================================================================
# COMPROBACIÓN 3: Estado de arrays RAID
# =============================================================================
if [ ${#RAID_ARRAYS[@]} -gt 0 ]; then
    log "--- Comprobando estado RAID ---"

    for ARRAY in "${RAID_ARRAYS[@]}"; do
        if [ ! -b "$ARRAY" ]; then
            log "SKIP: $ARRAY no existe"
            continue
        fi

        if ! command -v mdadm > /dev/null 2>&1; then
            log "SKIP: mdadm no está instalado"
            break
        fi

        RAID_STATE=$(mdadm --detail "$ARRAY" 2>/dev/null | grep "State :" | awk '{print $3}')
        FAILED_DEVICES=$(mdadm --detail "$ARRAY" 2>/dev/null | grep "Failed Devices :" | awk '{print $4}')
        DEGRADED_DEVICES=$(mdadm --detail "$ARRAY" 2>/dev/null | grep "Degraded :" | awk '{print $3}' || echo "0")

        if [ "$RAID_STATE" != "clean" ] && [ "$RAID_STATE" != "active" ]; then
            add_alert "RAID DEGRADADO: $ARRAY en estado '$RAID_STATE'"
        fi

        if [ "$FAILED_DEVICES" -gt 0 ] 2>/dev/null; then
            add_alert "RAID FALLO: $ARRAY tiene $FAILED_DEVICES disco(s) fallido(s)"
        else
            log "OK: RAID $ARRAY en estado $RAID_STATE"
        fi
    done
fi

# =============================================================================
# COMPROBACIÓN 4: Salud S.M.A.R.T. de discos
# =============================================================================
if command -v smartctl > /dev/null 2>&1; then
    log "--- Comprobando salud S.M.A.R.T. ---"

    for DISK in "${SMART_DISKS[@]}"; do
        if [ ! -b "$DISK" ]; then
            log "SKIP: $DISK no existe"
            continue
        fi

        SMART_RESULT=$(smartctl -H "$DISK" 2>/dev/null | grep "SMART overall" | awk '{print $NF}' || echo "UNKNOWN")

        if [ "$SMART_RESULT" = "PASSED" ]; then
            log "OK: $DISK — S.M.A.R.T. PASSED"
        elif [ "$SMART_RESULT" = "FAILED!" ]; then
            add_alert "DISCO FALLANDO: $DISK — S.M.A.R.T. FAILED. Reemplazar URGENTE."
        else
            # Comprobar atributos críticos específicos
            REALLOCATED=$(smartctl -A "$DISK" 2>/dev/null | awk '/Reallocated_Sector_Ct/{print $10}' || echo "0")
            PENDING=$(smartctl -A "$DISK" 2>/dev/null | awk '/Current_Pending_Sector/{print $10}' || echo "0")
            UNCORRECTABLE=$(smartctl -A "$DISK" 2>/dev/null | awk '/Offline_Uncorrectable/{print $10}' || echo "0")

            if [ "$REALLOCATED" -gt 100 ] 2>/dev/null; then
                add_alert "DISCO DEGRADÁNDOSE: $DISK tiene $REALLOCATED sectores reasignados (Reallocated_Sector_Ct)"
            fi
            if [ "$PENDING" -gt 0 ] 2>/dev/null; then
                add_alert "DISCO CON ERRORES: $DISK tiene $PENDING sectores pendientes (Current_Pending_Sector)"
            fi
            if [ "$UNCORRECTABLE" -gt 0 ] 2>/dev/null; then
                add_alert "DISCO CON ERRORES: $DISK tiene $UNCORRECTABLE sectores irrecuperables (Offline_Uncorrectable)"
            fi
        fi
    done
else
    log "SKIP: smartmontools no instalado (apt install smartmontools)"
fi

# =============================================================================
# ENVÍO DE ALERTAS
# =============================================================================
if [ ${#ALERTS[@]} -gt 0 ]; then
    log "=== RESUMEN: ${#ALERTS[@]} ALERTA(S) DETECTADA(S) ==="

    ALERT_MSG="ALERTAS DE ALMACENAMIENTO — $HOSTNAME_REAL — $TIMESTAMP\n\n"
    for ALERT in "${ALERTS[@]}"; do
        ALERT_MSG+="⚠️  $ALERT\n"
        log "  → $ALERT"
    done

    ALERT_MSG+="\n---\nRevisar con:\n  df -h\n  cat /proc/mdstat\n  lvs && vgs\n  smartctl -a /dev/sdX"

    if [ "$SEND_EMAIL" = true ] && command -v mail > /dev/null 2>&1; then
        echo -e "$ALERT_MSG" | mail -s "⚠️ ALERTA ALMACENAMIENTO — $HOSTNAME_REAL" "$ALERT_EMAIL"
        log "Email de alerta enviado a $ALERT_EMAIL"
    fi

    # También escribir en syslog para que quede en los logs del sistema
    logger -t monitor-storage "ALERTA: ${#ALERTS[@]} problema(s) detectado(s) en $HOSTNAME_REAL"

    exit 1  # Salida con código 1 para que cron/sistemas de monitorización lo detecten
else
    log "=== OK: Ningún problema detectado ==="
    exit 0
fi
