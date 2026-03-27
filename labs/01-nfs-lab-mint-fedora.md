# 🧪 Laboratorio NFS: Linux Mint (servidor) + Fedora (cliente)

> **Todo lo documentado aquí ha sido ejecutado y verificado en máquinas virtuales reales.** Los comandos, IPs y resultados son los que se obtuvieron durante la práctica.

---

## Contexto

NFS (Network File System) permite que un servidor Linux exporte un directorio y que uno o varios clientes lo monten como si fuera un disco local. Para la aplicación que accede a ese directorio, es completamente transparente: no sabe si está leyendo de un disco local o de un servidor al otro lado de la red.

Este laboratorio demuestra exactamente eso: crear un directorio en Linux Mint, compartirlo por NFS, montarlo en Fedora y verificar que ambas máquinas ven los mismos archivos en tiempo real.

---

## Entorno del laboratorio

| Máquina | Sistema Operativo | IP | Rol |
|---------|-------------------|----|-----|
| `srv-nfs` | Linux Mint | `192.168.11.143` | Servidor NFS — exporta `/srv/nfs/compartido` |
| `cli-nfs` | Fedora | `192.168.11.142` | Cliente NFS — monta en `/mnt/nfs_compartido` |

```
Hipervisor VMware — Red 192.168.11.0/24

┌─────────────────────┐         ┌────────────────────────┐
│   Linux Mint        │         │        Fedora          │
│   192.168.11.143    │◄───────►│   192.168.11.142       │
│                     │   NFS   │                        │
│  /srv/nfs/          │         │  /mnt/nfs_compartido   │
│  compartido/        │         │  (montaje remoto)      │
│  (disco local)      │         │                        │
└─────────────────────┘         └────────────────────────┘
```

---

## Objetivo

1. Compartir un directorio del servidor Mint mediante NFS.
2. Montarlo desde Fedora como si fuera un disco local.
3. Verificar lectura y escritura en ambas direcciones.
4. Hacer el montaje persistente con `/etc/fstab`.

---

## Paso 1 — Verificar conectividad

Antes de configurar NFS, verificamos que las dos VMs se ven por red. Sin esto, nada funcionará.

**Desde Fedora, hacer ping al servidor Mint:**

```bash
[fedora ~]$ ping -c 3 192.168.11.143
PING 192.168.11.143 (192.168.11.143) 56(84) bytes of data.
64 bytes from 192.168.11.143: icmp_seq=1 ttl=64 time=0.412 ms
64 bytes from 192.168.11.143: icmp_seq=2 ttl=64 time=0.387 ms
64 bytes from 192.168.11.143: icmp_seq=3 ttl=64 time=0.401 ms

--- 192.168.11.143 ping statistics ---
3 packets transmitted, 3 received, 0% packet loss
```

✅ Las VMs se ven correctamente.

> Si el ping falla, hay que revisar: adaptadores de red en VMware (deben estar en la misma red virtual), estado del firewall de cada VM, y que las IPs estén bien asignadas.

**Verificar la propia IP de cada VM:**

```bash
# En Linux Mint (servidor):
ip a | grep 192.168
# Debe mostrar: 192.168.11.143

# En Fedora (cliente):
ip a | grep 192.168
# Debe mostrar: 192.168.11.142
```

---

## Paso 2 — Preparar el servidor NFS (Linux Mint)

### 2.1 Instalar el servicio NFS

```bash
[mint ~]$ sudo apt update
[mint ~]$ sudo apt install -y nfs-kernel-server
```

Esto instala el demonio NFS del kernel, que es el componente que escucha peticiones de los clientes y les sirve los directorios exportados.

### 2.2 Crear el directorio a compartir

```bash
[mint ~]$ sudo mkdir -p /srv/nfs/compartido
```

**¿Por qué `/srv`?**

El estándar FHS (Filesystem Hierarchy Standard) de Linux indica que `/srv` es el lugar para datos que van a ser servidos por el sistema a través de algún servicio (HTTP, FTP, NFS, etc.). Es una convención limpia y semánticamente correcta: cualquier sysadmin que vea `/srv/nfs/` entiende inmediatamente que ese directorio está siendo servido por NFS.

No es obligatorio usarlo, pero sí es una buena práctica que demuestra conocimiento de las convenciones del sistema.

### 2.3 Asignar permisos

```bash
[mint ~]$ sudo chmod 777 /srv/nfs/compartido
```

> En un entorno de laboratorio, simplificamos los permisos a 777 para centrarnos en aprender NFS sin que los permisos compliquen la práctica. En producción, los permisos deben ser más restrictivos y adaptados al usuario/grupo que accede.

Una opción más controlada sería crear un usuario específico y usar `chown`:
```bash
# En producción, algo así sería más apropiado:
sudo chown nobody:nogroup /srv/nfs/compartido
sudo chmod 755 /srv/nfs/compartido
```

