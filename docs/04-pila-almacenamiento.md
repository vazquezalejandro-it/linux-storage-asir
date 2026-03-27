# 🔗 La Pila de Almacenamiento en Linux

> Antes de trabajar con discos, RAID, LVM o NFS, conviene tener claro el mapa completo. ¿Cómo viaja un dato desde los platos físicos de un disco hasta convertirse en un archivo que puede abrir una aplicación?

---

## Visión global

Linux organiza el almacenamiento en capas. Cada capa añade una abstracción que hace la capa superior más flexible e independiente del hardware:

```
┌──────────────────────────────────────────────────────────────────┐
│                        APLICACIÓN / USUARIO                       │
│                 cat /var/lib/mysql/datos.ibd                     │
└────────────────────────────┬─────────────────────────────────────┘
                             │
┌────────────────────────────▼─────────────────────────────────────┐
│                    PUNTO DE MONTAJE                               │
│              /var/lib/mysql  →  "aquí está montado ese disco"    │
└────────────────────────────┬─────────────────────────────────────┘
                             │
┌────────────────────────────▼─────────────────────────────────────┐
│                    SISTEMA DE FICHEROS                            │
│                     XFS / ext4                                   │
│      "sé cómo guardar, buscar y recuperar archivos en bloques"   │
└────────────────────────────┬─────────────────────────────────────┘
                             │
┌────────────────────────────▼─────────────────────────────────────┐
│                     LVM (opcional)                               │
│           Logical Volume: /dev/vg_datos/lv_mysql                 │
│       "soy un volumen virtual de tamaño ajustable"               │
└────────────────────────────┬─────────────────────────────────────┘
                             │
┌────────────────────────────▼─────────────────────────────────────┐
│                     RAID (opcional)                              │
│           /dev/md0  ← RAID 10 sobre 4 discos físicos            │
│     "soy un disco virtual con rendimiento y redundancia"         │
└────────────────────────────┬─────────────────────────────────────┘
                             │
┌────────────────────────────▼─────────────────────────────────────┐
│                   HARDWARE (DISCOS FÍSICOS)                      │
│            /dev/sda  /dev/sdb  /dev/sdc  /dev/sdd               │
│       HDD, SSD, NVMe — los platos y celdas reales               │
└──────────────────────────────────────────────────────────────────┘
```

---

## El viaje de un dato

Vamos a seguir a un dato desde que la aplicación lo escribe hasta que llega al disco:

### 1. La aplicación escribe

```python
# Una aplicación Python escribe en un archivo:
with open('/var/lib/mysql/datos.ibd', 'a') as f:
    f.write('nueva_fila_de_datos')
```

La aplicación no sabe nada de discos, inodos, bloques ni RAID. Solo conoce la ruta `/var/lib/mysql/datos.ibd`.

---

### 2. El kernel resuelve el punto de montaje

El kernel de Linux mira en su tabla de montajes (que viene de `/etc/fstab` y de los montajes activos) y determina:

> "La ruta `/var/lib/mysql` está montada sobre el dispositivo `/dev/vg_datos/lv_mysql`."

Aquí entra en juego `/etc/fstab`, que es el "mapa de carreteras" del sistema de almacenamiento. Cada línea dice: *"este dispositivo va montado en este directorio, con este sistema de ficheros y estas opciones"*.

```
# Ejemplo de línea en /etc/fstab:
/dev/vg_datos/lv_mysql    /var/lib/mysql    xfs    defaults    0 0
```

---

### 3. El sistema de ficheros organiza los datos

El driver de XFS (o ext4) recibe la petición de escritura y:
- Busca bloques libres en el dispositivo.
- Actualiza el inodo del archivo (metadatos: tamaño, fecha de modificación, propietario).
- Escribe los bloques de datos.
- Si hay journaling activo, registra primero en el journal para garantizar consistencia.

El sistema de ficheros trabaja con el concepto de **bloques** (normalmente de 4 KB). Un archivo de 100 KB ocupa aproximadamente 25 bloques.

---

### 4. LVM traduce las direcciones lógicas en físicas

El sistema de ficheros ha dicho "escribe en el bloque 1500 del dispositivo `/dev/vg_datos/lv_mysql`". Pero ese dispositivo es un Logical Volume de LVM.

LVM sabe que el LV `lv_mysql` está compuesto por Physical Extents (PEs) repartidos entre los discos físicos que forman el Volume Group. Traduce la dirección lógica en la dirección física concreta de qué disco y qué offset.

---

### 5. RAID distribuye o espeja los bloques

Si hay RAID por debajo del LVM, el dispositivo RAID recibe la petición de escritura y la ejecuta según su configuración:

