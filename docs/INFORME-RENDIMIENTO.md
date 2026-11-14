# Informe de Rendimiento y Auditoría de Alto Rendimiento

Fecha: 2026-11-14  
Plataforma: Mac M1, macOS 15.7.9, Apple Swift 6.2.4 (Xcode)  
Entorno: Binarios optimizados en configuración Release (`-c release`)

---

## 1. Resumen Ejecutivo

Este informe consolida las mediciones y la verificación experimental de **SwiftAttributeGraph** bajo condiciones de carga real de interfaz de usuario declarativa (tipo SwiftUI) y estrés extremo.

> **Alcance (revisión del 2026-11-14).** Las cifras son reales y se reproducen en este Mac, pero **miden cargas
> sintéticas**, no una UI real, y varias conclusiones se matizan abajo. Léase con la sección 6 («Lo que este informe no
> prueba»).

El motor ha sido auditado contra los principios no negociables de arquitectura de grafos reactivos:
1. **Presupuesto de Frame UI ($\le 1,6\text{ ms}$)**: cumplido **en una carga sintética** (10.000 reglas independientes de una sola operación, sin jerarquía ni cuerpos de vista): media de **$0,513\text{ ms}$** y máximo de **$1,253\text{ ms}$** en 60 frames con 500 mutaciones cada uno. No es el caso objetivo de `DISENO-M0.md` §7 (1.000 filas con 5–10 atributos por fila).
2. **Sin recursión nativa en el camino reanudable**: cadenas de hasta 100.000 niveles evaluadas en frío en hilos con pila reducida (512 KB) sin desbordamiento, **solo con `ResumableRule`**. Los cierres síncronos (`Rule`, `StatefulRule`, `makeRule`) conservan su límite de profundidad en lecturas dinámicas nuevas (unos miles de niveles; medido en `DISENO-M4.md` §2).
3. **Borrado de aristas $O(1)$**: 50.000 desconexiones sobre un nodo común resueltas en **174,08 ms** lineales mediante swap-with-last con posición guardada.
4. **Ausencia total de fugas de memoria**: Tras crear y destruir 10.000 subgrafos (30.000 atributos), el contador de nodos regresa exactamente a la línea base (**0 nodos residuales**).
5. **Corte por versiones**: una escritura que la primera regla corta cuesta **$0,72\text{ ms}$**, frente a **$5,85\text{ ms}$** cuando el cambio se propaga por toda la cadena de 20.000 reglas. Son dos escenarios distintos del mismo banco, ya presentes en M0 (0,7 ms y 5,5 ms); **no es una aceleración atribuible al atajo de M1**.

---

## 2. Auditoría de Latencia de Frame (60 Frames Consecutivos @ 60 fps)

Simulación interactiva con 10.000 componentes montados en subgrafos independientes (`StressBenchmark`). Cada frame introduce 500 mutaciones directas (5% de la superficie de estado) y evalúa los dependientes observados:

| Métrica | Medida | Presupuesto Objetivo | Estado |
|---|---|---|---|
| **Montaje del árbol (10.000 componentes)** | **6,73 ms** | Inicial | — |
| **Frame 0 (render en frío)** | **10,70 ms** | Arranque | — |
| **Latencia media por frame** | **0,513 ms** | $\le 1,6\text{ ms}$ | ✅ CUMPLE |
| **Percentil 50 (Mediana)** | **0,477 ms** | $\le 1,6\text{ ms}$ | ✅ CUMPLE |
| **Percentil 95** | **0,648 ms** | $\le 1,6\text{ ms}$ | ✅ CUMPLE |
| **Percentil 99 (p99)** | **1,253 ms** (con 60 muestras es la última, es decir, **el máximo**) | $\le 1,6\text{ ms}$ | ✅ CUMPLE, sin valor estadístico como p99 |
| **Latencia máxima observada** | **1,253 ms** | $\le 2,5\text{ ms}$ | ✅ CUMPLE |
| **Vistas actualizadas por frame** | **500** | — | — |

---

## 3. Auditoría de Fan-Out Masivo (50.000 Lectores Directos)

Simulación de una variable global de entorno (`@Environment` / tema) leída por 50.000 reglas:

- **Tiempo de propagación dirty**: **0,506 ms** (marca iterativa de suciedad sin duplicados ni recursión).
- **Recálculo perezoso de los 50.000 lectores**: **17,169 ms** (~$0,34\ \mu\text{s}$ por regla evaluada).

