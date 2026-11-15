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
1. **Presupuesto de Frame UI ($\le 1,6\text{ ms}$)**: cumplido **en una carga sintética** (10.000 reglas independientes de una sola operación, sin jerarquía ni cuerpos de vista): media de **$0,524\text{ ms}$** y máximo de **$0,654\text{ ms}$** en 60 frames con 500 mutaciones cada uno. No es el caso objetivo de `DISENO-M0.md` §7 (1.000 filas con 5–10 atributos por fila).
2. **Sin recursión nativa en el camino reanudable**: cadenas de hasta 100.000 niveles evaluadas en frío en hilos con pila reducida (512 KB) sin desbordamiento, **solo con `ResumableRule`**. Los cierres síncronos (`Rule`, `StatefulRule`, `makeRule`) conservan su límite de profundidad en lecturas dinámicas nuevas (unos miles de niveles; medido en `DISENO-M4.md` §2).
3. **Borrado de aristas $O(1)$**: 50.000 desconexiones sobre un nodo común resueltas en **174,08 ms** lineales mediante swap-with-last con posición guardada, y poda de la mitad de 20.000 entradas de una regla en **4,85 ms** mediante marca y barrido.
4. **Ausencia total de fugas de memoria**: Tras crear y destruir 10.000 subgrafos (30.000 atributos), el contador de nodos regresa exactamente a la línea base (**0 nodos residuales**).
5. **Corte por versiones**: una escritura que la primera regla corta cuesta **$0,72\text{ ms}$**, frente a **$5,85\text{ ms}$** cuando el cambio se propaga por toda la cadena de 20.000 reglas. Son dos escenarios distintos del mismo banco, ya presentes en M0 (0,7 ms y 5,5 ms); **no es una aceleración atribuible al atajo de M1**.

---

## 2. Auditoría de Latencia de Frame (60 Frames Consecutivos @ 60 fps)

Simulación interactiva con 10.000 componentes montados en subgrafos independientes (`StressBenchmark`, revalidado tras la alineación C1–C24 y la eliminación de `NodeTable.lastVerified`). Cada frame introduce 500 mutaciones directas (5% de la superficie de estado) y evalúa los dependientes observados:

| Métrica | Medida | Presupuesto Objetivo | Estado |
|---|---|---|---|
| **Montaje del árbol (10.000 componentes)** | **9,58 ms** | Inicial | — |
| **Frame 0 (render en frío)** | **9,75 ms** | Arranque | — |
| **Latencia media por frame** | **0,524 ms** | $\le 1,6\text{ ms}$ | ✅ CUMPLE |
| **Percentil 50 (Mediana)** | **0,513 ms** | $\le 1,6\text{ ms}$ | ✅ CUMPLE |
| **Percentil 95** | **0,650 ms** | $\le 1,6\text{ ms}$ | ✅ CUMPLE |
| **Percentil 99 (p99)** | **0,654 ms** (con 60 muestras es la última, es decir, **el máximo**) | $\le 1,6\text{ ms}$ | ✅ CUMPLE, sin valor estadístico como p99 |
| **Latencia máxima observada** | **0,654 ms** | $\le 2,5\text{ ms}$ | ✅ CUMPLE |
| **Vistas actualizadas por frame** | **500** | — | — |

---

## 3. Auditoría de Fan-Out Masivo (50.000 Lectores Directos)

Simulación de una variable global de entorno (`@Environment` / tema) leída por 50.000 reglas:

- **Tiempo de propagación dirty**: **0,477 ms** (marca iterativa de suciedad sin duplicados ni recursión).
- **Recálculo perezoso de los 50.000 lectores**: **17,052 ms** (~$0,34\ \mu\text{s}$ por regla evaluada).

---

## 4. Auditoría de Churn de Navegación y Ciclo de Vida

Simulación de entrada y salida de pantallas complejas:

- **Creación de 10.000 subgrafos (30.000 atributos)**: **6,75 ms**.
- **Liberación e invalidación de 10.000 subgrafos**: **7,64 ms**.
- **Fugas de memoria / Nodos residuales**: **0**.
- **Huella de tablas en `UISimulator` (paso 8)**: **684 bytes** (8 recálculos totales, 7 aristas activas).

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
| **Redirecciones indirectas** | Alias y proyecciones sin nodo extra | `IndirectNode` con resolución iterativa, `setSource`, `resetSource` y `Focus` | ✅ Coincide con el diseño y con `AttributeGraph` nativo |
| **Batería de especificación** | Oráculos aleatorios y profundidad | M9 + C1–C24: **215 pruebas funcionales en verde (0 known issues)** y **22 escenarios `NativeProbe` al 100 %** | ✅ Coincide con el diseño y con `AttributeGraph` nativo |

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

