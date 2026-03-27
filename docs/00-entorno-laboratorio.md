# 🖥️ Entorno de Laboratorio

> Descripción del entorno de virtualización utilizado durante el bloque de almacenamiento en Linux.

---

## Hipervisor

**VMware Workstation** — utilizado para crear, gestionar y conectar en red todas las máquinas virtuales.

Las VMs comparten una red virtual en el rango `192.168.11.0/24`, lo que permite simular una infraestructura real de servidores comunicándose entre sí.

---

## Máquinas virtuales

| VM | Sistema Operativo | IP | Rol principal |
|----|-------------------|----|---------------|
| **srv-nfs** | Linux Mint | `192.168.11.143` | Servidor NFS — exporta directorios por red |
| **cli-nfs** | Fedora | `192.168.11.142` | Cliente NFS — monta directorios remotos |
| **srv-linux** | Ubuntu Server | `192.168.11.x` | Servidor general — prácticas de LVM, discos, RAID |
| **workstation** | Windows 11 Enterprise | `192.168.11.x` | Máquina de trabajo — conexión SSH a servidores Linux |

---

## Topología de red

```
                        VMware Virtual Network
                         192.168.11.0/24
                               │
        ┌──────────────────────┼──────────────────────┐
        │                      │                      │
┌───────────────┐   ┌──────────────────┐   ┌─────────────────┐
│  Linux Mint   │   │     Fedora       │   │  Ubuntu Server  │
│ 192.168.11.143│   │ 192.168.11.142   │   │ 192.168.11.x    │
│               │   │                  │   │                 │
│  Servidor NFS │   │  Cliente NFS     │   │  Prácticas LVM  │
│  /srv/nfs/    │──▶│  /mnt/nfs_comp.  │   │  RAID, discos   │
└───────────────┘   └──────────────────┘   └─────────────────┘
        ▲                                          ▲
        │                SSH                       │
        └──────────────────────────────────────────┘
                              │
                  ┌───────────────────────┐
                  │  Windows 11 Enterprise│
                  │  Cliente SSH          │
                  │  Terminal → Linux     │
                  └───────────────────────┘
```

---

## Decisiones de diseño del laboratorio

### ¿Por qué usar Windows 11 como cliente SSH?

En entornos empresariales reales es muy común que el administrador de sistemas trabaje desde una máquina Windows con herramientas como **Windows Terminal**, **PuTTY** o directamente el cliente SSH nativo de Windows 10/11.

Tener Windows 11 Enterprise en el lab permite practicar exactamente ese flujo: abrir un terminal en Windows y conectarse por SSH a cualquier servidor Linux del entorno.

```
# Desde Windows Terminal (PowerShell o CMD):
ssh usuario@192.168.11.143
```

Esto también permite familiarizarse con los problemas típicos de entornos mixtos: permisos de claves SSH, gestión de `known_hosts`, etc.

---

### ¿Por qué Linux Mint como servidor NFS?

Linux Mint es una distribución basada en Ubuntu/Debian, ampliamente extendida y con gestión de paquetes idéntica (`apt`). Usarla como servidor NFS es representativo de muchos entornos reales donde el servidor no es necesariamente una distribución "server edition", sino una estación de trabajo o servidor ligero.

---

### ¿Por qué Fedora como cliente NFS?

Fedora representa la familia Red Hat (RHEL, CentOS, Rocky Linux), muy presente en entornos de producción empresarial. Tener un cliente de familia diferente al servidor (Debian vs Red Hat) demuestra que NFS es agnóstico al sistema operativo: el protocolo funciona igual independientemente de la distro.

---

### ¿Por qué Ubuntu Server para prácticas generales?

Ubuntu Server es uno de los sistemas más usados en producción para servidores web, bases de datos y servicios generales. Las prácticas de LVM, RAID y montaje de discos se han realizado sobre Ubuntu Server por su estabilidad y documentación extensa.

---

## Objetivo del entorno

El objetivo no era tener las VMs más bonitas, sino simular un entorno que se parezca lo más posible a lo que un sysadmin encontraría en una empresa:

- Servidores Linux de distintas familias conviviendo.
- Un operador que trabaja desde Windows pero administra Linux por SSH.
- Servicios de red (NFS) conectando máquinas distintas.
- Red local simulada con IPs fijas y nombres de host.

Todo esto hace que las prácticas documentadas en este repositorio sean aplicables directamente a entornos reales.
