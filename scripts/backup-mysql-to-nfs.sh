#!/bin/bash
# =============================================================================
# backup-mysql-to-nfs.sh
# Backup automático de todas las bases de datos MySQL hacia el servidor NFS.
# Cada base de datos se guarda en un archivo .sql.gz separado.
# Implementa rotación automática (elimina backups más antiguos que N días).
# Verifica que el NFS está montado antes de empezar.
#
# Uso: ./backup-mysql-to-nfs.sh
# Recomendado: ejecutar a las 2:00 AM desde cron
#   0 2 * * * /opt/scripts/backup-mysql-to-nfs.sh >> /var/log/backup-mysql.log 2>&1
#
# Configuración: editar la sección CONFIGURACIÓN más abajo
#
# Autor: Alejandro — ASIR
# =============================================================================

set -euo pipefail

# =============================================================================
# CONFIGURACIÓN — Editar según el entorno
# =============================================================================
MYSQL_USER="backup_user"              # Usuario MySQL con permisos de backup
MYSQL_PASS=""                         # Contraseña (mejor usar ~/.my.cnf, ver abajo)
NFS_MOUNT="/mnt/nfs_backups"          # Punto de montaje del servidor NFS
BACKUP_BASE_DIR="$NFS_MOUNT/mysql"    # Directorio raíz de backups en el NFS
RETENTION_DAYS=7                      # Días que se conservan los backups
ALERT_EMAIL="admin@empresa.com"       # Email para notificaciones de error
LOG_FILE="/var/log/backup-mysql.log"

# BBDDs a excluir del backup (separadas por espacio):
EXCLUDE_DBS="information_schema performance_schema sys"
# =============================================================================

TIMESTAMP=$(date '+%Y-%m-%d_%H%M')
BACKUP_DIR="$BACKUP_BASE_DIR/$TIMESTAMP"
ERRORS=0
BACKED_UP=0

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"; }
log_error() { log "ERROR: $1"; ERRORS=$((ERRORS + 1)); }

# =============================================================================
# Nota sobre seguridad de credenciales
# =============================================================================
# En lugar de poner la contraseña en este script, es más seguro usar ~/.my.cnf:
#
# Crear /root/.my.cnf con:
#   [client]
#   user=backup_user
#   password=tu_contraseña_aqui
#
# Y cambiar permisos: chmod 600 /root/.my.cnf
#
# Luego cambiar MYSQL_PASS="" y usar mysql/mysqldump sin -p
# Los comandos del script ya están preparados para funcionar con .my.cnf

# --- Construir opciones de MySQL ---
if [ -n "$MYSQL_PASS" ]; then
    MYSQL_OPTS="-u $MYSQL_USER -p$MYSQL_PASS"
else
    MYSQL_OPTS="-u $MYSQL_USER"
fi

log "======================================================="
log "Iniciando backup de MySQL → NFS"
log "Destino: $BACKUP_DIR"
log "======================================================="

# =============================================================================
# PASO 1: Verificaciones previas
# =============================================================================
log "Verificando prerrequisitos..."

# Comprobar que el NFS está montado
if ! mountpoint -q "$NFS_MOUNT"; then
    log_error "El servidor NFS NO está montado en $NFS_MOUNT"
    log "Intentando montar..."
    if mount -a 2>/dev/null && mountpoint -q "$NFS_MOUNT"; then
        log "NFS montado correctamente"
    else
        log_error "No se pudo montar el NFS. Abortando backup."
        echo "CRÍTICO: Backup MySQL fallido — NFS no disponible en $(hostname)" | \
            mail -s "FALLO BACKUP MySQL" "$ALERT_EMAIL" 2>/dev/null || true
        exit 1
    fi
fi
log "OK: NFS montado en $NFS_MOUNT"

# Comprobar que hay espacio suficiente en el NFS (mínimo 1 GB libre)
NFS_FREE_KB=$(df -k "$NFS_MOUNT" | awk 'NR==2 {print $4}')
if [ "$NFS_FREE_KB" -lt 1048576 ]; then  # 1 GB en KB
    log_error "Espacio insuficiente en NFS: menos de 1 GB disponible"
    exit 1
fi
log "OK: Espacio en NFS disponible"

# Comprobar que MySQL está accesible
if ! mysql $MYSQL_OPTS -e "SELECT 1;" > /dev/null 2>&1; then
    log_error "No se puede conectar a MySQL. Verificar credenciales y estado del servicio."
    exit 1
fi
log "OK: MySQL accesible"

