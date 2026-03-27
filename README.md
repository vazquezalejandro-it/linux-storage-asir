# 🗄️ Almacenamiento en Linux — Laboratorios y Teoría ASIR

> **Repositorio de prácticas reales ejecutadas en entorno de laboratorio con máquinas virtuales.**  
> Todo el contenido ha sido probado, verificado y documentado personalmente durante un bloque intensivo de almacenamiento en Linux.

---

## ¿Qué encontrarás aquí?

Este repositorio documenta un bloque completo de **almacenamiento en Linux** con enfoque profesional, cubriendo desde los conceptos más fundamentales hasta laboratorios reales con múltiples VMs en red.

No es un resumen de Wikipedia. Es lo que he aprendido tocando máquinas.

---

## 🗺️ Estructura del repositorio

```
linux-storage-asir/
│
├── README.md                         ← Este archivo
│
├── docs/
│   ├── 00-entorno-laboratorio.md     ← Descripción del entorno de VMs
│   ├── 01-raid.md                    ← RAID 0/1/5/6/10 explicado a fondo
│   ├── 02-lvm.md                     ← LVM: PV, VG, LV y casos de uso
│   ├── 03-filesystems-ext4-xfs.md    ← ext4 vs XFS: cuándo usar cada uno
│   ├── 04-pila-almacenamiento.md     ← Visión global: del disco al archivo
│   └── 05-caso-practico-mysql.md     ← Diseño de almacenamiento para MySQL
│
└── labs/
    └── 04-nfs-lab-mint-fedora.md     ← Lab NFS completo: Mint (srv) + Fedora (cli)
```

---

## 📚 Contenido teórico

| Documento | Qué cubre |
|-----------|-----------|
| [Entorno de laboratorio](docs/00-entorno-laboratorio.md) | VMs, hipervisor, red, roles de cada máquina |
| [RAID](docs/01-raid.md) | RAID 0, 1, 5, 6, 10 — funcionamiento, capacidad, fallos, casos de uso |
| [LVM](docs/02-lvm.md) | Physical Volumes, Volume Groups, Logical Volumes — la piscina de almacenamiento |
| [Sistemas de ficheros](docs/03-filesystems-ext4-xfs.md) | ext4 vs XFS — diferencias, cuándo usar cada uno |
| [Pila de almacenamiento](docs/04-pila-almacenamiento.md) | Cómo viaja un dato desde el disco físico hasta el archivo |
| [Caso práctico MySQL](docs/05-caso-practico-mysql.md) | Diseño argumentado: RAID 10 + LVM + XFS para una BBDD |

---

## 🧪 Laboratorios

| Laboratorio | Máquinas | Tecnología |
|-------------|----------|------------|
| [NFS: Mint + Fedora](labs/04-nfs-lab-mint-fedora.md) | Linux Mint `192.168.11.143` + Fedora `192.168.11.142` | NFS v4, fstab |

---

## 🖥️ Entorno de laboratorio (resumen)

```
Hipervisor: VMware
Red: 192.168.11.0/24

┌──────────────────────────────────────────────────────┐
│                   Red local VMware                   │
│                  192.168.11.0/24                     │
│                                                      │
│  ┌─────────────┐   ┌──────────────┐   ┌───────────┐ │
│  │ Linux Mint  │   │    Fedora    │   │ Ubuntu    │ │
│  │ .143        │   │    .142      │   │ Server    │ │
│  │ Srv NFS     │   │  Cliente NFS │   │ Prácticas │ │
│  └─────────────┘   └──────────────┘   └───────────┘ │
│                                                      │
│  ┌──────────────────────────────────┐               │
│  │   Windows 11 Enterprise          │               │
│  │   Cliente SSH → servidores Linux │               │
│  └──────────────────────────────────┘               │
└──────────────────────────────────────────────────────┘
```

---

## 🧠 Por qué este repositorio

El almacenamiento en Linux es uno de los pilares de cualquier sysadmin. Saber qué RAID elegir, cómo dimensionar LVM, qué sistema de ficheros usar y cómo compartir almacenamiento por red no es algo que se aprenda leyendo: se aprende rompiendo cosas en un lab y entendiéndolas de verdad.

Este repositorio es la evidencia de ese proceso.

---

## 🔖 Tecnologías y conceptos cubiertos

`RAID` · `LVM` · `ext4` · `XFS` · `NFS` · `fstab` · `exportfs` · `VMware` · `SSH` · `Linux Mint` · `Fedora` · `Ubuntu Server` · `Windows 11`

---

*Estudiante de ASIR — Administración de Sistemas Informáticos en Red*