---

## 7. Banco comparativo, escenario S1: motor frente a SwiftUI real

Fecha: 2026-11-14. Mac M1, macOS 15.7.9, Swift 6.2.4. Diseño y criterios: [DISENO-BANCO-COMPARATIVO.md](DISENO-BANCO-COMPARATIVO.md).
El código está en `parity/Bench` (local, no versionado); los resultados en bruto, en
`parity/Bench/resultados-macos-15.7.9-S1-run1..5.txt`.

**Escenario:** 1.000 filas. Cada fila tiene un estado, un `body` de fila que lo lee y dos hijos que leen el resultado de la fila.
Cambiar el estado de una fila ejecuta **3 `body`** (en el motor, 3 reglas). En cada fotograma se cambian k filas
(k = 1, 10, 50, 100). Cada ejecución del proceso mide **1.000 fotogramas** tras 50 de calentamiento, para cada k y
cada implementación; **5 ejecuciones** alternando qué implementación va primero. Los `body` hacen un trabajo trivial
idéntico. En SwiftUI la latencia va de justo antes de la primera mutación a la marca de tiempo del último `body`; en el motor,
de antes de la primera escritura al final de las lecturas de lo que se ensució.

| k filas cambiadas | Motor: mediana | Motor: peor p99 de las 5 ejecuciones | SwiftUI: mediana | SwiftUI: peor p99 | SwiftUI / motor |
|---|---|---|---|---|---|
| 1 | 0,002 ms | 0,002 ms | 0,647 ms | 0,869 ms | ≈ 324× |
| 10 | 0,018 ms | 0,023 ms | 2,521 ms | 2,866 ms | ≈ 140× |
| 50 | 0,087 ms | 0,118 ms | 9,018 ms | 9,977 ms | ≈ 104× |
| 100 | 0,175 ms | 0,196 ms | 17,495 ms | 19,028 ms | ≈ 100× |

- **Paridad:** en las 5 ejecuciones y en los 4 valores de k, **0 fotogramas** con un recuento de `body` distinto del esperado, en las dos
  implementaciones.
- **Escala:** el motor cuesta ≈ **1,75 µs por fila cambiada** (3 reglas y una escritura) de forma casi constante; SwiftUI ≈ 175 µs
  por fila. Ambos crecen casi linealmente con k.
- **Dispersión entre ejecuciones:** las medianas del motor varían ≤ 3 % entre ejecuciones; las de SwiftUI, hasta ≈ 7 % (k = 1).
- **Memoria al montar 1.000 filas** (memoria residente del proceso, bytes por fila): motor **475 a 1.376** (el dato es muy
  ruidoso a esta escala; falta usar `estimatedMemoryFootprint`); SwiftUI **118.000 a 128.000**.

**Criterios de la nota (§6), para S1:** (1) paridad: **cumple**; (2) p99 del motor ≤ 1,6 ms con k = 50: **0,118 ms en el peor caso**,
unas 13 veces por debajo; (3) escala casi lineal: **cumple**; (4) memoria registrada, sin umbral aún; (5) sin regresión: no se
tocó el motor. **S2 a S6 siguen sin medir.**

**Cómo leer estas cifras (límites):**
1. La razón de 100× no es una medida de «el algoritmo del motor es 100 veces mejor». SwiftUI incluye planificación,
   diferencial y layout, y el motor aquí solo evalúa las reglas. Lo que dice es que **el motor consume del orden del 1 % de lo
   que cuesta actualizar esas filas en SwiftUI**, y que con 100 filas cambiadas el motor gasta 0,18 ms de un fotograma de 16,6 ms.
2. Los `body` son triviales; los reales cuestan más, y eso lo pagará quien los escriba.
3. Las filas del motor son 4 reglas por fila escritas a mano, sin capa de vistas, y menos que las 5 a 10 del objetivo.
4. La ventana está fuera de pantalla; la latencia de SwiftUI incluye su planificador y no se puede separar del coste del grafo.
5. Un solo Mac M1 y macOS 15.7.9; no se extrapola a Windows.

