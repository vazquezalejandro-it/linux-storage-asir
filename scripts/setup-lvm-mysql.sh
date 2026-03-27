#!/bin/bash
# =============================================================================
# setup-lvm-mysql.sh
# Configura la pila LVM optimizada para MySQL sobre un dispositivo dado.
# RAID 10 previo asumido. Este script gestiona desde el PV hasta el montaje.
#
# Uso: sudo ./setup-lvm-mysql.sh <DISPOSITIVO> <TAMAÑO_LV>
# Ejemplo: sudo ./setup-lvm-mysql.sh /dev/md0 80G
#
# Lo que hace:
#   1. Crea el PV sobre el dispositivo
#   2. Crea el VG vg_mysql
#   3. Crea lv_mysql (datos) y lv_binlog (binary logs)
#   4. Formatea ambos con XFS
#   5. Monta en /var/lib/mysql y /var/lib/mysql-binlog
#   6. Añade entradas a /etc/fstab
#   7. Ajusta permisos para el usuario mysql
#
# Prerrequisitos: lvm2 instalado, dispositivo disponible y sin datos
#
# Autor: Alejandro — ASIR
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC}  $1"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# --- Verificaciones previas ---
[ "$EUID" -ne 0 ] && log_error "Ejecutar como root"
[ "$#" -ne 2 ]    && log_error "Uso: $0 <DISPOSITIVO> <TAMAÑO_LV_DATOS>\nEjemplo: $0 /dev/md0 80G"

DEVICE="$1"
LV_SIZE="$2"

# Calcular tamaño de binlog (10% del tamaño de datos, mínimo 5G)
# Para simplificar el script, usamos un valor fijo de 10G para binlogs
BINLOG_SIZE="10G"

VG_NAME="vg_mysql"
LV_DATOS="lv_mysql"
LV_BINLOG="lv_binlog"
MOUNT_DATOS="/var/lib/mysql"
MOUNT_BINLOG="/var/lib/mysql-binlog"

echo ""
echo "=================================================="
echo "  Configuración de LVM para MySQL"
echo "=================================================="
echo "  Dispositivo base:     $DEVICE"
echo "  VG:                   $VG_NAME"
echo "  LV datos ($LV_DATOS): $LV_SIZE"
echo "  LV binlog ($LV_BINLOG): $BINLOG_SIZE"
echo "  Montaje datos:        $MOUNT_DATOS"
echo "  Montaje binlog:       $MOUNT_BINLOG"
echo "=================================================="
echo ""

# --- Verificar que el dispositivo existe ---
[ ! -b "$DEVICE" ] && log_error "El dispositivo $DEVICE no existe o no es un dispositivo de bloque"

# --- Verificar que lvm2 está instalado ---
command -v pvcreate > /dev/null 2>&1 || log_error "lvm2 no está instalado. Instalar con: apt install lvm2"

# --- Advertencia de seguridad ---
log_warn "ATENCIÓN: Este script creará un PV sobre $DEVICE."
log_warn "TODOS LOS DATOS EN $DEVICE SERÁN DESTRUIDOS."
echo ""
read -r -p "¿Confirmas que $DEVICE no tiene datos importantes? [escribe 'si' para continuar]: " CONFIRM
[ "$CONFIRM" != "si" ] && log_error "Operación cancelada por el usuario"
echo ""

# --- Paso 1: Crear Physical Volume ---
log_info "Creando Physical Volume sobre $DEVICE..."
pvcreate "$DEVICE"
log_ok "PV creado: $DEVICE"

# --- Paso 2: Crear Volume Group ---
log_info "Creando Volume Group $VG_NAME..."
vgcreate "$VG_NAME" "$DEVICE"
log_ok "VG creado: $VG_NAME"

# Mostrar espacio disponible
VG_FREE=$(vgs --noheadings -o vfree "$VG_NAME" | tr -d ' ')
log_info "Espacio disponible en $VG_NAME: $VG_FREE"

# --- Paso 3: Crear Logical Volumes ---
log_info "Creando LV para datos MySQL: $LV_DATOS ($LV_SIZE)..."
lvcreate -L "$LV_SIZE" -n "$LV_DATOS" "$VG_NAME"
log_ok "LV creado: /dev/$VG_NAME/$LV_DATOS"

