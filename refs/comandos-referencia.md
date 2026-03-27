# 📋 Comandos de Referencia Rápida

> Una página con todos los comandos que necesitas para trabajar con almacenamiento en Linux. Sin explicaciones largas: acción directa.

---

## RAID con mdadm

```bash
# Crear RAID 10 con 4 discos:
mdadm --create /dev/md0 --level=10 --raid-devices=4 /dev/sdb /dev/sdc /dev/sdd /dev/sde

# Ver estado del RAID:
cat /proc/mdstat
mdadm --detail /dev/md0

# Añadir disco de repuesto:
mdadm --manage /dev/md0 --add /dev/sdf

# Simular fallo de un disco (laboratorio):
mdadm --manage /dev/md0 --fail /dev/sde

# Quitar disco fallido:
mdadm --manage /dev/md0 --remove /dev/sde

# Guardar configuración:
mdadm --detail --scan >> /etc/mdadm/mdadm.conf
update-initramfs -u

# Monitorizar con alertas por email:
mdadm --monitor --scan --daemonise --mailaddr=admin@empresa.com
```

---

## LVM

### Physical Volumes (PV)
```bash
pvcreate /dev/sdb                    # Crear PV
pvs                                  # Listar PVs
pvdisplay /dev/sdb                   # Detalle de un PV
pvremove /dev/sdb                    # Eliminar PV (si no está en VG)
```

### Volume Groups (VG)
```bash
vgcreate vg_datos /dev/sdb           # Crear VG
vgextend vg_datos /dev/sdc           # Añadir disco al VG
vgs                                  # Listar VGs
vgdisplay vg_datos                   # Detalle de un VG
vgcfgbackup -f backup.cfg vg_datos   # Backup de configuración del VG
```

### Logical Volumes (LV)
```bash
lvcreate -L 20G -n lv_mysql vg_datos          # Crear LV de tamaño fijo
lvcreate -l 100%FREE -n lv_datos vg_datos     # Crear LV con todo el espacio libre
lvextend -L +10G /dev/vg_datos/lv_mysql       # Extender LV en 10 GB más
lvextend -l +100%FREE /dev/vg_datos/lv_mysql  # Extender LV con todo el espacio libre del VG
lvs                                           # Listar LVs
lvdisplay /dev/vg_datos/lv_mysql              # Detalle de un LV
lvremove /dev/vg_datos/lv_mysql               # Eliminar LV (¡cuidado!)
```

### Extender sistema de ficheros tras lvextend
```bash
xfs_growfs /var/lib/mysql            # XFS: usar punto de montaje
resize2fs /dev/vg_datos/lv_mysql     # ext4: usar dispositivo
```

---

## Sistemas de ficheros

```bash
# Crear:
mkfs.xfs /dev/vg_datos/lv_mysql         # Formatear con XFS
mkfs.ext4 /dev/vg_datos/lv_sistema      # Formatear con ext4

# Montar y desmontar:
mount /dev/vg_datos/lv_mysql /var/lib/mysql
umount /var/lib/mysql

# Información:
xfs_info /var/lib/mysql                  # Info del FS XFS montado
tune2fs -l /dev/vg_datos/lv_sistema     # Info del FS ext4
blkid /dev/vg_datos/lv_mysql            # Ver UUID y tipo

# Comprobar integridad (con el FS desmontado):
xfs_repair /dev/vg_datos/lv_mysql       # Reparar XFS
e2fsck -f /dev/vg_datos/lv_sistema      # Comprobar/reparar ext4

# Reducir ext4 (XFS no se puede reducir):
e2fsck -f /dev/vg_datos/lv_sistema
resize2fs /dev/vg_datos/lv_sistema 10G
lvreduce -L 10G /dev/vg_datos/lv_sistema
```

---

## /etc/fstab

```bash
# Formato de una línea:
# <dispositivo>  <punto_montaje>  <tipo_fs>  <opciones>  <dump>  <pass>

# Ejemplos:
/dev/vg_datos/lv_mysql    /var/lib/mysql    xfs     defaults         0 0
UUID=abc123...            /                 ext4    errors=remount-ro 0 1
192.168.11.143:/srv/nfs   /mnt/nfs          nfs     defaults         0 0

# Probar fstab sin reiniciar:
mount -a

# Ver todos los montajes activos:
findmnt
```

