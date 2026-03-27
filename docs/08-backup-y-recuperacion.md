# 💾 Backup y Recuperación

> RAID no es backup. Esta frase se repite tanto que ya parece un cliché, pero hay una razón: la gente sigue perdiendo datos pensando que su RAID los protege de todo. Este documento cierra el ciclo.

---

## Por qué RAID no es backup

RAID protege contra un tipo muy específico de problema: el **fallo físico de un disco**. Nada más.

RAID no protege contra:

- **Borrado accidental**: `rm -rf /var/lib/mysql` borra los datos en todos los discos del RAID simultáneamente. El RAID mantiene la consistencia de los datos, incluyendo su borrado.
- **Corrupción lógica**: Un bug en la aplicación que corrompe la base de datos lo hace igualmente en todos los discos del espejo.
- **Ransomware**: Si un ransomware cifra los archivos, el RAID cifra perfectamente la misma basura en todos sus discos.
- **Fallo del controlador RAID o la placa base**: Si el hardware que gestiona el RAID falla, puede llevarse los datos consigo.
- **Desastre físico**: Un incendio, una inundación o un robo destruye todos los discos a la vez.

Un backup real debe estar en un sistema **separado, independiente y preferiblemente en una ubicación distinta** del sistema principal.

---

## La regla 3-2-1

El estándar de facto para backup que cualquier sysadmin debe conocer:

```
3 copias de los datos
  2 en medios distintos (ejemplo: disco local + NFS)
    1 fuera del sitio (ejemplo: almacenamiento en la nube o sede alternativa)
```

En un entorno de laboratorio o pequeña empresa, una implementación práctica de 3-2-1 podría ser:
- Copia 1: Los datos originales en el servidor (RAID 10 + LVM).
- Copia 2: Backup diario en el servidor NFS de la red local.
- Copia 3: Backup semanal en almacenamiento en la nube (S3, Backblaze B2, etc.).

---

## Backup de MySQL con mysqldump

`mysqldump` es la herramienta nativa de MySQL para exportar bases de datos a archivos SQL. Es el método más sencillo y portable: el resultado es un archivo de texto con las instrucciones SQL para recrear la base de datos desde cero.

### Backup manual de una base de datos

```bash
# Backup de una base de datos específica:
mysqldump -u root -p nombre_bbdd > /tmp/backup_nombre_bbdd_$(date +%Y%m%d).sql

# Backup de todas las bases de datos:
mysqldump -u root -p --all-databases > /tmp/backup_completo_$(date +%Y%m%d).sql

# Backup con compresión (mucho más pequeño):
mysqldump -u root -p --all-databases | gzip > /tmp/backup_$(date +%Y%m%d).sql.gz
```

### Restaurar desde un backup

```bash
# Restaurar una base de datos:
mysql -u root -p nombre_bbdd < /tmp/backup_nombre_bbdd_20240315.sql

# Restaurar un backup comprimido:
gunzip < /tmp/backup_20240315.sql.gz | mysql -u root -p
```

---

## Backup automático hacia el servidor NFS

Este es el punto donde todos los elementos del repositorio convergen: usamos el servidor NFS que configuramos en el laboratorio como destino del backup de MySQL.

El flujo es:
```
MySQL (servidor Ubuntu) → mysqldump → compresión → NFS (servidor Mint) → rotación automática
```

```bash
#!/bin/bash
# Script completo en scripts/backup-mysql-to-nfs.sh

# Configuración
MYSQL_USER="backup_user"
MYSQL_PASS="password_seguro"
NFS_MOUNT="/mnt/nfs_backups"
FECHA=$(date +%Y%m%d_%H%M)
RETENTION_DAYS=7   # Mantener backups de los últimos 7 días

# Verificar que el NFS está montado
if ! mountpoint -q "$NFS_MOUNT"; then
    echo "ERROR: El servidor NFS no está montado en $NFS_MOUNT"
    exit 1
fi

# Crear directorio de backup con fecha
BACKUP_DIR="$NFS_MOUNT/mysql/$FECHA"
mkdir -p "$BACKUP_DIR"

# Hacer backup de cada base de datos por separado
for DB in $(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "SHOW DATABASES;" | grep -v "Database\|information_schema\|performance_schema"); do
    mysqldump -u "$MYSQL_USER" -p"$MYSQL_PASS" \
        --single-transaction \
        --routines \
        --triggers \
        "$DB" | gzip > "$BACKUP_DIR/${DB}.sql.gz"
    echo "Backup completado: $DB"
done

# Eliminar backups más antiguos que RETENTION_DAYS
find "$NFS_MOUNT/mysql/" -maxdepth 1 -type d -mtime +$RETENTION_DAYS -exec rm -rf {} \;

echo "Backup finalizado: $BACKUP_DIR"
```

