# 📊 Monitorización del Almacenamiento

> En producción, lo que no se monitoriza se rompe tarde o temprano. Y normalmente se rompe a las 3 de la mañana, con el servicio caído y el teléfono sonando. Este documento explica cómo no llegar a ese punto.

---

## El principio de la monitorización proactiva

Hay dos tipos de administradores:
- Los que se enteran de que un disco ha fallado porque el servicio ha caído.
- Los que se enteran porque su sistema de monitorización les avisa días antes de que falle.

La diferencia entre ambos es tener un sistema de monitorización correctamente configurado. No hace falta una herramienta enterprise para esto. Con `smartctl`, `mdadm` y un par de scripts en `cron`, se cubre el 80% de los casos que importan.

---

## 1. Monitorización del espacio en disco

### Ver el estado actual

```bash
# Espacio usado por sistema de ficheros montado:
df -h

# Salida típica:
# Filesystem                      Size  Used Avail Use% Mounted on
# /dev/vg_datos/lv_mysql           50G   31G   19G  62% /var/lib/mysql
# 192.168.11.143:/srv/nfs/comp     20G  5.1G   15G  26% /mnt/nfs

# Ver uso de inodos (cuando el espacio parece libre pero hay errores de escritura):
df -i

# Ver qué directorio está ocupando más espacio:
du -sh /var/lib/mysql/*  | sort -rh | head -20
```

### Alerta automática cuando el espacio se acaba

El problema más común en producción es encontrarse con que un volumen está al 95% de capacidad y el servicio empieza a fallar. Esto se evita con una alerta que avise con tiempo suficiente para actuar.

```bash
# Script básico que avisa cuando un LV supera el 80% de uso:
# (El script completo está en scripts/monitor-storage.sh)

THRESHOLD=80
MOUNT="/var/lib/mysql"

USO=$(df -h "$MOUNT" | awk 'NR==2 {print $5}' | tr -d '%')

if [ "$USO" -gt "$THRESHOLD" ]; then
    echo "ALERTA: $MOUNT está al ${USO}% de capacidad" | \
    mail -s "ALERTA ALMACENAMIENTO - $(hostname)" admin@empresa.com
fi
```

Programado en cron para que se ejecute cada hora:
```bash
# Editar crontab:
crontab -e

# Añadir línea:
0 * * * * /opt/scripts/monitor-storage.sh
```

---

## 2. Monitorización del RAID con mdadm

### Estado actual del RAID

```bash
# Ver estado detallado del array RAID:
cat /proc/mdstat

# Salida si todo está bien:
# md0 : active raid10 sdb[0] sdc[1] sdd[2] sde[3]
#       976760832 blocks super 1.2 512K chunks 2 near-copies [4/4] [UUUU]

# Salida si un disco ha fallado:
# md0 : active raid10 sdb[0] sdc[1] sdd[2] sde[3](F)
#       976760832 blocks super 1.2 512K chunks 2 near-copies [4/3] [UUU_]
#       ← El _ indica que hay un disco caído

# Información detallada:
sudo mdadm --detail /dev/md0
```

Lo que hay que vigilar en la salida de `mdadm --detail`:
- **State**: debe ser `clean`. Si aparece `degraded`, un disco ha fallado.
- **Active Devices**: debe coincidir con **Raid Devices**.
- **Failed Devices**: debe ser `0`.

### Configurar mdadm para que envíe alertas automáticas

`mdadm` tiene un modo de monitorización que puede enviar emails cuando detecta cambios en el estado del RAID:

```bash
# Configuración en /etc/mdadm/mdadm.conf:
# Añadir o modificar la línea MAILADDR:
sudo nano /etc/mdadm/mdadm.conf

# Añadir:
MAILADDR admin@empresa.com

# Activar el demonio de monitorización:
sudo systemctl enable --now mdadm-monitor

# Probar que funciona:
sudo mdadm --monitor --scan --test --oneshot
```

Con esta configuración, si un disco del RAID empieza a dar errores o falla completamente, `mdadm` envía un email automáticamente, sin necesidad de scripts adicionales.

### Simular un fallo para entender cómo responde el RAID

En el laboratorio, es una práctica muy valiosa simular el fallo de un disco y observar el comportamiento del RAID:

```bash
# Marcar un disco como fallido (simulación en laboratorio):
sudo mdadm --manage /dev/md0 --fail /dev/sde

# Ver el estado degradado:
cat /proc/mdstat
# Verás [UUU_] indicando que falta un disco

# Quitar el disco fallido del array:
sudo mdadm --manage /dev/md0 --remove /dev/sde

# Añadir el disco de reemplazo:
sudo mdadm --manage /dev/md0 --add /dev/sdf

# Ver la reconstrucción en progreso:
watch cat /proc/mdstat
# Verás una barra de progreso y el tiempo estimado
```

Esto demuestra que con RAID 10, el servicio sigue funcionando durante todo el proceso de sustitución.

---

## 3. Salud del hardware: S.M.A.R.T.