---

## 4. Auditoría de Churn de Navegación y Ciclo de Vida

Simulación de entrada y salida de pantallas complejas:

- **Creación de 10.000 subgrafos (30.000 atributos)**: **7,11 ms**.
- **Liberación e invalidación de 10.000 subgrafos**: **8,38 ms**.
- **Fugas de memoria / Nodos residuales**: **0**.

---

## 5. Tabla Comparativa de Exigencias de Motores de Grafos

> **Nota:** la columna «Estándar de Referencia» recoge lo que **nuestros documentos de diseño** dicen de Compute, Salsa y
> otros motores. Los estudios originales (`AGENTS.md` §5) no estaban disponibles en las rutas locales al redactar este
> informe y **no se contrastó el código de esos proyectos**. «Coincide» significa «coincide con el diseño anotado», no
> «verificado contra la fuente».

| Exigencia | Estándar de Referencia (según nuestros diseños) | SwiftAttributeGraph | Resultado |
|---|---|---|---|
| **Pila de actualización** | Pila explícita (`UpdateStack` de Compute) | Pila iterativa en heap con índice de reanudación | ✅ Coincide con el diseño y tiene pruebas |
| **Identidad de atributo** | Índice 32 bits + Generación 32 bits (Salsa) | `AttributeID(index: UInt32, generation: UInt32)` | ✅ Coincide con el diseño y tiene pruebas |
| **Almacenamiento por ranuras** | Arrays paralelos indexados por ranura | `NodeTable` plana sin punteros indirectos | ✅ Coincide con el diseño y tiene pruebas |
| **Corte por versiones** | Época global y versión por nodo | `Graph.globalVersion` + `InputEdge.seenVersion` | ✅ Coincide con el diseño y tiene pruebas |
| **Poda de dependencias** | Poda por cursor de lectura | `pruneEdges` dinámico en cada ejecución | ✅ Coincide con el diseño y tiene pruebas |
| **Subgrafos y vida** | Destrucción jerárquica con invalidación diferida | `SubgraphTable` con árbol O(1) y posorden | ✅ Coincide con el diseño y tiene pruebas |
| **Comparación en caliente** | Comparación de bytes para tipos triviales | `ValueComparator` con caché de `ComparisonPlan` | ✅ Coincide con el diseño y tiene pruebas |
| **Reglas con estado** | Soporte de acumuladores y cambios diferenciales | `StatefulRule` y `RuleContext` | ✅ Coincide con el diseño y tiene pruebas |
| **Redirecciones indirectas** | Alias y proyecciones sin nodo extra | `IndirectNode` con resolución iterativa | ✅ Coincide con el diseño y tiene pruebas |
| **Batería de especificación** | Oráculos aleatorios y profundidad | M9 completo: 202 pruebas funcionales en verde | ✅ Coincide con el diseño y tiene pruebas |

---

## 6. Lo que este informe no prueba

1. **Carga de UI.** Los bancos (`StressBenchmark`, `UISimulator`) usan reglas triviales, sin cuerpos de vista con coste,
   sin jerarquía de dependencias, sin entorno repartido y sin la capa de vistas. Son una **cota inferior** del coste del
   motor, no una medida del presupuesto de un frame real.
2. **Percentiles.** Con 60 muestras, p95 y p99 son casi el máximo. Para percentiles significativos hacen falta cientos o
   miles de frames y varias ejecuciones.
3. **Profundidad en cierres síncronos.** Solo el camino reanudable evita la anidación nativa. Una capa de vistas que
   escriba `body` como cierre síncrono con lecturas implícitas conserva el límite de profundidad; la migración sigue siendo
   una decisión abierta (`DISENO-M4.md` §6 y §10).
4. **Contraste con los motores de referencia.** No se leyó el código de Compute, Salsa ni Preact Signals en esta etapa.
5. **Plataformas y versiones.** Un solo Mac M1 y macOS 15.7.9; Windows está aplazado y sin verificar.
6. **Memoria total y percentiles de memoria**, que siguen sin medirse.
7. **Ruido.** Las medidas varían del orden de 5 a 10 % entre ejecuciones (p. ej. «50 ciclos de 1.000 reglas»: 18,2 a
   20,3 ms en distintas sesiones); no se deben leer diferencias menores como mejoras o regresiones.
