# 🧪 Laboratorio LVM: Ubuntu Server

> **Laboratorio ejecutado y verificado en Ubuntu Server con VMware.**  
> El objetivo es demostrar las operaciones más importantes de LVM en la práctica: crear la estructura, formatear, montar, y extender en caliente sin parar ningún servicio.

---

## Contexto

LVM es uno de esos conceptos que parecen complicados en teoría pero que, al hacerlo en el lab, se vuelven claros en cuestión de minutos. Este laboratorio sigue ese camino: primero entender qué vamos a hacer y por qué, luego ejecutarlo paso a paso.

El escenario: tenemos un servidor Ubuntu con un disco adicional `/dev/sdb` de 20 GB. Queremos configurarlo con LVM para alojar datos de una aplicación, y demostrar que podemos extender el espacio sin reiniciar ni parar el servicio.

---

## Entorno

| Máquina | Sistema Operativo | Rol |
|---------|-------------------|-----|
| srv-linux | Ubuntu Server 22.04 | Servidor donde se hace el laboratorio |

El laboratorio asume que tienes un disco adicional disponible. En VMware, añadir un disco a una VM existente tarda menos de un minuto: VM Settings → Add → Hard Disk.

---

## Objetivo

1. Preparar el disco como Physical Volume de LVM.
2. Crear un Volume Group.
3. Crear dos Logical Volumes (datos y logs).
4. Formatear y montar ambos.
5. Configurar `/etc/fstab` para persistencia.
6. Simular que nos quedamos sin espacio y extender en caliente.

---

## Paso 1 — Verificar el disco disponible

```bash
# Ver todos los discos y su estado:
lsblk

# Salida esperada:
# NAME   MAJ:MIN RM  SIZE RO TYPE MOUNTPOINTS
# sda      8:0    0   20G  0 disk
# ├─sda1   8:1    0   19G  0 part /
# └─sda2   8:2    0    1G  0 part [SWAP]
# sdb      8:16   0   20G  0 disk   ← nuestro disco nuevo, sin particionar

# Verificar que sdb no tiene datos:
sudo fdisk -l /dev/sdb
# Debe mostrar "Disk /dev/sdb: 20 GiB" sin particiones listadas
```

> En VMware, si acabas de añadir el disco y no aparece, no hace falta reiniciar. Basta con hacer `echo "- - -" > /sys/class/scsi_host/host0/scan` para que el kernel lo detecte.

---

## Paso 2 — Instalar LVM (si no está instalado)

```bash
sudo apt update
sudo apt install -y lvm2

# Verificar que está instalado:
pvs --version
```

En Ubuntu Server moderno, `lvm2` suele estar instalado por defecto. El comando `pvs` sin error confirma que está disponible.

---

## Paso 3 — Crear el Physical Volume

```bash
sudo pvcreate /dev/sdb

# Salida esperada:
# Physical volume "/dev/sdb" successfully created.

# Verificar:
sudo pvs
# PV         VG Fmt  Attr PSize  PFree
# /dev/sdb      lvm2 ---  20.00g 20.00g
```

En este momento, LVM ha inscrito sus metadatos en el disco. El disco completo (sin necesidad de particionar) es ahora un PV. Podría haberse hecho también sobre una partición (`/dev/sdb1`), pero usar el disco directamente es válido y más simple.

---

## Paso 4 — Crear el Volume Group

```bash
sudo vgcreate vg_app /dev/sdb

# Salida esperada:
# Volume group "vg_app" successfully created

# Verificar:
sudo vgs
# VG     #PV #LV #SN Attr   VSize   VFree
# vg_app   1   0   0 wz--n- <20.00g <20.00g
```

El VG `vg_app` tiene ahora los ~20 GB del disco disponibles como piscina de espacio.

---

## Paso 5 — Crear los Logical Volumes

Vamos a crear dos LVs: uno para datos de la aplicación y otro para sus logs. Mantenerlos separados es una buena práctica: si los logs crecen descontroladamente y llenan su LV, el LV de datos sigue funcionando.

```bash
# LV para datos de la aplicación: 15 GB
sudo lvcreate -L 15G -n lv_datos vg_app

# LV para logs: 3 GB (dejamos 2 GB libres en el VG como margen)
sudo lvcreate -L 3G -n lv_logs vg_app

# Verificar:
sudo lvs
# LV       VG     Attr       LSize Pool Origin Data%  Meta%  Move Log Cpy%Sync Convert
# lv_datos vg_app -wi-a----- 15.00g
# lv_logs  vg_app -wi-a-----  3.00g
```

Los LVs aparecen como dispositivos de bloque en `/dev/vg_app/lv_datos` y `/dev/vg_app/lv_logs`.

---

## Paso 6 — Formatear los Logical Volumes

```bash
# LV de datos con XFS (buena elección para datos de aplicación):
sudo mkfs.xfs /dev/vg_app/lv_datos

# Salida:
# meta-data=/dev/vg_app/lv_datos   isize=512    agcount=4, agsize=983040 blks
# ...

# LV de logs con ext4 (logs suelen ser muchos archivos pequeños, ext4 es buena opción):
sudo mkfs.ext4 /dev/vg_app/lv_logs

# Salida:
# Creating filesystem with 786432 4k blocks and 196608 inodes
# ...
```

---

## Paso 7 — Crear los puntos de montaje y montar

