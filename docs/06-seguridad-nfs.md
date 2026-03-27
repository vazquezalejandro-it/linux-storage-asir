# 🔒 Seguridad en NFS

> NFS es un protocolo de red. Y como cualquier servicio de red mal configurado, puede convertirse en una puerta trasera enorme. Este documento explica los riesgos reales y cómo mitigarlos.

---

## El problema de NFS con configuraciones permisivas

En el laboratorio, cuando el objetivo es aprender cómo funciona NFS, es razonable simplificar los permisos para no distraerse con el foco principal. Pero si esa configuración de laboratorio llegara a un servidor de producción, las consecuencias podrían ser graves.

El escenario más peligroso: un servidor NFS exportando un directorio a toda la red sin restricciones.

```
# Configuración que NUNCA deberías ver en producción:
/srv/datos    *(rw,no_root_squash)
```

Esto significa: cualquier máquina de cualquier red puede montar este directorio, leer y escribir lo que quiera, y además el usuario root del cliente tiene privilegios de root también en el servidor. Es esencialmente un disco duro compartido sin contraseña.

---

## Las opciones de /etc/exports explicadas una a una

```
/srv/nfs/compartido    192.168.11.142(rw,sync,no_subtree_check)
```

### Control de acceso por IP o red

```bash
# Solo una IP específica (lo más restrictivo):
/srv/datos    192.168.11.142(rw,sync,no_subtree_check)

# Una subred completa:
/srv/datos    192.168.11.0/24(rw,sync,no_subtree_check)

# Cualquier máquina — NUNCA en producción:
/srv/datos    *(rw,sync,no_subtree_check)
```

En un entorno real, lo ideal es restringir siempre por IP o como mínimo por subred conocida. Si la red interna está bien segmentada y las máquinas que acceden al NFS son conocidas, restringir por IP es el camino correcto.

### rw vs ro (read-write vs read-only)

```bash
# Lectura y escritura:
192.168.11.142(rw,sync,no_subtree_check)

# Solo lectura — mucho más seguro si el cliente no necesita escribir:
192.168.11.142(ro,sync,no_subtree_check)
```

Un servidor web que monta los archivos HTML desde NFS no necesita `rw`. Con `ro` se asegura que incluso si el servidor web es comprometido, el atacante no puede modificar los archivos que sirve a través del NFS.

### sync vs async

```bash
# sync: la escritura se confirma cuando está físicamente en disco del servidor
192.168.11.142(rw,sync,no_subtree_check)

# async: el servidor confirma la escritura antes de que esté en disco (más rápido, menos seguro)
192.168.11.142(rw,async,no_subtree_check)
```

`sync` es más lento pero garantiza que si el servidor se apaga en mitad de una escritura, los datos no quedan corruptos. Para cualquier dato importante, siempre `sync`.

### root_squash vs no_root_squash — La opción más crítica de seguridad

Esta es la opción más importante desde el punto de vista de seguridad:

```bash
# root_squash (DEFECTO — SEGURO):
# El usuario root del cliente se convierte en el usuario "nobody" en el servidor
192.168.11.142(rw,sync,no_subtree_check,root_squash)

# no_root_squash (PELIGROSO):
# El root del cliente ES root en el servidor también
192.168.11.142(rw,sync,no_subtree_check,no_root_squash)
```

Con `no_root_squash`, si alguien compromete el cliente NFS y escala a root, tiene acceso de root sobre el sistema de ficheros del servidor. `root_squash` está activo por defecto precisamente porque es la opción segura, pero hay que saber que existe y qué hace.

### no_subtree_check vs subtree_check

```bash
# no_subtree_check (recomendado actualmente):
# El servidor no verifica que el archivo solicitado está dentro del directorio exportado
# Mejora el rendimiento y evita problemas cuando los archivos se renombran
192.168.11.142(rw,sync,no_subtree_check)

# subtree_check (comportamiento antiguo):
# Verificación extra de seguridad pero con penalización de rendimiento
# Puede causar problemas con archivos abiertos que se renombran
192.168.11.142(rw,sync,subtree_check)
```

La documentación oficial de Linux recomienda `no_subtree_check` en la mayoría de los casos modernos.

---

## Configuración de firewall para NFS

