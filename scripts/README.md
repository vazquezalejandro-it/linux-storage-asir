# ⚙️ Scripts de Automatización

> Un sysadmin que hace las mismas cosas a mano cada semana no es un sysadmin eficiente. Estos scripts convierten los laboratorios manuales en despliegues reproducibles.

---

## Por qué automatizar

Durante el laboratorio, todo se hace a mano: cada comando se escribe, se entiende y se verifica. Eso es correcto para aprender. Pero en producción, si tienes que configurar 5 servidores NFS o programar backups en 10 máquinas, hacerlo a mano es lento y propenso a errores.

Estos scripts no reemplazan entender cómo funciona cada cosa. Son la siguiente capa: una vez que entiendes el laboratorio manual, el script te permite reproducirlo de forma fiable, documentada y rápida.

---

## Scripts disponibles

### setup-nfs-server.sh
Configura un servidor NFS desde cero en sistemas Debian/Ubuntu o Fedora/RHEL.

```bash
# Uso:
sudo chmod +x setup-nfs-server.sh
sudo ./setup-nfs-server.sh <IP_CLIENTE> <DIRECTORIO_EXPORT>

# Ejemplo (equivalente al laboratorio Mint + Fedora):
sudo ./setup-nfs-server.sh 192.168.11.142 /srv/nfs/compartido
```

Lo que hace: instala los paquetes, crea el directorio, configura `/etc/exports`, inicia el servicio y verifica que todo funciona. Al final muestra el comando exacto para montar desde el cliente.

---

### setup-lvm-mysql.sh
Configura la pila LVM completa optimizada para MySQL sobre un dispositivo dado.

```bash
# Uso:
sudo chmod +x setup-lvm-mysql.sh
sudo ./setup-lvm-mysql.sh <DISPOSITIVO> <TAMAÑO_LV_DATOS>

# Ejemplo (sobre el RAID 10 del caso práctico):
sudo ./setup-lvm-mysql.sh /dev/md0 80G
```

Lo que hace: crea PV, VG (`vg_mysql`), dos LVs (`lv_mysql` para datos y `lv_binlog` para binary logs), formatea ambos con XFS, monta en `/var/lib/mysql` y `/var/lib/mysql-binlog`, añade entradas a `/etc/fstab` y ajusta permisos para el usuario `mysql`.

> ⚠️ **ATENCIÓN**: Este script destruye los datos del dispositivo especificado. Pide confirmación explícita antes de proceder.

---

### monitor-storage.sh
Comprueba el estado del almacenamiento y envía alertas si detecta problemas.

```bash
# Uso manual:
chmod +x monitor-storage.sh
./monitor-storage.sh

# Instalación en cron (ejecutar cada hora):
crontab -e
# Añadir:
0 * * * * /opt/scripts/monitor-storage.sh
```

Qué comprueba:
- Espacio en disco (alerta si algún FS supera el 80%)
- Uso de inodos (alerta si supera el 80%)
- Estado de arrays RAID con mdadm
- Salud S.M.A.R.T. de discos físicos

Configurar el umbral, email de alerta y discos a monitorizar editando la sección `CONFIGURACIÓN` al inicio del script.

---

### backup-mysql-to-nfs.sh
Hace backup de todas las bases de datos MySQL hacia el servidor NFS con rotación automática.

```bash
# Uso manual:
chmod +x backup-mysql-to-nfs.sh
./backup-mysql-to-nfs.sh

# Instalación en cron (backup diario a las 2:00 AM):
crontab -e
# Añadir:
0 2 * * * /opt/scripts/backup-mysql-to-nfs.sh >> /var/log/backup-mysql.log 2>&1
```

Qué hace:
- Verifica que el NFS está montado antes de empezar
- Hace backup de cada base de datos en un archivo `.sql.gz` separado
- Usa `--single-transaction` para no bloquear las tablas
- Verifica la integridad de cada backup después de crearlo
- Guarda también un tar de los archivos de configuración del sistema
- Elimina backups más antiguos que N días (configurable)

---

## Instalación recomendada

```bash
# Copiar scripts a /opt/scripts (buena práctica en Linux):
sudo mkdir -p /opt/scripts
sudo cp *.sh /opt/scripts/
sudo chmod +x /opt/scripts/*.sh

# Verificar:
ls -la /opt/scripts/
```

---

## Credenciales de MySQL para el backup

Para no poner la contraseña de MySQL dentro del script (mala práctica de seguridad), usar el archivo `~/.my.cnf`:

```bash
# Crear usuario de backup en MySQL:
sudo mysql -e "CREATE USER 'backup_user'@'localhost' IDENTIFIED BY 'contraseña_segura';"
sudo mysql -e "GRANT SELECT, LOCK TABLES, SHOW VIEW, EVENT, TRIGGER ON *.* TO 'backup_user'@'localhost';"
sudo mysql -e "FLUSH PRIVILEGES;"

# Crear /root/.my.cnf:
sudo nano /root/.my.cnf

# Contenido:
[client]
user=backup_user
password=contraseña_segura

# Permisos seguros:
sudo chmod 600 /root/.my.cnf
```

Con esto, los comandos `mysql` y `mysqldump` se autentican automáticamente leyendo el archivo, sin necesidad de pasar credenciales en la línea de comandos (que quedarían visibles en `ps aux` o en el historial).

---

*Volver al [README principal](../README.md)*
