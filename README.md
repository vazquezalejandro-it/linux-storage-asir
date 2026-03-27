# 🗄️ Almacenamiento en Linux — Laboratorios, Arquitectura y Automatización

> **Repositorio de estudio avanzado — ASIR / Administración de Sistemas**  
> Todo el contenido ha sido diseñado, ejecutado y verificado personalmente en un entorno de laboratorio con máquinas virtuales reales bajo VMware.

---

## 📌 Por qué existe este repositorio

Durante un bloque intensivo de almacenamiento en Linux me encontré con algo que nadie explica bien: los libros de texto te dan los comandos, pero no te dicen **por qué** un sysadmin elige RAID 10 sobre RAID 5 para una base de datos, ni **qué pasa** cuando el espacio se acaba en producción a las 3 de la mañana y tienes que crecer un volumen sin parar el servicio.

Este repositorio es la respuesta a esas preguntas. No es un resumen de documentación oficial. Es lo que aprendí tocando máquinas, cometiendo errores y entendiéndolo de verdad.

Cubre el ciclo completo de almacenamiento en Linux:

```
Hardware → RAID → LVM → Sistema de ficheros → Montaje → Servicio de red → Monitorización → Backup
```

Cada capa está documentada con teoría, laboratorios reales y scripts de automatización.

---

## 🗺️ Estructura del repositorio

```
linux-storage-asir/
│
├── README.md
│
├── docs/                                   ← Documentación teórica
│   ├── 00-entorno-laboratorio.md           Descripción del lab: VMs, red, decisiones
│   ├── 01-raid.md                          RAID 0/1/5/6/10 a fondo
│   ├── 02-lvm.md                           LVM: PV, VG, LV y operaciones en caliente
│   ├── 03-filesystems-ext4-xfs.md          ext4 vs XFS: cuándo usar cada uno
│   ├── 04-pila-almacenamiento.md           Visión global: del disco físico al archivo
│   ├── 05-caso-practico-mysql.md           Diseño de almacenamiento para MySQL
│   ├── 06-seguridad-nfs.md                 Seguridad en NFS: riesgos y buenas prácticas
│   ├── 07-monitorizacion-almacenamiento.md Cómo saber si algo va a fallar antes de que falle
│   ├── 08-backup-y-recuperacion.md         Estrategia de backup que cierra el ciclo
│   └── 09-troubleshooting.md              Problemas reales y cómo resolverlos
│
├── labs/                                   ← Laboratorios ejecutados y verificados
│   ├── 01-nfs-lab-mint-fedora.md           NFS completo: Linux Mint (srv) + Fedora (cli)
│   └── 02-lvm-lab-ubuntu-server.md         LVM en Ubuntu Server: crear, extender, montar
│
├── scripts/                                ← Automatización: de manual a reproducible
│   ├── README.md                           Guía de uso de los scripts
│   ├── setup-nfs-server.sh                 Despliega un servidor NFS desde cero
│   ├── setup-lvm-mysql.sh                  Configura LVM optimizado para MySQL
│   ├── monitor-storage.sh                  Alerta cuando el espacio está al límite
│   └── backup-mysql-to-nfs.sh              Backup de MySQL hacia el servidor NFS
│
└── refs/
    └── comandos-referencia.md              Cheatsheet: todos los comandos en una página
```

---

## 📚 Documentación teórica

| # | Documento | Qué explica |
|---|-----------|-------------|
| 00 | [Entorno de laboratorio](docs/00-entorno-laboratorio.md) | VMs, hipervisor, red, por qué cada máquina |
| 01 | [RAID](docs/01-raid.md) | RAID 0/1/5/6/10 — funcionamiento, fallos, casos de uso reales |
| 02 | [LVM](docs/02-lvm.md) | La piscina de almacenamiento: PV, VG, LV, operaciones en caliente |
| 03 | [Sistemas de ficheros](docs/03-filesystems-ext4-xfs.md) | ext4 vs XFS: la elección que marca el rendimiento |
| 04 | [Pila de almacenamiento](docs/04-pila-almacenamiento.md) | El viaje de un dato desde el disco hasta la aplicación |
| 05 | [Caso práctico MySQL](docs/05-caso-practico-mysql.md) | RAID 10 + LVM + XFS: diseño argumentado para producción |
| 06 | [Seguridad NFS](docs/06-seguridad-nfs.md) | Por qué abrir NFS a toda la red es un error grave |
| 07 | [Monitorización](docs/07-monitorizacion-almacenamiento.md) | Detectar fallos antes de que ocurran |
| 08 | [Backup y recuperación](docs/08-backup-y-recuperacion.md) | Cerrar el ciclo: RAID no es backup |
| 09 | [Troubleshooting](docs/09-troubleshooting.md) | Errores reales y cómo salir de ellos |

