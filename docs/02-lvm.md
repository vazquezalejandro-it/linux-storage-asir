# 📦 LVM — Logical Volume Manager

> LVM resuelve uno de los problemas más frustrantes del almacenamiento tradicional: "me he quedado sin espacio y no puedo crecer sin parar el servicio y reparticionar". Con LVM, eso deja de ser un problema.

---

## El problema que resuelve LVM

Imagina que has instalado un servidor con un disco de 100 GB y has montado `/var` con 20 GB porque en aquel momento parecía suficiente. Seis meses después, los logs y la base de datos han llenado esos 20 GB y el servicio empieza a fallar.

Sin LVM, las opciones son:
1. Reparticionar → parar el servidor, reorganizar, rezar.
2. Añadir un disco y crear una partición nueva → pero eso no "amplía" `/var`, solo da un nuevo punto de montaje.

Con LVM:
1. Añades el nuevo disco al grupo de volúmenes.
2. Extiendes el volumen lógico de `/var` con un comando.
3. Amplías el sistema de ficheros en caliente.
4. El servidor no se ha detenido en ningún momento.

---

## Los tres niveles de LVM

LVM introduce una capa de abstracción entre el hardware y el sistema de ficheros, organizada en tres niveles:

```
┌─────────────────────────────────────────────┐
│            Sistema de ficheros               │
│          (ext4, XFS, etc.)                  │
└─────────────────┬───────────────────────────┘
                  │
┌─────────────────▼───────────────────────────┐
│         Logical Volume (LV)                  │
│  /dev/vg_datos/lv_mysql  (tamaño flexible)  │
└─────────────────┬───────────────────────────┘
                  │
┌─────────────────▼───────────────────────────┐
│         Volume Group (VG)                    │
│   vg_datos  ← la "piscina" de espacio       │
│   [████████████████████░░░░░░░░░░░░░░░░]    │
│   60 GB usados              40 GB libres    │
└─────────────────┬───────────────────────────┘
                  │
┌─────────────────▼───────────────────────────┐
│         Physical Volume (PV)                 │
│  /dev/sdb  +  /dev/sdc  +  /dev/sdd        │
│  (discos físicos o particiones reales)       │
└─────────────────────────────────────────────┘
```

---

## Physical Volume (PV) — El ladrillo

Un PV es un disco físico o una partición que has "entregado" a LVM para que lo gestione. A partir de ese momento, LVM lo trata como un recurso de espacio que puede usar libremente.

```bash
# Convertir un disco en PV:
pvcreate /dev/sdb
pvcreate /dev/sdc

# Ver PVs del sistema:
pvs
pvdisplay
```

> Una vez que un disco es un PV de LVM, no debes tocar sus particiones directamente. LVM lleva su propia contabilidad interna.

---

## Volume Group (VG) — La piscina de espacio

El VG agrupa uno o varios PVs en un único pool de espacio. Puedes pensar en él como una piscina: los PVs son el agua que entra, y de esa piscina vas sacando trozos para cada servicio.

```bash
# Crear un VG llamado "vg_datos" con dos discos:
vgcreate vg_datos /dev/sdb /dev/sdc

# Ver VGs:
vgs
vgdisplay vg_datos
```

Si necesitas más espacio en el futuro, solo tienes que añadir un nuevo PV al VG:

```bash
pvcreate /dev/sdd
vgextend vg_datos /dev/sdd
```

El VG crece sin afectar a los LVs que ya existen dentro de él.

---

## Logical Volume (LV) — El trozo que usas

Un LV es lo que el sistema operativo ve como si fuera un disco o una partición. Es un "corte" del espacio disponible en el VG. Sobre él se formatea un sistema de ficheros y se monta en un directorio.

```bash
# Crear un LV de 20 GB llamado "lv_mysql" en el VG "vg_datos":
lvcreate -L 20G -n lv_mysql vg_datos

# Ver LVs:
lvs
lvdisplay

# El LV aparece como un dispositivo de bloque en:
# /dev/vg_datos/lv_mysql
# o equivalentemente: /dev/mapper/vg_datos-lv_mysql
```

---

## Ejemplo completo: crear un volumen para MySQL

```bash
# 1. Preparar los PVs (asumiendo que tenemos /dev/sdb y /dev/sdc vírgenes)
pvcreate /dev/sdb /dev/sdc

# 2. Crear el VG con esos dos discos
vgcreate vg_datos /dev/sdb /dev/sdc

# 3. Crear un LV de 50 GB para los datos de MySQL
lvcreate -L 50G -n lv_mysql vg_datos

# 4. Formatear con XFS (ideal para BBDD)
mkfs.xfs /dev/vg_datos/lv_mysql

# 5. Montar
mkdir -p /var/lib/mysql
mount /dev/vg_datos/lv_mysql /var/lib/mysql

# 6. Persistencia en fstab
echo '/dev/vg_datos/lv_mysql /var/lib/mysql xfs defaults 0 0' >> /etc/fstab
```

---

## Crecer un LV en caliente

Esta es la operación más valiosa de LVM. El servicio sigue corriendo mientras amplías el espacio.

```bash
# El VG tiene espacio libre. Ampliar el LV en 10 GB:
lvextend -L +10G /dev/vg_datos/lv_mysql

# Ahora hay que decirle al sistema de ficheros que el LV es más grande:
# Con XFS:
xfs_growfs /var/lib/mysql

# Con ext4:
resize2fs /dev/vg_datos/lv_mysql
```

> Con XFS no puedes reducir el LV (solo crecer). Con ext4 puedes reducir, pero necesitas desmontar el sistema de ficheros antes.

---

## LVM sobre RAID

En entornos de producción, LVM no reemplaza a RAID: se pone **encima** de él.

```
┌───────────────────────────────────────┐
│           Sistema de ficheros         │
│              (ext4 / XFS)             │
└──────────────────┬────────────────────┘
                   │
┌──────────────────▼────────────────────┐
│              LVM (LV / VG)            │
│      gestión flexible del espacio     │
└──────────────────┬────────────────────┘
                   │
┌──────────────────▼────────────────────┐
│         RAID 10 (mdadm)               │
│   rendimiento + tolerancia a fallos   │
└──────────────────┬────────────────────┘
                   │
        ┌──────────┴──────────┐
        │                     │
   ┌────▼────┐           ┌────▼────┐
   │ Espejo 1│           │ Espejo 2│
   │ D1 + D2 │           │ D3 + D4 │
   └─────────┘           └─────────┘
```

La lógica es:
- **RAID** garantiza que los datos sobreviven a fallos de hardware.
- **LVM** garantiza que puedes gestionar el espacio sin parar el sistema.

Son complementarios, no excluyentes.

---

## Comandos de diagnóstico útiles

```bash
# Ver resumen de todos los componentes LVM:
pvs && vgs && lvs

# Ver espacio disponible en un VG:
vgdisplay vg_datos | grep "Free"

# Ver a qué LV pertenece un punto de montaje:
df -h /var/lib/mysql

# Ver el mapa completo LV → VG → PV:
lsblk
```

---

## Resumen conceptual

| Concepto | Analogía | Comando clave |
|----------|----------|---------------|
| PV | Ingrediente (un disco) | `pvcreate` |
| VG | La piscina (suma de discos) | `vgcreate`, `vgextend` |
| LV | Un cubo de agua de la piscina | `lvcreate`, `lvextend` |
| FS | Lo que pones dentro del cubo | `mkfs.xfs`, `mkfs.ext4` |

---

*Anterior: [RAID](01-raid.md) · Siguiente: [Sistemas de ficheros](03-filesystems-ext4-xfs.md)*
