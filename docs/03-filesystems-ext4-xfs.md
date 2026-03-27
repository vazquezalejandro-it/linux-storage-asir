# 📁 Sistemas de Ficheros: ext4 vs XFS

> El sistema de ficheros es la capa que organiza cómo se guardan y recuperan los datos dentro de un volumen. Elegir el correcto no es un detalle menor: puede marcar la diferencia en rendimiento, recuperación ante fallos y facilidad de gestión.

---

## ¿Qué es un sistema de ficheros?

Cuando formateas un disco o un LV, no estás borrando datos de forma especial: estás escribiendo una estructura de control que le dice al sistema operativo cómo organizar los datos que vendrán después.

Un sistema de ficheros responde a preguntas como:
- ¿Dónde empieza y termina cada archivo?
- ¿Qué nombre tiene?
- ¿Quién es el propietario y qué permisos tiene?
- ¿Cuándo fue modificado por última vez?
- ¿Cómo se agrupan los bloques físicos?

Linux soporta docenas de sistemas de ficheros. Los dos más relevantes en producción hoy en día son **ext4** y **XFS**.

---

## ext4 — El sistema de ficheros de propósito general

### ¿Qué es?
ext4 (fourth extended filesystem) es la evolución de ext3 y ext2, que llevan décadas siendo el estándar de Linux. Es el sistema de ficheros por defecto en Ubuntu, Debian y la mayoría de distros de la familia Debian.

### Características clave

- **Journaling**: registra operaciones pendientes en un diario antes de ejecutarlas. Si el sistema se apaga de golpe, al reiniciar se reproduce el diario y el sistema de ficheros queda consistente.
- **Extensiones (extents)**: en lugar de rastrear cada bloque individual de un archivo, trabaja con rangos contiguos de bloques, lo que es más eficiente.
- **Gestión de inodos flexible**: se pueden crear más inodos (entradas de directorio) si son necesarios.
- **Permite reducir (shrink)**: con `resize2fs` puedes reducir el tamaño de un ext4 desmontado. Esta es una ventaja importante sobre XFS.
- **Tamaño máximo de fichero**: 16 TB.
- **Tamaño máximo del sistema de ficheros**: 1 EB.

### Cuándo usarlo
- Sistema operativo (partición raíz `/`).
- Servidores web con archivos pequeños y medianos (PHP, Python, etc.).
- Entornos donde la flexibilidad de poder reducir el volumen es importante.
- Uso general donde no hay requisitos extremos de rendimiento con escritura concurrente.

```bash
# Crear un ext4 en un LV:
mkfs.ext4 /dev/vg_sistema/lv_root

# Ampliar (LV ya extendido previamente):
resize2fs /dev/vg_sistema/lv_root

# Reducir (requiere desmontar primero):
umount /dev/vg_sistema/lv_datos
e2fsck -f /dev/vg_sistema/lv_datos   # comprobar integridad
resize2fs /dev/vg_sistema/lv_datos 10G
```

---

## XFS — El sistema de ficheros para cargas intensivas

### ¿Qué es?
XFS fue desarrollado originalmente por Silicon Graphics (SGI) en los años 90 para sus estaciones de trabajo de gráficos, que manejaban archivos enormes. Red Hat adoptó XFS como sistema de ficheros por defecto a partir de RHEL 7 (2014), y hoy es el estándar en todo el ecosistema Red Hat (RHEL, Rocky Linux, AlmaLinux, Fedora, CentOS Stream).

### Características clave

- **Journaling de metadatos de alto rendimiento**: el journaling de XFS está diseñado para minimizar la latencia en escrituras concurrentes, especialmente con muchos hilos de I/O simultáneos.
- **Delayed allocation**: XFS no asigna bloques de disco inmediatamente cuando se escribe en un archivo. Espera a tener más contexto para hacer asignaciones más eficientes y contiguas. Ideal para archivos grandes.
- **Escrituras paralelas masivas**: está diseñado desde el principio para manejar múltiples escrituras simultáneas sin que se conviertan en un cuello de botella.
- **Sin límite práctico de tamaño de fichero**: puede manejar ficheros de hasta 8 EB.
- **Tamaño máximo del sistema de ficheros**: 8 EB en 64 bits.
- **Solo permite crecer (no reducir)**: esta es la contrapartida. Una vez formateado y montado, XFS solo puede expandirse, nunca reducirse.

### Cuándo usarlo
- Bases de datos (MySQL, PostgreSQL, MariaDB, MongoDB).
- Servidores de almacenamiento masivo (NAS, SAN).
- Sistemas de logs con escrituras muy frecuentes (`/var/log` en servidores de alta actividad).
- Virtualización (almacén de imágenes de VMs).
- Cualquier carga de trabajo con ficheros grandes y muchas escrituras concurrentes.

```bash
# Crear un XFS en un LV:
mkfs.xfs /dev/vg_datos/lv_mysql

# Ampliar (LV ya extendido previamente, puede hacerse en caliente):
xfs_growfs /var/lib/mysql   # se usa el punto de montaje, no el dispositivo

# Información del sistema de ficheros:
xfs_info /var/lib/mysql
```

---

## Comparativa directa

| Característica | ext4 | XFS |
|----------------|------|-----|
| Familia Linux | Debian (Ubuntu, Mint...) | Red Hat (Fedora, Rocky, RHEL...) |
| Año de diseño | 2008 | 1994 (para grandes datos) |
| Journaling | Sí | Sí (más avanzado para concurrencia) |
| Escrituras concurrentes | Moderado | Excelente |
| Archivos grandes | Bien | Muy bien |
| Tamaño máximo fichero | 16 TB | 8 EB |
| Puede crecer en caliente | Sí | Sí |
| Puede reducirse | **Sí** (desmontado) | **No** |
| Uso recomendado | SO, web, uso general | BBDD, logs, almacenamiento masivo |
| Comando de crecimiento | `resize2fs` | `xfs_growfs` |

---

## El punto crítico: shrink

La diferencia más práctica entre ext4 y XFS en el día a día es la posibilidad de reducir:

- **ext4**: puedes reducir el LV desmontando el volumen, comprobando su integridad con `e2fsck` y luego ejecutando `resize2fs`. Es un proceso delicado pero posible.
- **XFS**: no hay soporte para reducción. Si te equivocas en el tamaño inicial, la única opción es hacer backup, borrar y reformatear.

Esto no significa que ext4 sea "mejor" para todo. Significa que para volúmenes de datos críticos donde el tamaño puede no estar bien calculado desde el principio, hay que pensar bien qué sistema de ficheros usar.

---

## Recomendaciones prácticas

```
¿Qué monto aquí?

├── Sistema operativo (/) → ext4
│
├── Servidor web (html, PHP, static files) → ext4
│
├── Base de datos (MySQL, PostgreSQL) → XFS ← aquí la diferencia importa
│
├── Logs de alta actividad (/var/log) → XFS
│
├── Almacenamiento masivo / NAS → XFS
│
└── ¿No sé cuánto espacio voy a necesitar? → ext4 (más flexible para ajustar)
```

---

## Una nota sobre Btrfs y otros

Existen otros sistemas de ficheros en Linux, como **Btrfs** (que incorpora snapshots y RAID propio), **ZFS** (muy potente, con licencia diferente), o **NTFS** (para compatibilidad con Windows). En el contexto de servidores Linux de producción en 2024, la elección práctica es casi siempre ext4 o XFS dependiendo del caso de uso.

---

*Anterior: [LVM](02-lvm.md) · Siguiente: [Pila de almacenamiento](04-pila-almacenamiento.md)*