RAID protege contra el fallo de un disco, pero no avisa cuando un disco está *a punto* de fallar. Para eso existe S.M.A.R.T. (Self-Monitoring, Analysis and Reporting Technology), que es la tecnología que tienen todos los discos modernos para autodiagnosticarse.

### Instalar y usar smartmontools

```bash
# Instalar:
sudo apt install smartmontools   # Debian/Ubuntu/Mint
sudo dnf install smartmontools   # Fedora/RHEL/Rocky

# Ver información S.M.A.R.T. de un disco:
sudo smartctl -a /dev/sdb

# Lo que hay que buscar en la salida:
# SMART overall-health self-assessment test result: PASSED  ← Bueno
# SMART overall-health self-assessment test result: FAILED! ← El disco va a morir

# Atributos críticos a vigilar:
# ID  5  Reallocated_Sector_Ct  → sectores reasignados (>0 empieza a preocupar, >100 es serio)
# ID 197  Current_Pending_Sector → sectores pendientes de reasignar (cualquier valor >0 es preocupante)
# ID 198  Offline_Uncorrectable  → sectores irrecuperables (cualquier valor >0 es serio)
```

### Ejecutar un test de diagnóstico

```bash
# Test corto (tarda ~2 minutos):
sudo smartctl -t short /dev/sdb

# Esperar y ver resultados:
sudo smartctl -l selftest /dev/sdb

# Test largo (tarda horas, más exhaustivo):
sudo smartctl -t long /dev/sdb
```

### Monitorización automática con smartd

`smartd` es el demonio que monitoriza los discos en segundo plano:

```bash
# Activar:
sudo systemctl enable --now smartd

# Configuración en /etc/smartd.conf:
# La línea DEVICESCAN habilita monitorización automática de todos los discos:
DEVICESCAN -H -l error -l selftest -f -s (S/../.././02|L/../../6/03) -m admin@empresa.com
```

Esta configuración ejecuta tests cortos cada día a las 2h y tests largos los sábados a las 3h, y envía email si detecta problemas.

---

## 4. Monitorización de LVM

```bash
# Ver el espacio disponible en todos los Volume Groups:
vgs

# Salida:
# VG        #PV #LV #SN Attr   VSize   VFree
# vg_datos    1   2   0 wz--n- 476.94g 276.94g

# Ver espacio de cada LV:
lvs

# Ver con más detalle:
lvdisplay /dev/vg_datos/lv_mysql | grep -E "LV Size|Allocated"

# Porcentaje de uso de cada LV:
df -h | grep -E "vg_datos|Filesystem"
```

Lo que hay que vigilar: cuando `VFree` del VG llega a 0, ya no puedes extender ningún LV aunque el sistema de ficheros tenga espacio. Siempre mantener algo de espacio libre en el VG como margen de maniobra.

---

## 5. Herramientas de monitorización más completas

Para entornos con más de 2-3 servidores, gestionar la monitorización con scripts propios escala mal. Las herramientas que se usan en producción real son:

### Prometheus + Grafana
El estándar actual en infraestructura moderna. `node_exporter` recopila métricas del sistema (disco, memoria, CPU, red) y Grafana las visualiza con dashboards. Es la herramienta que más vas a ver en ofertas de trabajo.

```bash
# Instalación básica de node_exporter (el agente de métricas):
wget https://github.com/prometheus/node_exporter/releases/latest/download/node_exporter-linux-amd64.tar.gz
tar xvf node_exporter-*.tar.gz
sudo mv node_exporter-*/node_exporter /usr/local/bin/
sudo systemctl enable --now node_exporter
```

### Zabbix
Más tradicional, con una interfaz web completa. Muy presente en empresas con infraestructura legacy. Tiene agentes para Linux y Windows y permite monitorizar casi cualquier cosa.

### Nagios / Icinga
Los veteranos. Nagios lleva décadas siendo el estándar de monitorización de servidores. Icinga es un fork moderno con mejor interfaz. Se siguen usando mucho en empresas con infraestructura madura.

### Para el lab
En el contexto de este laboratorio, lo más práctico es dominar los comandos nativos (`df`, `mdadm`, `smartctl`, `lvs`) y el script de monitorización propio. Cuando llegues a un entorno empresarial, adaptarte a su herramienta de monitorización (Zabbix, Prometheus, Nagios) será mucho más fácil si ya entiendes qué métricas son relevantes y por qué.

---

## Resumen: qué monitorizar y con qué frecuencia

| Qué | Herramienta | Frecuencia | Alerta si... |
|-----|-------------|------------|--------------|
| Espacio en disco | `df` + script | Cada hora | > 80% uso |
| Estado RAID | `mdadm --detail` / `mdadm-monitor` | Continuo | Disco fallido o degradado |
| Salud disco S.M.A.R.T. | `smartd` | Diaria/Semanal | Test falla o sectores reasignados |
| Espacio VG libre | `vgs` + script | Cada hora | VFree < 10% |
| Logs del sistema | `journalctl` / `/var/log/syslog` | Revisión periódica | Errores de I/O, `I/O error` |

---

*Anterior: [Seguridad NFS](06-seguridad-nfs.md) · Siguiente: [Backup y recuperación](08-backup-y-recuperacion.md)*