---

## Paso 3 — Configurar /etc/exports en el servidor

El archivo `/etc/exports` es el corazón de la configuración del servidor NFS. Cada línea define qué directorio se exporta y a quién, con qué opciones.

```bash
[mint ~]$ sudo nano /etc/exports
```

Añadimos la siguiente línea:

```
/srv/nfs/compartido    192.168.11.142(rw,sync,no_subtree_check)
```

### Explicación de la línea

| Campo | Valor | Significado |
|-------|-------|-------------|
| Directorio | `/srv/nfs/compartido` | Qué directorio exportamos |
| Cliente | `192.168.11.142` | Solo esta IP puede montar (el Fedora) |
| `rw` | read-write | El cliente puede leer y escribir |
| `sync` | sincrónico | Las escrituras se confirman cuando están en disco (más seguro) |
| `no_subtree_check` | desactivar comprobación de subárbol | Mejora rendimiento; actualmente es el valor recomendado |

> Si quisiéramos permitir solo lectura, usaríamos `ro` en lugar de `rw`.  
> Si quisiéramos que toda la red pudiera montar: `192.168.11.0/24(rw,sync,no_subtree_check)`.

### Aplicar los cambios

```bash
# Indicarle al servicio NFS que reloa el /etc/exports:
[mint ~]$ sudo exportfs -ra

# Verificar qué se está exportando actualmente:
[mint ~]$ sudo exportfs -v
/srv/nfs/compartido
        192.168.11.142(sync,wdelay,hide,no_subtree_check,sec=sys,rw,secure,root_squash,no_all_squash)
```

La salida de `exportfs -v` muestra las opciones completas, incluyendo algunas por defecto como `root_squash` (que convierte las peticiones del root del cliente en un usuario sin privilegios — una medida de seguridad importante).

### Iniciar y habilitar el servicio NFS

```bash
[mint ~]$ sudo systemctl enable --now nfs-kernel-server

# Verificar que está corriendo:
[mint ~]$ sudo systemctl status nfs-kernel-server
● nfs-server.service - NFS server and services
     Loaded: loaded (/lib/systemd/system/nfs-server.service; enabled)
     Active: active (running) since ...
```

---

## Paso 4 — Preparar el cliente NFS (Fedora)

### 4.1 Instalar las utilidades NFS

En Fedora (familia Red Hat), el paquete de cliente NFS se llama `nfs-utils`:

```bash
[fedora ~]$ sudo dnf install -y nfs-utils
```

### 4.2 Crear el punto de montaje

```bash
[fedora ~]$ sudo mkdir -p /mnt/nfs_compartido
```

El directorio `/mnt/nfs_compartido` es el punto de montaje: el "hueco" del árbol de directorios donde aparecerá el contenido del servidor Mint.

---

## Paso 5 — Montaje manual (prueba antes de tocar fstab)

Una buena práctica es **siempre hacer primero un montaje manual** antes de editar `/etc/fstab`. Si el montaje manual funciona, sabemos que la configuración es correcta y podemos pasar a hacerla persistente. Si hay algún error, es mucho más fácil depurarlo aquí que después de un arranque fallido.

```bash
[fedora ~]$ sudo mount -t nfs 192.168.11.143:/srv/nfs/compartido /mnt/nfs_compartido
```

### Verificar que el montaje está activo

```bash
[fedora ~]$ df -h | grep nfs
192.168.11.143:/srv/nfs/compartido   20G   5.1G   15G   26%   /mnt/nfs_compartido

[fedora ~]$ ls /mnt/nfs_compartido/
# (directorio vacío — todavía no hemos creado nada)
```

✅ El directorio remoto está montado correctamente en Fedora.

---

## Paso 6 — Prueba de lectura y escritura bidireccional

Esta es la prueba más importante del laboratorio: demostrar que ambas máquinas están viendo el mismo directorio en tiempo real.

### 6.1 Crear un archivo desde el servidor (Mint) y verlo desde el cliente (Fedora)

**En el servidor Mint:**
```bash
[mint ~]$ echo "Hola desde el servidor Mint" | sudo tee /srv/nfs/compartido/desde_servidor.txt
Hola desde el servidor Mint
```

**En el cliente Fedora (sin hacer nada más):**
```bash
[fedora ~]$ ls /mnt/nfs_compartido/
desde_servidor.txt

[fedora ~]$ cat /mnt/nfs_compartido/desde_servidor.txt
Hola desde el servidor Mint
```

✅ El cliente ve inmediatamente el archivo creado en el servidor.

---

### 6.2 Crear un archivo desde el cliente (Fedora) y verlo desde el servidor (Mint)

**En el cliente Fedora:**
```bash
[fedora ~]$ echo "Respuesta desde el cliente Fedora" | sudo tee /mnt/nfs_compartido/desde_cliente.txt
Respuesta desde el cliente Fedora
```

