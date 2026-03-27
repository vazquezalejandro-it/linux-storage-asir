# 💾 RAID — Redundant Array of Independent Disks

> RAID no es magia ni una solución universal. Es una herramienta con compromisos: sacrificas algo (capacidad, coste, rendimiento de escritura) a cambio de otra cosa (velocidad, redundancia). La clave es saber qué estás comprando.

---

## ¿Qué es RAID?

RAID es una técnica que combina múltiples discos físicos para que el sistema operativo los vea como una sola unidad de almacenamiento. Dependiendo del nivel elegido, se consiguen distintas combinaciones de:

- **Rendimiento** (leer/escribir más rápido usando varios discos a la vez)
- **Redundancia** (tolerar el fallo de uno o varios discos sin perder datos)
- **Capacidad** (aprovechar el espacio de todos los discos)

Ningún nivel de RAID da las tres cosas al máximo. Siempre hay compromisos.

> ⚠️ **RAID no es un backup.** Si borras un archivo, se borra en todos los discos. Si hay corrupción lógica, RAID no te salva. Para eso están las copias de seguridad.

---

## Conceptos fundamentales

Antes de ver cada nivel, hay tres conceptos que aparecen constantemente:

### Striping (distribución en franjas)
Los datos se dividen en bloques y se escriben en paralelo en varios discos. Resultado: mayor velocidad de lectura/escritura. Sin redundancia inherente.

```
Dato: [A][B][C][D]
Disco 1: [A][C]
Disco 2: [B][D]
```

### Mirroring (espejo)
Los datos se escriben idénticos en dos o más discos simultáneamente. Si uno falla, el otro tiene la copia exacta.

```
Dato: [X]
Disco 1: [X]
Disco 2: [X]  ← copia exacta
```

### Paridad
En lugar de duplicar datos completos, se calcula un valor matemático (paridad) a partir de los datos. Si un disco falla, ese valor permite reconstruir los datos perdidos. Ahorra espacio frente al espejo, pero tiene coste de cálculo.

---

## RAID 0 — Striping puro

### ¿Cómo funciona?
Los datos se distribuyen en franjas entre todos los discos. No hay redundancia de ningún tipo. Si un disco falla, se pierden **todos** los datos.

```
          RAID 0 (2 discos)
┌────────────┐   ┌────────────┐
│  Disco 1   │   │  Disco 2   │
│ ──────────│   │──────────  │
│ Bloque A1 │   │ Bloque A2  │
│ Bloque B1 │   │ Bloque B2  │
│ Bloque C1 │   │ Bloque C2  │
└────────────┘   └────────────┘
  Se leen/escriben en paralelo → más velocidad
```

| Parámetro | Valor |
|-----------|-------|
| Discos mínimos | 2 |
| Capacidad útil | 100% (suma de todos los discos) |
| Tolerancia a fallos | **0** — si falla 1 disco, se pierden todos los datos |
| Rendimiento lectura | ⭐⭐⭐⭐⭐ Excelente |
| Rendimiento escritura | ⭐⭐⭐⭐⭐ Excelente |

### ¿Cuándo usarlo?
- Datos temporales o cacheados que se pueden regenerar (ej: caché de render).
- Estaciones de trabajo de edición de vídeo donde la velocidad es prioritaria y hay backup separado.
- **Nunca** para datos que no puedas permitirte perder.

---

## RAID 1 — Espejo

### ¿Cómo funciona?
Cada escritura se realiza simultáneamente en dos (o más) discos idénticos. El espacio útil es solo el de un disco, porque el otro es la copia.

```
          RAID 1 (2 discos)
┌────────────┐   ┌────────────┐
│  Disco 1   │   │  Disco 2   │
│ ──────────│   │──────────  │
│ Bloque A  │   │ Bloque A   │  ← mismo dato
│ Bloque B  │   │ Bloque B   │  ← mismo dato
│ Bloque C  │   │ Bloque C   │  ← mismo dato
└────────────┘   └────────────┘
```