---

## 8. Banco comparativo, escenarios S2 a S6

Fecha: 2026-11-14. Mismo equipo, método y limitaciones que la sección 7. **300 fotogramas por caso tras 20 de calentamiento, 3 ejecuciones**
alternando qué implementación va primero (S6: 15 repeticiones por ejecución). Resultados en bruto:
`parity/Bench/resultados-macos-15.7.9-S2-S6-run1..3.txt`. Medianas de las medianas de las 3 ejecuciones; «peor p99» es el mayor de los 3.

| Escenario | Motor: mediana | Motor: peor p99 | SwiftUI: mediana | Cuentas de `body` |
|---|---|---|---|---|
| S2, N = 100 (entorno leído por la mitad) | 0,025 ms | 0,082 ms | 5,09 ms | 51 / 51 |
| S2, N = 1.000 | 0,228 ms | 0,284 ms | 39,93 ms | 501 / 501 |
| S2, N = 5.000 | 1,146 ms | 1,209 ms | 205,96 ms | 2.501 / 2.501 |
| S3, añadir una fila a 1.000 | 0,043 ms | 0,060 ms | 36,69 ms | 2 / 2 |
| S3, quitar una fila del medio | 0,043 ms | 0,054 ms | 0,284 ms (*) | 1 / 1 |
| S3, invertir 1.000 filas | 0,050 ms | 0,061 ms | 0,446 ms (*) | 1 / 1 |
| S4, jerarquía de 50 niveles | 0,020 ms | 0,061 ms | 0,494 ms | 52 / 52 |
| S4, jerarquía de 200 niveles | 0,138 ms | 0,257 ms | 2,357 ms | 202 / 202 |
| S5, cambio de rama con 100 hijos | 0,101 ms | 0,271 ms | 13,86 ms | 102 / 102 |
| S6, arranque en frío de 1.000 filas | 3,06 ms | — | 255,4 ms | — |

**Paridad de `body`:** 0 fotogramas con recuento distinto en todos los escenarios y las 3 ejecuciones (columna «cuentas»: obtenidas / esperadas).
**S5:** el desmontaje de la rama vieja cuesta en el motor 0,04–0,06 ms de mediana y queda fuera de la latencia de la tabla.

**Criterios de la nota (§6):**
1. Paridad: **cumple** en S1 a S5.
2. p99 del motor ≤ 1,6 ms en S1 (k = 50) y en S2 con N = 1.000: **cumple** (0,118 y 0,284 ms). En S2 con N = 5.000 el p99 es de **1,21 ms**: cumple, pero con un margen de solo ≈ 25 %.
3. Escala casi lineal: **cumple** en S1 y S2 (N × 10 da ≈ ×9 en el motor); en S4, 50 → 200 niveles da ≈ ×7 en el motor (4× más niveles), algo por encima de lineal, dentro del ruido de esas medidas.
4. Memoria: SwiftUI ≈ 81.000–84.000 bytes por fila al repetir el arranque (S6) frente a 118.000–128.000 en S1; el dato del motor por memoria residente **no es utilizable** (0 bytes: el asignador reutiliza lo liberado). Falta medir el motor con `estimatedMemoryFootprint`.
5. Sin regresión: no se tocó el motor.

**Salvedades:**
- (*) **S3, quitar e invertir no son comparables.** En SwiftUI solo se ejecuta el `body` de la raíz y la medida termina en él; el diferencial y el layout posteriores quedan fuera, así que su latencia está subestimada. El motor sí incluye su diferencial de ids.
- **S4 tiene mucha dispersión entre ejecuciones** en SwiftUI (200 niveles: de 1,36 a 2,38 ms de mediana) y algo en el motor (0,095–0,145 ms); no se debe leer una diferencia menor que eso.
- **S4 usa `AnyView` en cada nivel** para romper la recursión de tipos, lo que añade coste propio a SwiftUI.
- **S5 mide hasta el último `body` del árbol nuevo.** El desmontaje del viejo en SwiftUI ocurre después y no se mide.
- **Todo lo dicho al final de la sección 7 sigue valiendo:** cargas sintéticas, `body` triviales, una máquina y una versión, y que la razón entre SwiftUI y el motor no mide la eficiencia del algoritmo.
