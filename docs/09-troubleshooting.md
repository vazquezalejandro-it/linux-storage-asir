# 🔧 Troubleshooting — Problemas Reales y Cómo Resolverlos

> La mayoría de los problemas de almacenamiento en Linux son predecibles. Este documento recoge los errores más frecuentes, por qué ocurren y cómo salir de ellos sin entrar en pánico.

---

## Problema 1: El sistema no arranca después de editar /etc/fstab

**Síntoma**: Después de añadir una línea a `/etc/fstab`, el sistema arranca en modo emergencia (`emergency mode`) o se queda colgado con el mensaje `A start job is running for...`

**Causa**: Un error en la línea añadida (UUID incorrecto, tipo de sistema de ficheros mal escrito, punto de montaje que no existe, etc.).

**Solución**:

```bash
# El sistema arranca en modo emergencia y pide la contraseña de root
# Una vez dentro:

# 1. Remontar la raíz en modo escritura (suele estar en solo lectura en emergencia):
mount -o remount,rw /

# 2. Editar fstab para corregir el error:
nano /etc/fstab

# 3. Verificar que la línea corregida es válida:
mount -a

# 4. Si mount -a no da errores, reiniciar:
reboot
```

**Cómo evitarlo**: Antes de reiniciar después de editar `/etc/fstab`, siempre ejecutar `mount -a` para detectar errores sin necesidad de reiniciar. Si da error, corregir antes de reiniciar.

---

## Problema 2: "No space left on device" con espacio libre aparente

**Síntoma**: Las aplicaciones fallan con `No space left on device`, pero `df -h` muestra espacio disponible.

**Causa más frecuente**: Se han agotado los **inodos**, no el espacio en bloques. Cada archivo ocupa un inodo (una entrada de directorio), y los sistemas de ficheros tienen un número máximo de inodos. Esto ocurre cuando hay millones de archivos pequeños (logs, sesiones de PHP, caches).

```bash
# Verificar uso de inodos:
df -i

# Salida problemática:
# Filesystem      Inodes  IUsed   IFree IUse% Mounted on
# /dev/sda1      1048576 1048576      0  100% /    ← 100% de inodos usados
```

**Solución**:

```bash
# Encontrar el directorio con más archivos:
find / -xdev -printf '%h\n' | sort | uniq -c | sort -rn | head -10

# Si son logs de PHP sessions:
ls /var/lib/php/sessions/ | wc -l   # Ver cuántas hay
find /var/lib/php/sessions/ -type f -mtime +7 -delete  # Borrar las de más de 7 días

# Si son logs del sistema acumulados:
journalctl --disk-usage
journalctl --vacuum-time=7d   # Mantener solo los últimos 7 días
```

**Causa alternativa**: El sistema de ficheros está realmente lleno pero en un LV diferente al que muestra `df`.

```bash
# Ver TODOS los sistemas de ficheros incluyendo los que no están en /dev:
df -h --output=source,size,used,avail,pcent,target
```

---

## Problema 3: El cliente NFS no puede montar el directorio

**Síntoma**: `mount: /mnt/nfs_comp: bad option; for several filesystems (e.g. nfs, cifs) you might need a /sbin/mount.<type> helper program`

**Causa**: Faltan las utilidades de cliente NFS en el sistema.

```bash
# En Fedora/RHEL:
sudo dnf install nfs-utils

# En Debian/Ubuntu/Mint:
sudo apt install nfs-common
```

---

**Síntoma**: `mount.nfs: Connection timed out`

**Causa**: El servidor NFS no está accesible. Puede ser firewall, el servicio no está corriendo, o un problema de red.

```bash
# 1. Verificar conectividad básica:
ping 192.168.11.143

# 2. Verificar que el servicio NFS está corriendo en el servidor:
# (En el servidor Mint)
sudo systemctl status nfs-kernel-server

# 3. Verificar que el puerto NFS está abierto:
# (Desde el cliente)
nc -zv 192.168.11.143 2049
# Si dice "succeeded", el puerto está abierto
# Si dice "refused" o timeout, el firewall está bloqueando

# 4. Ver qué exporta el servidor:
showmount -e 192.168.11.143
```

---

**Síntoma**: `mount.nfs: access denied by server while mounting`

**Causa**: La IP del cliente no está en `/etc/exports` del servidor, o la ruta exportada es incorrecta.

```bash
# En el servidor:
# 1. Verificar el contenido de exports:
cat /etc/exports

# 2. Verificar qué se está exportando activamente:
sudo exportfs -v

# 3. Si la IP del cliente no aparece, editar exports y recargar:
sudo nano /etc/exports
sudo exportfs -ra
```

---

## Problema 4: El LV no se puede extender

**Síntoma**: `Insufficient free space: X extents needed, but only Y available`