| Parámetro | Valor |
|-----------|-------|
| Discos mínimos | 2 |
| Capacidad útil | 50% (solo un disco del par) |
| Tolerancia a fallos | 1 disco — puede fallar uno y el sistema sigue |
| Rendimiento lectura | ⭐⭐⭐ Puede leer de ambos discos |
| Rendimiento escritura | ⭐⭐ Debe escribir en ambos |

### ¿Cuándo usarlo?
- Discos de sistema operativo donde la redundancia importa más que la capacidad.
- Sistemas donde la simplicidad es clave (fácil de gestionar y recuperar).
- Servidores pequeños con solo 2 discos disponibles.

---

## RAID 5 — Striping con paridad distribuida

### ¿Cómo funciona?
Los datos se distribuyen en franjas entre los discos (como RAID 0), pero además se calcula un bloque de paridad que se distribuye rotativamente entre todos los discos. Esto permite reconstruir los datos si falla **un** disco.

```
          RAID 5 (3 discos)
┌──────────┐  ┌──────────┐  ┌──────────┐
│ Disco 1  │  │ Disco 2  │  │ Disco 3  │
│──────────│  │──────────│  │──────────│
│   A1     │  │   A2     │  │  Ap(A)   │  ← paridad de A
│   B1     │  │  Bp(B)   │  │   B2     │  ← paridad de B (rotada)
│  Cp(C)   │  │   C1     │  │   C2     │  ← paridad de C (rotada)
└──────────┘  └──────────┘  └──────────┘
```

La paridad está distribuida para que no haya un único disco "de paridad" que sea el cuello de botella.

| Parámetro | Valor |
|-----------|-------|
| Discos mínimos | 3 |
| Capacidad útil | (N-1) discos — con 4×2TB → 6TB útiles |
| Tolerancia a fallos | **1 disco** |
| Rendimiento lectura | ⭐⭐⭐⭐ Bueno |
| Rendimiento escritura | ⭐⭐ Penalización por cálculo de paridad |

### ⚠️ El problema de RAID 5 con discos grandes

Con discos de varios TB, una reconstrucción tras un fallo puede tardar **horas o días**. Durante ese tiempo, si falla un segundo disco (lo cual es estadísticamente probable dado el estrés de la reconstrucción), se pierden **todos** los datos. Este problema ha hecho que RAID 5 esté en declive para entornos críticos con discos grandes.

### ¿Cuándo usarlo?
- Almacenamiento de archivos o backups donde se leen con frecuencia pero se escriben poco.
- NAS doméstico o de pequeña empresa con discos no demasiado grandes.
- Cuando la relación capacidad/coste importa más que la velocidad de escritura.

---

## RAID 6 — Striping con doble paridad

### ¿Cómo funciona?
Igual que RAID 5 pero con **dos** bloques de paridad independientes distribuidos entre los discos. Esto permite tolerar el fallo simultáneo de **dos discos**.

| Parámetro | Valor |
|-----------|-------|
| Discos mínimos | 4 |
| Capacidad útil | (N-2) discos — con 6×2TB → 8TB útiles |
| Tolerancia a fallos | **2 discos simultáneos** |
| Rendimiento lectura | ⭐⭐⭐⭐ Bueno |
| Rendimiento escritura | ⭐ Penalización mayor que RAID 5 (doble paridad) |

### ¿Cuándo usarlo?
- Almacenamiento de gran capacidad con discos de muchos TB donde la reconstrucción es lenta.
- Entornos donde se puede tolerar la penalización de escritura a cambio de mayor seguridad.
- NAS empresarial con muchos discos.

---

## RAID 10 — Espejo + Striping (1+0)

### ¿Cómo funciona?
RAID 10 combina lo mejor de RAID 1 y RAID 0: primero crea parejas de espejos (RAID 1), y luego hace striping entre esas parejas (RAID 0). Se necesita un número par de discos.