---

## 🧪 Laboratorios

| Lab | Máquinas | Qué se practica |
|-----|----------|-----------------|
| [NFS: Mint + Fedora](labs/01-nfs-lab-mint-fedora.md) | Mint `192.168.11.143` + Fedora `192.168.11.142` | Servidor NFS, exports, montaje manual, fstab, prueba bidireccional |
| [LVM: Ubuntu Server](labs/02-lvm-lab-ubuntu-server.md) | Ubuntu Server | Crear PV/VG/LV, formatear, montar, extender en caliente |

---

## ⚙️ Scripts de automatización

| Script | Qué hace |
|--------|----------|
| [setup-nfs-server.sh](scripts/setup-nfs-server.sh) | Instala y configura NFS en un servidor Debian/Ubuntu desde cero |
| [setup-lvm-mysql.sh](scripts/setup-lvm-mysql.sh) | Crea la pila LVM optimizada para MySQL (VG + LV + XFS + fstab) |
| [monitor-storage.sh](scripts/monitor-storage.sh) | Comprueba espacio, estado RAID y salud de discos; envía alerta si es necesario |
| [backup-mysql-to-nfs.sh](scripts/backup-mysql-to-nfs.sh) | Hace dump de todas las BBDD MySQL y las guarda en el servidor NFS con rotación |

---

## 🖥️ Entorno de laboratorio

```
Hipervisor: VMware Workstation
Red interna: 192.168.11.0/24

┌─────────────────────────────────────────────────────────────┐
│                    Red VMware 192.168.11.0/24               │
│                                                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │  Linux Mint  │  │    Fedora    │  │   Ubuntu Server  │  │
│  │ .143         │  │    .142      │  │      .x          │  │
│  │ Servidor NFS │  │ Cliente NFS  │  │ LVM, RAID, discos│  │
│  └──────────────┘  └──────────────┘  └──────────────────┘  │
│                                                             │
│  ┌─────────────────────────────────────┐                   │
│  │       Windows 11 Enterprise         │                   │
│  │  Cliente SSH → todos los servidores │                   │
│  └─────────────────────────────────────┘                   │
└─────────────────────────────────────────────────────────────┘
```

La elección de usar Windows 11 como máquina de trabajo no es casual: en el 90% de las empresas el administrador gestiona servidores Linux desde una máquina Windows. Practicar ese flujo desde el principio elimina una fricción que muchos estudiantes no trabajan hasta que llegan a su primer empleo.

---

## 🔁 El ciclo completo

Este repositorio no documenta piezas sueltas. Documenta un ciclo completo que un sysadmin real necesita dominar:

```
1. Diseño        → ¿Qué RAID? ¿Qué sistema de ficheros? ¿Cuánto espacio? (docs/)
2. Despliegue    → Montar la infraestructura paso a paso (labs/)
3. Automatización → Convertir lo manual en reproducible (scripts/)
4. Operación     → Monitorizar, detectar problemas, resolverlos (docs/07, docs/09)
5. Continuidad   → Backup, recuperación, no perder datos nunca (docs/08)
```

---

## 💡 Reflexión técnica

Una cosa que aprendí durante este bloque: el almacenamiento en Linux no es difícil, pero sí tiene muchas capas que interactúan entre sí. El error más común es aprender cada capa por separado (RAID, luego LVM, luego NFS...) sin entender cómo encajan.

La clave está en la pila: RAID da redundancia al hardware, LVM da flexibilidad al espacio, el sistema de ficheros organiza los datos, y NFS los expone a otros equipos. Cada capa hace una cosa y la hace bien. Cuando entiendes eso, las decisiones de diseño se vuelven obvias.

---

## 🔖 Tecnologías y conceptos

`RAID 0/1/5/6/10` · `mdadm` · `LVM` · `pvcreate` · `vgcreate` · `lvcreate` · `lvextend` · `ext4` · `XFS` · `xfs_growfs` · `resize2fs` · `NFS v4` · `fstab` · `exportfs` · `mysqldump` · `cron` · `smartctl` · `Bash scripting` · `VMware` · `SSH` · `Linux Mint` · `Fedora` · `Ubuntu Server` · `Windows 11`

---

*Estudiante de ASIR — Administración de Sistemas Informáticos en Red*  
*Repositorio mantenido y actualizado activamente*