**Causa**: El Volume Group no tiene suficiente espacio libre para extender el LV.

```bash
# Ver cuánto espacio libre hay en el VG:
vgdisplay vg_datos | grep "Free"
# o
vgs

# Si el VG no tiene espacio libre, hay que añadir un disco:
# 1. Preparar el nuevo disco como PV:
sudo pvcreate /dev/sdf

# 2. Añadir el PV al VG:
sudo vgextend vg_datos /dev/sdf

# 3. Ahora sí extender el LV:
sudo lvextend -L +50G /dev/vg_datos/lv_mysql

# 4. Extender el sistema de ficheros:
sudo xfs_growfs /var/lib/mysql     # Para XFS
sudo resize2fs /dev/vg_datos/lv_mysql  # Para ext4
```

---

## Problema 5: xfs_growfs dice "is not a mount point"

**Síntoma**: `xfs_growfs: /dev/vg_datos/lv_mysql is not a mount point`

**Causa**: `xfs_growfs` necesita el **punto de montaje**, no el dispositivo.

```bash
# Incorrecto:
sudo xfs_growfs /dev/vg_datos/lv_mysql

# Correcto:
sudo xfs_growfs /var/lib/mysql
# (usar la ruta donde está montado, no el dispositivo)
```

---

## Problema 6: RAID degradado después de reiniciar

**Síntoma**: Al reiniciar, `cat /proc/mdstat` muestra el RAID en estado degradado aunque todos los discos físicos están presentes.

**Causa frecuente**: El archivo `/etc/mdadm/mdadm.conf` no está actualizado, o el initramfs no lo incluye.

```bash
# Ver el estado actual:
sudo mdadm --detail /dev/md0

# Actualizar mdadm.conf con la configuración actual:
sudo mdadm --detail --scan | sudo tee /etc/mdadm/mdadm.conf

# Actualizar initramfs para que incluya la nueva configuración:
sudo update-initramfs -u   # Debian/Ubuntu
sudo dracut --force        # Fedora/RHEL

# Reiniciar y verificar:
reboot
cat /proc/mdstat
```

---

## Problema 7: "WARNING: journal is not clean" al montar ext4

**Síntoma**: Al montar un volumen ext4 aparece el aviso sobre journal no limpio, y el montaje se realiza en solo lectura.

**Causa**: El sistema de ficheros no se desmontó correctamente (apagado brusco, fallo de hardware). El journaling detecta que hay operaciones sin terminar.

```bash
# El sistema hace una comprobación automática con e2fsck, pero si no ocurre:
# 1. Desmontar si está montado:
sudo umount /dev/vg_datos/lv_datos

# 2. Ejecutar comprobación y reparación:
sudo e2fsck -f /dev/vg_datos/lv_datos

# 3. Volver a montar:
sudo mount /dev/vg_datos/lv_datos /mnt/datos
```

XFS maneja esto de forma automática en el siguiente montaje: reproduce el journal y queda limpio sin intervención manual.

---

## Problema 8: Escrituras muy lentas en NFS

**Síntoma**: Copiar archivos al directorio NFS es mucho más lento de lo esperado, y la escritura va en ráfagas con pausas largas.

**Causa probable**: La opción `sync` en el servidor, combinada con escrituras pequeñas, causa mucha latencia. Cada escritura espera confirmación de disco antes de responder al cliente.

```bash
# En el cliente, montar con la opción noatime y tamaño de buffer mayor:
sudo mount -t nfs -o rw,sync,noatime,rsize=131072,wsize=131072 \
    192.168.11.143:/srv/nfs/compartido /mnt/nfs_compartido

# Actualizar en fstab:
192.168.11.143:/srv/nfs/comp  /mnt/nfs_comp  nfs  rw,sync,noatime,rsize=131072,wsize=131072  0  0
```

Para NFS en LAN donde la velocidad importa más que la durabilidad estricta, se puede cambiar `sync` por `async` en el servidor, pero con la advertencia de que en caso de caída del servidor, puede haber datos sin confirmar en el buffer.

---

## Herramientas de diagnóstico generales

```bash
# Ver errores de hardware en tiempo real:
sudo dmesg | grep -i -E "error|fail|warn|ata|sd[a-z]"

# Ver los últimos eventos del sistema:
journalctl -xe

# Ver si hay errores de I/O en los logs:
grep -i "I/O error" /var/log/syslog

# Estado de todos los discos en una línea:
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,STATE

# Mapa completo del almacenamiento:
lsblk
pvs && vgs && lvs
cat /proc/mdstat
df -h
```

---

*Anterior: [Backup y recuperación](08-backup-y-recuperacion.md) · Ver también: [Comandos de referencia](../refs/comandos-referencia.md)*