```
              RAID 10 (4 discos)
    ┌──────────────────────────────────┐
    │         Striping (RAID 0)        │
    │                                  │
    │  ┌────────────┐  ┌────────────┐  │
    │  │  Espejo 1  │  │  Espejo 2  │  │
    │  │ ┌──┐ ┌──┐ │  │ ┌──┐ ┌──┐ │  │
    │  │ │D1│ │D2│ │  │ │D3│ │D4│ │  │
    │  │ └──┘ └──┘ │  │ └──┘ └──┘ │  │
    │  │  copia    │  │  copia    │  │
    │  └────────────┘  └────────────┘  │
    └──────────────────────────────────┘

    D1 = D2 (espejo)    D3 = D4 (espejo)
    Los datos se distribuyen en franja entre D1/D3
```

| Parámetro | Valor |
|-----------|-------|
| Discos mínimos | 4 (número par) |
| Capacidad útil | 50% del total |
| Tolerancia a fallos | Al menos 1 disco por espejo — puede perder hasta N/2 discos si son del espejo correcto |
| Rendimiento lectura | ⭐⭐⭐⭐⭐ Excelente |
| Rendimiento escritura | ⭐⭐⭐⭐ Muy bueno |

### Tolerancia a fallos en detalle

Con 4 discos (2 parejas):
- Falla D1 → D2 tiene la copia → el sistema sigue sin pérdida de datos ✅
- Falla D1 y D3 → cada espejo pierde un disco pero sigue intacto ✅
- Falla D1 y D2 → ambos discos del mismo espejo → **pérdida de datos** ❌

La probabilidad de que fallen los dos discos del mismo espejo antes de reemplazar uno es baja, pero no nula. En la práctica, RAID 10 es uno de los RAID más robustos para entornos de producción.

### ⭐ Por qué RAID 10 es la elección para bases de datos (MySQL, PostgreSQL, etc.)

Las bases de datos tienen un patrón de I/O muy exigente:
- **Muchas escrituras aleatorias y pequeñas** (inserts, updates, commits de transacciones).
- **Lecturas frecuentes** de filas individuales o rangos pequeños.
- Los índices se actualizan en cada write.

RAID 10 es ideal porque:
1. El striping distribuye la carga de I/O entre varios discos → mejor rendimiento.
2. El espejo garantiza que si un disco falla en plena carga, el servicio no se detiene.
3. La reconstrucción tras un fallo es mucho más rápida que en RAID 5/6 (solo hay que copiar el espejo, no recalcular paridad).

---

## Tabla comparativa

| Nivel | Discos mín. | Capacidad útil | Fallos tolerados | Lectura | Escritura | Uso ideal |
|-------|-------------|----------------|------------------|---------|-----------|-----------|
| RAID 0 | 2 | 100% | 0 | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | Caché, temporal |
| RAID 1 | 2 | 50% | 1 | ⭐⭐⭐ | ⭐⭐ | SO, sistemas críticos simples |
| RAID 5 | 3 | (N-1)/N | 1 | ⭐⭐⭐⭐ | ⭐⭐ | NAS, archivos, backups |
| RAID 6 | 4 | (N-2)/N | 2 | ⭐⭐⭐⭐ | ⭐ | Grandes arrays, discos enormes |
| RAID 10 | 4 | 50% | ≥1 por pareja | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | **BBDD, producción crítica** |

---

## RAID software vs RAID hardware

Todo lo visto aplica tanto a RAID hardware (tarjeta controladora dedicada) como a RAID software (gestionado por el SO, con `mdadm` en Linux).

- **RAID hardware**: mayor rendimiento, independiente del SO, pero costoso.
- **RAID software con mdadm**: gratuito, flexible, suficiente para la mayoría de entornos. Es lo que se usa en laboratorio y en muchos servidores de producción.

---

*Siguiente: [LVM — Gestión de volúmenes lógicos](02-lvm.md)*
