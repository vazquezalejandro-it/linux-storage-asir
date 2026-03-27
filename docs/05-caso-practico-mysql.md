# 🛢️ Caso Práctico: Diseño de Almacenamiento para MySQL

> Este documento no es una receta. Es una decisión razonada. El objetivo es explicar **por qué** se elige cada tecnología para un servidor de base de datos MySQL en producción, no solo qué comandos ejecutar.

---

## El escenario

Tenemos que poner en producción un servidor MySQL para una aplicación web de tamaño medio:
- ~100 GB de datos iniciales.
- Crecimiento estimado de 20-30 GB por año.
- Alta disponibilidad requerida: no se puede permitir pérdida de datos.
- Rendimiento: la aplicación hace muchas escrituras (inserts/updates frecuentes).
- Servidor físico con 4 discos de 500 GB disponibles.

---

## La decisión: RAID 10 + LVM + XFS

La elección final es la siguiente pila:

```
┌──────────────────────────────────┐
│   Sistema de ficheros: XFS       │
│   Montado en: /var/lib/mysql     │
└────────────────┬─────────────────┘
                 │
┌────────────────▼─────────────────┐
│   LVM Logical Volume             │
│   lv_mysql  (150 GB inicial)     │
│   → puede crecer sin parar MySQL │
└────────────────┬─────────────────┘
                 │
┌────────────────▼─────────────────┐
│   LVM Volume Group               │
│   vg_mysql (sobre /dev/md0)      │
└────────────────┬─────────────────┘
                 │
┌────────────────▼─────────────────┐
│   RAID 10  (/dev/md0)            │
│   mdadm: 4 discos en 2 espejos   │
└────────────────┬─────────────────┘
                 │
     ┌───────────┴────────────┐
┌────▼────┐              ┌────▼────┐
│ sdb+sdc │              │ sdd+sde │
│ Espejo1 │              │ Espejo2 │
└─────────┘              └─────────┘
```

---

## Por qué RAID 10 y no otro nivel

### Descartar RAID 0
RAID 0 da máximo rendimiento pero **cero tolerancia a fallos**. Un servidor de BBDD con RAID 0 es una bomba de relojería. Descartado.

### Descartar RAID 1
RAID 1 con 4 discos desperdiciaría espacio (50%) y no daría el rendimiento de lectura paralela que una BBDD activa necesita. Con 4 discos disponibles, hay opciones mejores.

### Descartar RAID 5/6
RAID 5 y 6 sufren de **penalización en escrituras aleatorias pequeñas**: para cada escritura, hay que leer los datos actuales, calcular la nueva paridad y escribir tanto los datos como la paridad. Las bases de datos hacen exactamente este tipo de escrituras constantemente (cada INSERT, UPDATE, commit de transacción). Además, la reconstrucción tras un fallo con discos grandes puede durar horas, durante las cuales el rendimiento cae dramáticamente.

### RAID 10: lo mejor de ambos mundos para BBDD

RAID 10 con 4 discos nos da:
- **Striping**: la carga de I/O se distribuye entre 2 espejos → mayor rendimiento.
- **Espejo**: cada disco tiene su copia → tolerancia a fallos inmediata.
- **Reconstrucción rápida**: si un disco falla, la reconstrucción consiste solo en copiar el espejo → horas frente a días del RAID 5/6.
- **Sin penalización de escritura por paridad**: las escrituras van directas a los espejos, sin cálculo de paridad.

La contrapartida es el coste: solo aprovechamos el 50% del espacio (4×500 GB = 1 TB útil). Pero para una BBDD de producción crítica, ese coste es completamente aceptable.

---

## Por qué LVM encima del RAID

Una vez que tenemos el RAID montado (`/dev/md0`), podríamos simplemente formatearlo y montarlo directamente. Entonces, ¿por qué añadir LVM?

**Razón principal: el futuro.**

En 18 meses, la base de datos ha crecido más de lo previsto y el LV está al 90% de capacidad. Sin LVM, las opciones son:
- Parar MySQL, mover datos, reformatear → inaceptable en producción.
- Añadir un servidor más → posible, pero complejo.

Con LVM:
```bash
# Añadir un quinto disco al sistema:
pvcreate /dev/sdf
vgextend vg_mysql /dev/sdf

# Ampliar el LV en caliente (MySQL sigue corriendo):
lvextend -L +100G /dev/vg_mysql/lv_mysql
xfs_growfs /var/lib/mysql

# MySQL no se ha reiniciado. El espacio ha crecido.
```

LVM también facilita la gestión de múltiples volúmenes: datos de MySQL en un LV, logs binarios en otro LV diferente (lo que permite gestionar el espacio de cada uno de forma independiente).

---