- **RAID 1**: escribe en ambos discos del espejo simultáneamente.
- **RAID 10**: escribe en el par correspondiente del striping y su espejo.
- **RAID 5/6**: calcula y distribuye los bloques de paridad.

---

### 6. El disco físico almacena los bits

Finalmente, el controlador de disco y el firmware del hardware escriben los bits en las celdas NAND (SSD) o mueven el cabezal para escribir en los platos magnéticos (HDD).

---

## Puntos de montaje en Linux: sin letras de unidad

Una de las diferencias más importantes entre Linux y Windows es cómo se expone el almacenamiento al usuario:

**Windows:**
```
C:\  →  Disco del sistema
D:\  →  Segundo disco o partición
E:\  →  DVD o USB
```

**Linux:**
```
/           →  Raíz del sistema (todo cuelga de aquí)
/home       →  Directorios de usuarios (puede ser otro disco)
/var        →  Logs, bases de datos, colas de correo...
/var/lib/mysql  →  Podría estar en su propio disco/LV
/mnt/nfs    →  Un directorio remoto montado por NFS
```

En Linux, el almacenamiento no tiene letras. Todo es un directorio. Que ese directorio esté respaldado por un disco local, un LV de LVM, un volumen RAID o una carpeta remota de NFS es transparente para la aplicación que accede a él.

Esta uniformidad es una de las grandes fortalezas del modelo Unix/Linux.

---

## El papel de /etc/fstab

`/etc/fstab` es el archivo de configuración que define qué se monta dónde en cada arranque del sistema. Sin una entrada en fstab, un montaje no sobrevive a un reinicio.

```bash
# Estructura de una línea de fstab:
# <dispositivo>          <punto_montaje>    <tipo_fs>    <opciones>    <dump>  <pass>

/dev/vg_datos/lv_mysql   /var/lib/mysql     xfs          defaults      0       0
UUID=abc123...           /                  ext4         errors=remount-ro  0  1
192.168.11.143:/srv/nfs  /mnt/nfs_comp      nfs          defaults      0       0
```

Campos principales:
- **Dispositivo**: puede ser `/dev/...`, UUID o dirección NFS.
- **Punto de montaje**: directorio donde se accede al contenido.
- **Tipo de sistema de ficheros**: `ext4`, `xfs`, `nfs`, `swap`, etc.
- **Opciones**: `defaults`, `rw`, `noexec`, etc.
- **dump**: obsoleto, casi siempre `0`.
- **pass**: orden de comprobación al arrancar (`0` = no comprobar, `1` = primero, `2` = después).

> ⚠️ Un error en `/etc/fstab` puede impedir que el sistema arranque. Antes de reiniciar, siempre verificar con `mount -a` para detectar errores sin reiniciar.

---

## NFS: cuando el almacenamiento viene por red

La pila de almacenamiento no tiene que terminar en un disco local. Con NFS (Network File System), un directorio remoto se monta como si fuera local, y la aplicación no nota la diferencia.

```
     Servidor NFS                   Cliente NFS
   (Linux Mint .143)              (Fedora .142)
                                        
┌───────────────────┐          ┌─────────────────────┐
│  /srv/nfs/comp.   │          │  /mnt/nfs_compartido│
│  (disco local)    │◄─────────│  (montaje NFS)      │
│                   │   NFS    │                     │
│  Exportado vía    │          │  La app ve archivos │
│  /etc/exports     │          │  como si fueran     │
│                   │          │  locales            │
└───────────────────┘          └─────────────────────┘
```

El cliente monta el directorio remoto vía `/etc/fstab` igual que montaría un disco local, pero especificando el tipo `nfs` y la dirección del servidor.

---

## Resumen: las capas y su responsabilidad

| Capa | Responsabilidad | Herramientas |
|------|----------------|--------------|
| Hardware | Almacenar bits | HDD, SSD, NVMe |
| RAID | Redundancia y/o rendimiento multi-disco | `mdadm` |
| LVM | Gestión flexible del espacio en caliente | `lvcreate`, `lvextend`, `vgextend` |
| Sistema de ficheros | Organizar archivos en bloques | `mkfs.xfs`, `mkfs.ext4` |
| Punto de montaje | Integrar el almacenamiento en el árbol `/` | `mount`, `/etc/fstab` |
| Red (NFS) | Exponer almacenamiento a otros equipos | `nfs-kernel-server`, `/etc/exports` |

---

*Anterior: [Sistemas de ficheros](03-filesystems-ext4-xfs.md) · Siguiente: [Caso práctico MySQL](05-caso-practico-mysql.md)*