La opción `--single-transaction` es importante para MySQL/InnoDB: hace el dump dentro de una transacción, lo que garantiza consistencia sin bloquear las tablas durante el backup. En una base de datos activa, bloquear las tablas durante el backup podría interrumpir el servicio.

### Automatizar con cron

```bash
# Abrir crontab:
crontab -e

# Backup diario a las 2:00 AM:
0 2 * * * /opt/scripts/backup-mysql-to-nfs.sh >> /var/log/backup-mysql.log 2>&1
```

---

## Verificar que los backups funcionan

El error más común en backup es no verificar que los backups realmente se pueden restaurar. Un backup que no se puede restaurar no es un backup, es un archivo.

```bash
# Verificar que el archivo de backup es válido:
gunzip -t /mnt/nfs_backups/mysql/20240315_020001/mi_bbdd.sql.gz
echo $?  # 0 = OK, cualquier otro valor = archivo corrupto

# Verificar que el contenido SQL es correcto (ver primeras líneas):
zcat /mnt/nfs_backups/mysql/20240315_020001/mi_bbdd.sql.gz | head -20

# Prueba de restauración real (en una base de datos de prueba):
mysql -u root -p -e "CREATE DATABASE test_restore;"
zcat /mnt/nfs_backups/mysql/20240315_020001/mi_bbdd.sql.gz | mysql -u root -p test_restore
mysql -u root -p -e "SHOW TABLES FROM test_restore;"
```

Lo ideal es automatizar también la verificación: un script semanal que intente restaurar el último backup en una base de datos temporal y compruebe que el número de tablas y registros es el esperado.

---

## Backup de la configuración del sistema

Los datos de MySQL son lo más crítico, pero no hay que olvidar los archivos de configuración. Si el servidor muere y hay que reconstruirlo desde cero, perder horas buscando cómo estaba configurado el NFS o el LVM es frustrante y evitable.

```bash
# Hacer un tar de los archivos de configuración clave:
tar -czf /mnt/nfs_backups/config/config_$(date +%Y%m%d).tar.gz \
    /etc/fstab \
    /etc/exports \
    /etc/mdadm/mdadm.conf \
    /etc/mysql/ \
    /etc/ssh/sshd_config

# También es buena práctica guardar la configuración del LVM:
vgcfgbackup -f /mnt/nfs_backups/config/lvm_vg_datos_$(date +%Y%m%d).cfg vg_datos
```

---

## Tipos de backup: completo, incremental y diferencial

Para entornos con muchos datos, hacer un backup completo cada día puede ser prohibitivo en tiempo y espacio. Por eso existen estrategias combinadas:

### Backup completo
Copia todos los datos. Rápido de restaurar, lento de hacer, ocupa mucho espacio. Frecuencia típica: semanal.

### Backup incremental
Copia solo los cambios desde el **último backup** (completo o incremental). Rápido de hacer, ocupa poco, pero restaurar requiere encadenar: completo + todos los incrementales hasta la fecha.

### Backup diferencial
Copia los cambios desde el **último backup completo**. Más lento que el incremental pero más rápido de restaurar: solo se necesitan completo + el diferencial más reciente.

En la práctica para MySQL con tamaños manejables (< 100 GB), `mysqldump` diario con retención de 7 días es suficiente y simple. Para bases de datos más grandes, herramientas como `Percona XtraBackup` permiten backups incrementales en caliente sin `--single-transaction`.

---

## Resumen del ciclo completo

Juntando todo lo documentado en este repositorio, el ciclo completo de un servidor de base de datos en producción quedaría así:

```
┌─────────────────────────────────────────────────────────────────┐
│                    SERVIDOR MySQL PRODUCCIÓN                     │
│                                                                  │
│  RAID 10 (4 discos)     → Tolerancia a fallo de hardware        │
│       ↓                                                          │
│  LVM (vg_mysql)         → Flexibilidad para crecer en caliente  │
│       ↓                                                          │
│  XFS (/var/lib/mysql)   → Rendimiento para escrituras intensivas│
│       ↓                                                          │
│  MySQL corriendo        → El servicio                           │
│       ↓                                                          │
│  mysqldump diario       → Backup lógico con rotación 7 días     │
│       ↓                                                          │
│  NFS (servidor Mint)    → Destino del backup en red local       │
│       ↓                                                          │
│  S.M.A.R.T. + mdadm    → Alerta si algo va a fallar            │
│       ↓                                                          │
│  monitor-storage.sh     → Alerta si el espacio se acaba         │
└─────────────────────────────────────────────────────────────────┘
```

Cada capa del stack tiene una responsabilidad clara y complementa a las demás. RAID cubre lo que LVM no puede. LVM cubre lo que el sistema de ficheros no puede. El backup cubre lo que RAID no puede. Y la monitorización cubre lo que el backup no puede prevenir: te avisa antes de que necesites usar el backup.

---

*Anterior: [Monitorización](07-monitorizacion-almacenamiento.md) · Siguiente: [Troubleshooting](09-troubleshooting.md)*
