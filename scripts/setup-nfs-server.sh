#!/bin/bash
# =============================================================================
# setup-nfs-server.sh
# Configura un servidor NFS en sistemas Debian/Ubuntu desde cero.
#
# Uso: sudo ./setup-nfs-server.sh <IP_CLIENTE> <DIRECTORIO_EXPORT>
# Ejemplo: sudo ./setup-nfs-server.sh 192.168.11.142 /srv/nfs/compartido
#
# Lo que hace este script:
#   1. Instala nfs-kernel-server
#   2. Crea el directorio de exportación
#   3. Configura /etc/exports
#   4. Inicia y habilita el servicio NFS
#   5. Verifica que todo está funcionando
#
# Autor: Alejandro — ASIR
# =============================================================================

set -euo pipefail   # Salir si hay error, variable no definida, o fallo en pipe

# --- Colores para la salida ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Funciones de log ---
log_info()    { echo -e "${BLUE}[INFO]${NC}  $1"; }
log_ok()      { echo -e "${GREEN}[OK]${NC}    $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# --- Verificaciones previas ---
[ "$EUID" -ne 0 ] && log_error "Este script debe ejecutarse como root (sudo)"
[ "$#" -ne 2 ]    && log_error "Uso: $0 <IP_CLIENTE> <DIRECTORIO_EXPORT>\nEjemplo: $0 192.168.11.142 /srv/nfs/compartido"

CLIENT_IP="$1"
EXPORT_DIR="$2"

echo ""
echo "=================================================="
echo "  Configuración de Servidor NFS"
echo "=================================================="
echo "  Cliente permitido: $CLIENT_IP"
echo "  Directorio a exportar: $EXPORT_DIR"
echo "=================================================="
echo ""

# --- Paso 1: Detectar el sistema operativo ---
log_info "Detectando sistema operativo..."
if [ -f /etc/debian_version ]; then
    PKG_MANAGER="apt"
    NFS_SERVICE="nfs-kernel-server"
    NFS_PKG="nfs-kernel-server"
    log_ok "Sistema Debian/Ubuntu detectado"
elif [ -f /etc/fedora-release ] || [ -f /etc/redhat-release ]; then
    PKG_MANAGER="dnf"
    NFS_SERVICE="nfs-server"
    NFS_PKG="nfs-utils"
    log_ok "Sistema Fedora/RHEL detectado"
else
    log_error "Sistema operativo no soportado. Solo Debian/Ubuntu o Fedora/RHEL."
fi

# --- Paso 2: Instalar NFS ---
log_info "Instalando paquetes NFS..."
if [ "$PKG_MANAGER" = "apt" ]; then
    apt-get update -qq
    apt-get install -y "$NFS_PKG" > /dev/null
else
    dnf install -y "$NFS_PKG" > /dev/null
fi
log_ok "Paquetes NFS instalados correctamente"

# --- Paso 3: Crear el directorio de exportación ---
log_info "Creando directorio de exportación: $EXPORT_DIR"
mkdir -p "$EXPORT_DIR"
chmod 755 "$EXPORT_DIR"
log_ok "Directorio creado: $EXPORT_DIR"

# --- Paso 4: Configurar /etc/exports ---
log_info "Configurando /etc/exports..."

# Hacer backup del exports actual si ya tiene contenido
if [ -s /etc/exports ]; then
    cp /etc/exports "/etc/exports.backup.$(date +%Y%m%d_%H%M%S)"
    log_warn "Backup del exports anterior guardado en /etc/exports.backup.*"
fi

# Verificar si ya existe la entrada para evitar duplicados
EXPORTS_LINE="${EXPORT_DIR}    ${CLIENT_IP}(rw,sync,no_subtree_check,root_squash)"

if grep -qF "$EXPORT_DIR" /etc/exports 2>/dev/null; then
    log_warn "Ya existe una entrada para $EXPORT_DIR en /etc/exports. No se ha modificado."
    log_warn "Revisa /etc/exports manualmente si necesitas actualizarla."
else
    echo "$EXPORTS_LINE" >> /etc/exports
    log_ok "Añadida entrada en /etc/exports:"
    echo "    $EXPORTS_LINE"
fi

# --- Paso 5: Iniciar y habilitar el servicio ---
log_info "Iniciando y habilitando el servicio NFS..."
systemctl enable --now "$NFS_SERVICE" > /dev/null 2>&1
log_ok "Servicio $NFS_SERVICE activo y habilitado para el arranque"

# --- Paso 6: Aplicar la configuración de exports ---
log_info "Aplicando configuración de exports..."
exportfs -ra
log_ok "Exports recargados"

# --- Paso 7: Verificaciones ---
echo ""
log_info "Verificando la configuración..."

# Comprobar que el servicio está corriendo
if systemctl is-active --quiet "$NFS_SERVICE"; then
    log_ok "Servicio NFS: ACTIVO"
else
    log_error "El servicio NFS no está activo. Revisa: journalctl -xe"
fi

# Comprobar que el directorio existe y es accesible
if [ -d "$EXPORT_DIR" ]; then
    log_ok "Directorio de exportación: EXISTE"
else
    log_error "El directorio $EXPORT_DIR no existe"
fi

# Mostrar lo que se está exportando
echo ""
log_info "Exports activos en este servidor:"
exportfs -v

echo ""
echo "=================================================="
echo -e "  ${GREEN}Servidor NFS configurado correctamente${NC}"
echo "=================================================="
echo ""
echo "  Para montar desde el cliente ($CLIENT_IP):"
echo ""
echo "    sudo mkdir -p /mnt/nfs_compartido"
echo "    sudo mount -t nfs $(hostname -I | awk '{print $1}'):${EXPORT_DIR} /mnt/nfs_compartido"
echo ""
echo "  Para montaje persistente, añadir a /etc/fstab del cliente:"
echo ""
echo "    $(hostname -I | awk '{print $1}'):${EXPORT_DIR}  /mnt/nfs_compartido  nfs  defaults  0  0"
echo ""