# Crear directorio de backup
mkdir -p "$BACKUP_DIR"
log "Directorio de backup creado: $BACKUP_DIR"

# =============================================================================
# PASO 2: Backup de cada base de datos
# =============================================================================
log "Obteniendo lista de bases de datos..."

DATABASES=$(mysql $MYSQL_OPTS -e "SHOW DATABASES;" --skip-column-names 2>/dev/null)

for DB in $DATABASES; do
    # Saltar bases de datos excluidas
    SKIP=false
    for EXCL in $EXCLUDE_DBS; do
        [ "$DB" = "$EXCL" ] && SKIP=true && break
    done
    $SKIP && log "SKIP: $DB (excluida)" && continue

    log "Backup: $DB..."

    # Hacer el dump con opciones para consistencia y completitud
    if mysqldump $MYSQL_OPTS \
        --single-transaction \    # Consistencia sin bloquear tablas (InnoDB)
        --routines \              # Incluir stored procedures y funciones
        --triggers \              # Incluir triggers
        --events \                # Incluir eventos programados
        --set-gtid-purged=OFF \   # Evitar problemas con replicación GTID
        "$DB" 2>/dev/null | gzip -9 > "$BACKUP_DIR/${DB}.sql.gz"; then

        SIZE=$(du -sh "$BACKUP_DIR/${DB}.sql.gz" | awk '{print $1}')
        log "OK: $DB → ${DB}.sql.gz ($SIZE)"
        BACKED_UP=$((BACKED_UP + 1))
    else
        log_error "Fallo al hacer backup de $DB"
    fi
done

# =============================================================================
# PASO 3: Verificar integridad de los backups creados
# =============================================================================
log "Verificando integridad de los backups..."

for FILE in "$BACKUP_DIR"/*.sql.gz; do
    [ -f "$FILE" ] || continue
    if gunzip -t "$FILE" 2>/dev/null; then
        log "OK integridad: $(basename $FILE)"
    else
        log_error "CORRUPTO: $FILE"
    fi
done

# =============================================================================
# PASO 4: Backup de configuración del sistema
# =============================================================================
log "Backup de configuración del sistema..."
CONFIG_BACKUP="$BACKUP_DIR/system-config.tar.gz"

tar -czf "$CONFIG_BACKUP" \
    /etc/fstab \
    /etc/exports \
    /etc/mysql/ \
    /etc/mdadm/mdadm.conf 2>/dev/null || \
    log "WARN: Algunos archivos de config no encontrados (normal si no todos los servicios están instalados)"

log "OK: Configuración guardada en system-config.tar.gz"

# =============================================================================
# PASO 5: Rotación — eliminar backups antiguos
# =============================================================================
log "Ejecutando rotación de backups (retención: $RETENTION_DAYS días)..."

DELETED=0
while IFS= read -r OLD_DIR; do
    log "Eliminando backup antiguo: $OLD_DIR"
    rm -rf "$OLD_DIR"
    DELETED=$((DELETED + 1))
done < <(find "$BACKUP_BASE_DIR" -maxdepth 1 -type d -mtime +"$RETENTION_DAYS" 2>/dev/null)

[ "$DELETED" -gt 0 ] && log "Eliminados $DELETED backup(s) antiguo(s)" || log "No hay backups antiguos que eliminar"

# =============================================================================
# PASO 6: Resumen y notificación
# =============================================================================
TOTAL_SIZE=$(du -sh "$BACKUP_DIR" | awk '{print $1}')
BACKUPS_EN_NFS=$(find "$BACKUP_BASE_DIR" -maxdepth 1 -type d | wc -l)

echo ""
log "======================================================="
log "RESUMEN DEL BACKUP"
log "  Bases de datos: $BACKED_UP backups completados"
log "  Tamaño total:   $TOTAL_SIZE"
log "  Errores:        $ERRORS"
log "  Backups en NFS: $BACKUPS_EN_NFS (últimos $RETENTION_DAYS días)"
log "  Destino:        $BACKUP_DIR"
log "======================================================="

if [ "$ERRORS" -gt 0 ]; then
    log "ADVERTENCIA: El backup completó con $ERRORS error(s)"
    echo "Backup MySQL completado con $ERRORS error(s) en $(hostname). Revisar $LOG_FILE" | \
        mail -s "⚠️ Backup MySQL con errores — $(hostname)" "$ALERT_EMAIL" 2>/dev/null || true
    exit 1
else
    log "Backup completado correctamente"
    exit 0
fi