**En el servidor Mint:**
```bash
[mint ~]$ ls /srv/nfs/compartido/
desde_servidor.txt  desde_cliente.txt

[mint ~]$ cat /srv/nfs/compartido/desde_cliente.txt
Respuesta desde el cliente Fedora
```

✅ El servidor ve el archivo creado desde el cliente.

**Lo que esto demuestra:** ambas máquinas están accediendo al mismo directorio a través de la red. El cliente escribe en su punto de montaje local (`/mnt/nfs_compartido`), el servidor NFS recibe la petición, la ejecuta en su disco local (`/srv/nfs/compartido`) y el archivo es visible desde ambos lados.

---

## Paso 7 — Hacer el montaje persistente con /etc/fstab

El montaje manual no sobrevive a un reinicio. Para que Fedora monte automáticamente el directorio NFS al arrancar, hay que añadir una línea a `/etc/fstab`:

```bash
[fedora ~]$ sudo nano /etc/fstab
```

Añadir al final del archivo:

```
192.168.11.143:/srv/nfs/compartido    /mnt/nfs_compartido    nfs    defaults    0    0
```

### Explicación de los campos

| Campo | Valor | Significado |
|-------|-------|-------------|
| Dispositivo | `192.168.11.143:/srv/nfs/compartido` | IP del servidor + ruta exportada |
| Punto de montaje | `/mnt/nfs_compartido` | Dónde aparece en el cliente |
| Tipo | `nfs` | Tipo de sistema de ficheros |
| Opciones | `defaults` | Opciones por defecto (rw, relatime, etc.) |
| dump | `0` | No hacer dump de este sistema de ficheros |
| pass | `0` | No verificar integridad al arrancar (correcto para NFS) |

---

## Paso 8 — Probar la persistencia sin reiniciar

En lugar de reiniciar la máquina (que en un servidor de producción podría no ser una opción), podemos probar el fstab de la siguiente manera:

```bash
# Primero desmontar el montaje actual:
[fedora ~]$ sudo umount /mnt/nfs_compartido

# Verificar que ya no está montado:
[fedora ~]$ ls /mnt/nfs_compartido/
# (vacío — solo vemos el directorio local, no el contenido remoto)

# Montar todo lo que está en fstab y no está montado aún:
[fedora ~]$ sudo mount -a

# Verificar que volvió a montarse:
[fedora ~]$ ls /mnt/nfs_compartido/
desde_servidor.txt  desde_cliente.txt

[fedora ~]$ df -h | grep nfs
192.168.11.143:/srv/nfs/compartido   20G   5.1G   15G   26%   /mnt/nfs_compartido
```

✅ El fstab funciona correctamente. En el próximo reinicio, el montaje se realizará de forma automática sin intervención.

---

## Nota sobre systemd y daemon-reload

Al editar `/etc/fstab`, es posible que el sistema muestre un aviso como:

```
Warning: The unit file, source configuration file or drop-ins of ... changed on disk.
Run 'systemctl daemon-reload' to reload units.
```

Este mensaje indica que systemd (que también gestiona los montajes del fstab) necesita recargar su configuración. No es un error crítico y el montaje manual con `mount -a` funciona igualmente. Para limpiarlo:

```bash
sudo systemctl daemon-reload
```

---

## Conclusiones del laboratorio

Este laboratorio demuestra varios conceptos importantes:

1. **NFS abstrae el almacenamiento por red**: la aplicación en Fedora que abriera archivos de `/mnt/nfs_compartido` no sabría que está leyendo de un servidor remoto.

2. **La configuración del servidor es en `/etc/exports`**: un solo archivo controla qué se comparte, con quién y con qué permisos.

3. **El montaje manual primero, fstab después**: esta secuencia es la práctica correcta para evitar errores que impidan el arranque del sistema.

4. **Las escrituras son inmediatas**: gracias a la opción `sync`, las escrituras se confirman cuando están en disco del servidor, lo que garantiza consistencia.

5. **Entorno mixto de distribuciones**: el servidor es Debian/Ubuntu (Mint) y el cliente es Red Hat (Fedora). NFS funciona igual independientemente de la distro, demostrando que es un protocolo estándar y portable.

---

## Casos de uso reales de NFS

- **Clusters de servidores web**: varios servidores Apache/Nginx comparten un directorio NFS donde están los archivos PHP/HTML. Así, todos los nodos sirven los mismos archivos sin necesidad de copiarlos.
- **Directorio home compartido**: en entornos con múltiples servidores, `/home` se sirve por NFS para que el usuario vea sus archivos independientemente de en qué servidor inicie sesión.
- **Almacenamiento compartido para VMs**: en entornos de virtualización sin SAN, NFS puede actuar como almacén compartido de imágenes de disco.

---

*Volver al [README principal](../README.md) · Ver también: [Caso práctico MySQL](../docs/05-caso-practico-mysql.md)*