## Por qué XFS y no ext4

MySQL realiza un patrón de I/O muy específico:
- Escrituras frecuentes y aleatorias (inserts, updates de índices, commits de transacciones).
- Lecturas de filas individuales o rangos.
- Archivos de datos (`.ibd`) que pueden crecer a decenas de GB.
- Ficheros de redo log que se escriben constantemente.

XFS está optimizado para exactamente este patrón:
- El journaling de XFS tiene menor latencia en escrituras concurrentes que ext4.
- La asignación diferida (delayed allocation) agrupa las escrituras de forma más eficiente.
- Escala mejor con múltiples hilos de I/O (lo que MySQL genera con conexiones paralelas).

La única contrapartida de XFS es que no se puede reducir. Pero en un servidor de BBDD que solo crece, esto no es un problema real.

---

## Implementación paso a paso

### 1. Crear el RAID 10

```bash
# Los 4 discos que usaremos para el RAID:
# /dev/sdb, /dev/sdc, /dev/sdd, /dev/sde

mdadm --create /dev/md0 \
  --level=10 \
  --raid-devices=4 \
  /dev/sdb /dev/sdc /dev/sdd /dev/sde

# Verificar estado del RAID:
cat /proc/mdstat
mdadm --detail /dev/md0
```

### 2. Configurar LVM sobre el RAID

```bash
# Crear el PV sobre el dispositivo RAID:
pvcreate /dev/md0

# Crear el Volume Group:
vgcreate vg_mysql /dev/md0

# Crear el Logical Volume (150 GB inicial):
lvcreate -L 150G -n lv_mysql vg_mysql
lvcreate -L 10G  -n lv_binlog vg_mysql   # Para binary logs de MySQL
```

### 3. Formatear con XFS

```bash
# Formatear el LV de datos:
mkfs.xfs /dev/vg_mysql/lv_mysql

# Formatear el LV de binary logs:
mkfs.xfs /dev/vg_mysql/lv_binlog
```

### 4. Montar y configurar persistencia

```bash
# Crear los puntos de montaje:
mkdir -p /var/lib/mysql
mkdir -p /var/lib/mysql-binlog

# Montar:
mount /dev/vg_mysql/lv_mysql    /var/lib/mysql
mount /dev/vg_mysql/lv_binlog   /var/lib/mysql-binlog

# Añadir a /etc/fstab para persistencia:
echo '/dev/vg_mysql/lv_mysql      /var/lib/mysql         xfs    defaults    0 0' >> /etc/fstab
echo '/dev/vg_mysql/lv_binlog     /var/lib/mysql-binlog  xfs    defaults    0 0' >> /etc/fstab

# Verificar que fstab es correcto:
mount -a
```

### 5. Configurar permisos para MySQL

```bash
# MySQL necesita ser propietario de sus directorios:
chown -R mysql:mysql /var/lib/mysql
chown -R mysql:mysql /var/lib/mysql-binlog
```

---

## Gestión del crecimiento futuro

### Escenario: el LV de datos está al 85%

```bash
# Ver estado actual:
df -h /var/lib/mysql
lvs

# Si el VG tiene espacio libre → ampliar directamente:
lvextend -L +50G /dev/vg_mysql/lv_mysql
xfs_growfs /var/lib/mysql   # ← en caliente, MySQL sigue corriendo

# Si el VG no tiene espacio libre → añadir un disco:
pvcreate /dev/sdf
vgextend vg_mysql /dev/sdf
# Y luego el lvextend de arriba
```

---

## Resumen de decisiones

| Componente | Elección | Razón |
|------------|----------|-------|
| RAID | **RAID 10** | Rendimiento + tolerancia a fallos + reconstrucción rápida |
| Gestión de volúmenes | **LVM** | Crecimiento en caliente sin parar MySQL |
| Sistema de ficheros | **XFS** | Optimizado para escrituras concurrentes e intensivas |
| Punto de montaje | `/var/lib/mysql` | Estándar de MySQL, limpio y predecible |
| Persistencia | `/etc/fstab` | El servidor debe sobrevivir a un reinicio |

---

## ¿Y si es para un servidor web en lugar de una BBDD?

La elección cambia:
- **RAID 1** podría ser suficiente (menos I/O concurrente, archivos pequeños).
- **LVM** sigue siendo recomendable para la flexibilidad.
- **ext4** es una opción perfectamente válida (archivos PHP, HTML, etc.) y tiene la ventaja de poder reducir si hace falta.

La clave es siempre analizar el **patrón de I/O** del servicio antes de decidir.

---

*Anterior: [Pila de almacenamiento](04-pila-almacenamiento.md) · Ver también: [Lab NFS](../labs/04-nfs-lab-mint-fedora.md)*