NFS usa varios puertos. En un servidor de producción, el firewall debe permitir solo lo necesario:

```bash
# NFS v4 usa principalmente el puerto 2049 TCP/UDP
# En sistemas con firewalld (Fedora, RHEL, Rocky):
sudo firewall-cmd --permanent --add-service=nfs
sudo firewall-cmd --permanent --add-service=mountd
sudo firewall-cmd --permanent --add-service=rpc-bind
sudo firewall-cmd --reload

# En sistemas con ufw (Ubuntu, Mint):
sudo ufw allow from 192.168.11.0/24 to any port 2049
sudo ufw allow from 192.168.11.0/24 to any port 111
```

La diferencia con el laboratorio es importante: en el lab se desactiva el firewall para no complicar la práctica. En producción, el firewall está siempre activo y se abre solo lo necesario.

---

## NFS v4 vs NFS v3 — Por qué importa la versión

En el laboratorio usamos NFSv4 por defecto en distros modernas. La diferencia con v3 desde el punto de vista de seguridad es relevante:

| Característica | NFSv3 | NFSv4 |
|----------------|-------|-------|
| Autenticación | Basada solo en IP | Soporta Kerberos (krb5) |
| Cifrado en tránsito | No | Sí (con krb5p) |
| Puerto fijo | No (usa portmapper) | Sí (2049 TCP) |
| Estado de conexión | Sin estado | Con estado (más fiable) |

Para el nivel de un entorno de laboratorio de ASIR, NFSv4 sin Kerberos es suficiente. En un entorno empresarial real donde los datos son sensibles, NFSv4 con Kerberos (`sec=krb5p`) cifra los datos en tránsito y autentica usuarios de forma robusta.

---

## Configuración segura recomendada para el laboratorio

Comparando lo que usamos en el lab con lo que usaríamos en producción:

```bash
# Laboratorio (simplificado para aprender):
/srv/nfs/compartido    192.168.11.142(rw,sync,no_subtree_check)

# Producción con un servidor de datos compartido:
/srv/datos    192.168.11.142(rw,sync,no_subtree_check,root_squash)

# Producción con un servidor web (solo lectura):
/srv/web/html    192.168.11.10(ro,sync,no_subtree_check,root_squash)
/srv/web/html    192.168.11.11(ro,sync,no_subtree_check,root_squash)

# Producción con múltiples servidores de la misma subred:
/srv/compartido    192.168.11.0/24(rw,sync,no_subtree_check,root_squash)
```

---

## Los riesgos que hay que conocer

### 1. Escalada de privilegios vía no_root_squash
Si un cliente NFS está comprometido y el servidor tiene `no_root_squash`, el atacante tiene acceso de root sobre los datos del servidor. Por eso `root_squash` está activo por defecto.

### 2. Exposición de datos por exports demasiado abiertos
Un `*(rw)` exporta el directorio a internet completo si el servidor tiene una IP pública. Restricción por IP siempre.

### 3. NFS no cifra el tráfico por defecto
En NFSv4 sin Kerberos, los datos viajan en texto plano por la red. En una red interna bien aislada esto es generalmente aceptable. En redes donde no se confía en todos los segmentos, se necesita Kerberos o un túnel VPN.

### 4. Permisos de directorio mal configurados
Si el directorio exportado tiene permisos 777, cualquier usuario del cliente puede leer, escribir y borrar cualquier archivo. En producción los permisos deben ajustarse al usuario o grupo que realmente necesita acceso.

---

## Checklist de seguridad antes de poner NFS en producción

```
✅ Restringir acceso por IP específica o subred conocida (nunca *)
✅ Usar ro si el cliente no necesita escribir
✅ Mantener root_squash activo (está por defecto, no tocarlo sin razón)
✅ Usar sync para datos importantes
✅ Firewall configurado para permitir solo los puertos NFS desde las IPs cliente
✅ Permisos del directorio ajustados al usuario/grupo necesario
✅ Monitorizar accesos inusuales con los logs del sistema
✅ Valorar NFSv4 + Kerberos para datos sensibles
```

---

*Anterior: [Caso práctico MySQL](05-caso-practico-mysql.md) · Siguiente: [Monitorización](07-monitorizacion-almacenamiento.md)*