---

## NFS — Servidor

```bash
# Instalar:
apt install nfs-kernel-server       # Debian/Ubuntu/Mint
dnf install nfs-utils               # Fedora/RHEL/Rocky

# Iniciar y habilitar:
systemctl enable --now nfs-kernel-server    # Debian/Ubuntu
systemctl enable --now nfs-server           # Fedora/RHEL

# Archivo de configuración:
nano /etc/exports
# Ejemplo: /srv/nfs/datos  192.168.11.142(rw,sync,no_subtree_check)

# Aplicar cambios en exports sin reiniciar:
exportfs -ra

# Ver qué se está exportando:
exportfs -v

# Ver conexiones NFS activas:
showmount -a
```

---

## NFS — Cliente

```bash
# Instalar:
apt install nfs-common              # Debian/Ubuntu/Mint
dnf install nfs-utils               # Fedora/RHEL/Rocky

# Montaje manual:
mount -t nfs 192.168.11.143:/srv/nfs/datos /mnt/nfs_datos

# Ver qué exporta un servidor:
showmount -e 192.168.11.143

# Desmontar:
umount /mnt/nfs_datos

# Montaje persistente en fstab:
# 192.168.11.143:/srv/nfs/datos  /mnt/nfs_datos  nfs  defaults  0 0
```

---

## Diagnóstico de almacenamiento

```bash
# Vista general de todos los discos:
lsblk
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,UUID

# Espacio en disco:
df -h                                # Por sistema de ficheros
df -i                                # Uso de inodos
du -sh /var/log/* | sort -rh         # Qué ocupa más en un directorio

# Ver qué proceso tiene abierto un fichero/dispositivo:
lsof /var/lib/mysql
fuser -m /var/lib/mysql

# Errores de hardware en tiempo real:
dmesg | grep -i -E "error|fail|ata|sd[a-z]"
journalctl -k | grep -i error

# S.M.A.R.T. — salud de discos:
smartctl -a /dev/sdb                 # Info completa
smartctl -H /dev/sdb                 # Solo resultado del test de salud
smartctl -t short /dev/sdb           # Ejecutar test corto
```

---

## Backup MySQL

```bash
# Backup de una BBDD:
mysqldump -u root -p nombre_bbdd > backup.sql

# Backup de todas las BBDD con compresión:
mysqldump -u root -p --all-databases | gzip > backup_$(date +%Y%m%d).sql.gz

# Backup seguro (sin bloquear tablas InnoDB):
mysqldump -u root -p --single-transaction --all-databases | gzip > backup.sql.gz

# Restaurar:
mysql -u root -p nombre_bbdd < backup.sql
gunzip < backup.sql.gz | mysql -u root -p

# Verificar backup:
gunzip -t backup.sql.gz
```

---

## cron — Programación de tareas

```bash
# Editar crontab del usuario actual:
crontab -e

# Formato: minuto hora día_mes mes día_semana comando
# Backup diario a las 2:00:
0 2 * * * /opt/scripts/backup-mysql.sh

# Monitorización cada hora:
0 * * * * /opt/scripts/monitor-storage.sh

# Ver tareas programadas:
crontab -l

# Logs de cron:
journalctl -u cron
grep CRON /var/log/syslog
```

---

## Comandos de referencia rápida por situación

### "¿Cuánto espacio queda?"
```bash
df -h && vgs
```

### "¿El RAID está sano?"
```bash
cat /proc/mdstat && mdadm --detail /dev/md0
```

### "¿Qué hay montado ahora mismo?"
```bash
findmnt
```

### "El disco está lleno pero df dice que hay espacio"
```bash
df -i   # Comprobar inodos
```

### "Necesito más espacio en caliente"
```bash
# Si hay espacio en el VG:
lvextend -L +XG /dev/vg/lv && xfs_growfs /punto/montaje

# Si no hay espacio en el VG:
pvcreate /dev/sdX && vgextend vg_nombre /dev/sdX
# Luego el lvextend de arriba
```

### "NFS no monta"
```bash
ping servidor && showmount -e IP_servidor && systemctl status nfs-server
```

---

*Ver también: [Troubleshooting](../docs/09-troubleshooting.md) · [Volver al README](../README.md)*