log_info "Creando LV para binary logs: $LV_BINLOG ($BINLOG_SIZE)..."
lvcreate -L "$BINLOG_SIZE" -n "$LV_BINLOG" "$VG_NAME"
log_ok "LV creado: /dev/$VG_NAME/$LV_BINLOG"

# --- Paso 4: Formatear con XFS ---
log_info "Formateando $LV_DATOS con XFS..."
mkfs.xfs "/dev/$VG_NAME/$LV_DATOS" > /dev/null
log_ok "XFS creado en /dev/$VG_NAME/$LV_DATOS"

log_info "Formateando $LV_BINLOG con XFS..."
mkfs.xfs "/dev/$VG_NAME/$LV_BINLOG" > /dev/null
log_ok "XFS creado en /dev/$VG_NAME/$LV_BINLOG"

# --- Paso 5: Crear puntos de montaje y montar ---
log_info "Creando puntos de montaje..."
mkdir -p "$MOUNT_DATOS" "$MOUNT_BINLOG"

log_info "Montando $LV_DATOS en $MOUNT_DATOS..."
mount "/dev/$VG_NAME/$LV_DATOS" "$MOUNT_DATOS"
log_ok "Montado: $MOUNT_DATOS"

log_info "Montando $LV_BINLOG en $MOUNT_BINLOG..."
mount "/dev/$VG_NAME/$LV_BINLOG" "$MOUNT_BINLOG"
log_ok "Montado: $MOUNT_BINLOG"

# --- Paso 6: Configurar fstab ---
log_info "Añadiendo entradas a /etc/fstab..."

# Backup de fstab
cp /etc/fstab "/etc/fstab.backup.$(date +%Y%m%d_%H%M%S)"

# Añadir entradas si no existen ya
FSTAB_DATOS="/dev/$VG_NAME/$LV_DATOS    $MOUNT_DATOS    xfs    defaults    0 0"
FSTAB_BINLOG="/dev/$VG_NAME/$LV_BINLOG    $MOUNT_BINLOG    xfs    defaults    0 0"

if ! grep -qF "$LV_DATOS" /etc/fstab; then
    echo "$FSTAB_DATOS" >> /etc/fstab
    log_ok "Entrada fstab añadida para $LV_DATOS"
fi

if ! grep -qF "$LV_BINLOG" /etc/fstab; then
    echo "$FSTAB_BINLOG" >> /etc/fstab
    log_ok "Entrada fstab añadida para $LV_BINLOG"
fi

# Verificar fstab
log_info "Verificando /etc/fstab..."
mount -a --fake 2>/dev/null && log_ok "/etc/fstab válido" || log_warn "Posible problema en fstab, revisar manualmente"

# --- Paso 7: Ajustar permisos para MySQL (si el usuario existe) ---
if id mysql > /dev/null 2>&1; then
    log_info "Usuario mysql encontrado. Ajustando permisos..."
    chown -R mysql:mysql "$MOUNT_DATOS" "$MOUNT_BINLOG"
    log_ok "Permisos ajustados para usuario mysql"
else
    log_warn "Usuario mysql no encontrado. Ajustar permisos manualmente tras instalar MySQL:"
    log_warn "  chown -R mysql:mysql $MOUNT_DATOS $MOUNT_BINLOG"
fi

# --- Resumen final ---
echo ""
echo "=================================================="
echo -e "  ${GREEN}LVM para MySQL configurado correctamente${NC}"
echo "=================================================="
echo ""
df -h | grep -E "Filesystem|$VG_NAME"
echo ""
echo "  LVs creados:"
lvs "$VG_NAME"
echo ""
echo "  Para extender el almacenamiento en el futuro:"
echo ""
echo "    # Si el VG tiene espacio libre:"
echo "    lvextend -L +XG /dev/$VG_NAME/$LV_DATOS"
echo "    xfs_growfs $MOUNT_DATOS"
echo ""
echo "    # Si el VG no tiene espacio (añadir disco nuevo):"
echo "    pvcreate /dev/sdX"
echo "    vgextend $VG_NAME /dev/sdX"
echo "    # Luego el lvextend de arriba"
echo ""