```bash
# Crear los directorios:
sudo mkdir -p /opt/app/datos
sudo mkdir -p /opt/app/logs

# Montar:
sudo mount /dev/vg_app/lv_datos /opt/app/datos
sudo mount /dev/vg_app/lv_logs  /opt/app/logs

# Verificar:
df -h | grep vg_app
# /dev/mapper/vg_app-lv_datos   15G   87M   15G   1% /opt/app/datos
# /dev/mapper/vg_app-lv_logs   2.9G   24K  2.8G   1% /opt/app/logs
```

> Nota: El kernel expone los LVs también como `/dev/mapper/vg_app-lv_datos`. Es el mismo dispositivo, solo una ruta alternativa que usa el device mapper.

---

## Paso 8 — Hacer los montajes persistentes con /etc/fstab

```bash
# Ver los UUIDs de los LVs (recomendable usar UUID en vez de /dev/... para mayor robustez):
sudo blkid /dev/vg_app/lv_datos
sudo blkid /dev/vg_app/lv_logs

# Salida ejemplo:
# /dev/vg_app/lv_datos: UUID="a1b2c3d4-..." TYPE="xfs"
# /dev/vg_app/lv_logs:  UUID="e5f6a7b8-..." TYPE="ext4"

# Editar fstab:
sudo nano /etc/fstab

# Añadir al final (con los UUIDs reales del paso anterior):
/dev/vg_app/lv_datos    /opt/app/datos    xfs     defaults    0 0
/dev/vg_app/lv_logs     /opt/app/logs     ext4    defaults    0 2

# Probar sin reiniciar:
sudo umount /opt/app/datos /opt/app/logs
sudo mount -a

# Verificar que volvieron a montarse:
df -h | grep vg_app
```

---

## Paso 9 — Simular que nos quedamos sin espacio y extender en caliente

Esta es la demostración más importante del laboratorio. Simulamos que el LV de datos está casi lleno y necesitamos más espacio sin detener la aplicación.

```bash
# Ver estado actual:
df -h /opt/app/datos
# /dev/mapper/vg_app-lv_datos   15G  87M  15G  1% /opt/app/datos

# Comprobar que el VG tiene espacio libre (los 2 GB que dejamos antes):
sudo vgs
# VFree  <2.00g

# --- En este momento la "aplicación" sigue corriendo ---
# Extender el LV en 1.5 GB:
sudo lvextend -L +1.5G /dev/vg_app/lv_datos

# Salida:
# Size of logical volume vg_app/lv_datos changed from 15.00 GiB to 16.50 GiB.
# Logical volume vg_app/lv_datos successfully resized.

# Decirle al sistema de ficheros XFS que el LV ha crecido:
sudo xfs_growfs /opt/app/datos

# Salida:
# data blocks changed from 3932160 to 4325376

# Verificar el nuevo tamaño sin haber reiniciado nada:
df -h /opt/app/datos
# /dev/mapper/vg_app-lv_datos   17G  89M  17G  1% /opt/app/datos
```

✅ El LV ha pasado de 15 GB a 16.5 GB sin desmontar el sistema de ficheros, sin reiniciar el servidor y sin interrumpir ningún servicio. Esto es lo que hace que LVM sea indispensable en producción.

---

## Paso 10 — Explorar el mapa completo

Al terminar el laboratorio, el comando que da la visión más completa del estado del almacenamiento es:

```bash
lsblk
# NAME                MAJ:MIN RM  SIZE RO TYPE MOUNTPOINTS
# sda                   8:0    0   20G  0 disk
# ├─sda1                8:1    0   19G  0 part /
# └─sda2                8:2    0    1G  0 part [SWAP]
# sdb                   8:16   0   20G  0 disk
# └─vg_app-lv_datos   253:0    0 16.5G  0 lvm  /opt/app/datos
# └─vg_app-lv_logs    253:1    0    3G  0 lvm  /opt/app/logs
```

Este árbol muestra perfectamente la jerarquía: disco físico → LVM → sistema de ficheros → punto de montaje.

---

## Comandos de referencia del laboratorio

```bash
# Crear PV, VG, LV:
pvcreate /dev/sdb
vgcreate vg_app /dev/sdb
lvcreate -L 15G -n lv_datos vg_app

# Formatear y montar:
mkfs.xfs /dev/vg_app/lv_datos
mount /dev/vg_app/lv_datos /opt/app/datos

# Extender en caliente:
lvextend -L +1.5G /dev/vg_app/lv_datos
xfs_growfs /opt/app/datos              # Para XFS
resize2fs /dev/vg_app/lv_logs          # Para ext4

# Diagnóstico:
pvs && vgs && lvs
lsblk
df -h
```

---

## Conclusiones

Este laboratorio demuestra tres cosas importantes:

1. **LVM no es complicado**: el flujo `pvcreate → vgcreate → lvcreate → mkfs → mount` se vuelve natural con la práctica.

2. **La extensión en caliente es real y funciona**: sin parar servicios, sin reiniciar, sin reparticionar. Esta capacidad justifica por sí sola el uso de LVM en cualquier servidor de producción.

3. **La separación de LVs por función es una buena práctica**: datos en un LV, logs en otro. Si los logs crecen descontroladamente, no afectan a los datos. Cada volumen se puede gestionar de forma independiente.

---

*Volver al [README](../README.md) · Ver también: [LVM — documentación teórica](../docs/02-lvm.md)*
