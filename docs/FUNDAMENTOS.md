# Fundamentos del motor: preguntas antes de escribir código

Fecha: 2026-11-14. **Antes de M0.** Este documento fija la tecnología, la estructura de carpetas y los elementos del
motor, y lista las preguntas de diseño con una propuesta para cada una. Las marcadas **[dueño]** las decide el
dueño; las marcadas **[medida]** se deciden con un test y una medida en M0.

**Decisiones del dueño (2026-11-14):**

| Pregunta | Decisión |
|---|---|
| P1, API pública | `Attribute<Value>` ligero (solo el ID) |
| P2, nombres | Los de AttributeGraph donde coincida el concepto (`Attribute`, `Rule`, `StatefulRule`, `Subgraph`…) |
| Tests | Swift Testing |
| P5, errores | `precondition` para los errores de programación; `throws` solo para lo recuperable |
| P6, hilos | Un grafo por hilo |
| P8, tiempo y animaciones | Fuera del motor |
| P9, compatibilidad con `GraphNode` | No |

Quedan para medir en M0: P3 (forma de la regla) y P4 (dónde vive el valor).

## 1. Tecnología

| Pregunta | Propuesta | Motivo |
|---|---|---|
| ¿Qué lenguaje? | Swift puro | La ganancia medida en SwiftGraph vino de las estructuras de datos, no del lenguaje (G1–G3: 3,8×; G5: 18×) |
| ¿Qué versión de Swift? | `swift-tools-version: 6.2`, toolchain 6.4.1 | Comprobado en esta máquina (ARM64): compilan `~Copyable`, `InlineArray`, `Span`, `throws` tipado y `_isPOD` |
| ¿Modo de concurrencia? | Swift 6 estricto | Un grafo por hilo; los tipos del motor no son `Sendable` salvo los ID, y el compilador lo hace cumplir |
| ¿Foundation? | **No** en el motor | Sin dependencias (P5). Para el tiempo de los tests de rendimiento basta `ContinuousClock` de la biblioteca estándar |
| ¿Almacenamiento por hilo? | TLS nativo (`TlsAlloc` en Windows) aislado en un solo archivo | G5. Si un día se porta, se cambia solo ese archivo |
| ¿Punteros `Unsafe*`? | Solo dentro de los tipos de almacén, nunca en la API pública, y cada uso con su test | Rendimiento sin perder la seguridad en la superficie |
| ¿Framework de tests? | **Swift Testing** (`@Test`, `#expect`) | Decidido por el dueño (2026-11-14). Funciona en este toolchain |
| ¿Cómo se mide? | Tests de rendimiento marcados, en release, con mediana de varias ejecuciones; resultados en `PLAN-MOTOR.md` | Lo aprendido: en la máquina virtual hay mucho ruido, así que una sola ejecución no vale |
| ¿Plataformas? | Windows ARM64 (principal) y x64 | Igual que SwiftGraph |

## 2. Estructura de carpetas

Un solo módulo público (`SwiftAttributeGraph`). Lo interno se marca `internal` o `package`. Carpetas por
responsabilidad y un tipo principal por archivo:

```
Sources/SwiftAttributeGraph/
  Identity/      AttributeID (índice + generación), SubgraphID
  Storage/       Tabla de ranuras, lista libre, almacén de valores
  Node/          Parte común del nodo (estado, banderas, versión), aristas de entrada y de salida
  Graph/         Graph: crear, leer, escribir, quitar; contadores
  Rule/          Rule, StatefulRule (o cierres, según §4), contexto de regla
  Update/        Propagación de sucio, pila de actualización, verificación por versiones
  Tracking/      Contexto de lectura actual (TLS), registro y poda de dependencias
  Subgraph/      Jerarquía, subgrafo actual, invalidación diferida
  Comparison/    Comparador por tipo (Equatable, tipos triviales, «siempre distinto»)
  Indirect/      Atributos indirectos y desplazados (M6)
  Debug/         Volcado del grafo, trazas, contadores de memoria
Tests/SwiftAttributeGraphTests/
  Unit/          Una carpeta por carpeta de Sources
  Oracle/        Comparación con un modelo de referencia simple (recalcular todo) en grafos aleatorios
  Depth/         Profundidad ≥ 20.000 por cada recorrido (P1)
  Lifetime/      nodeCount vuelve a la base (P2)
  Performance/   Medidas en release
docs/            FUNDAMENTOS.md (este), PLAN-MOTOR.md, una nota de diseño por pieza
```

## 3. Elementos que necesita el motor

| Elemento | Responsabilidad | Pieza |
|---|---|---|
| `AttributeID` | Nombrar un atributo; detectar IDs de atributos ya borrados | M0 |
| Tabla de ranuras | Guardar nodos por índice; reutilizar huecos | M0 |
| Nodo de valor (entrada) | Valor escrito desde fuera; compara al escribir | M0 |
| Nodo de regla | Valor calculado a partir de otros; perezoso | M0 |
| Aristas | Entrada: fuente y versión vista. Salida: dependiente | M0, M1, M7 |
| Propagación | Marcar «posiblemente sucio» hacia delante, iterativo | M0 |
| Actualización | Recalcular al leer, con pila explícita, en orden de lectura | M0, M4 |
| Versiones y corte | No recalcular si ninguna entrada cambió de versión | M1 |
| Comparador por tipo | Igualdad rápida resuelta una vez | M2 |
| Rastreo | Saber qué lee la regla en curso; podar lo no leído | M0, M7 |
| Reglas con estado | Valor anterior; qué entradas cambiaron | M3 |
| Subgrafos | Dueños jerárquicos; liberar en bloque; invalidación diferida | M5 |
| Indirectos | Redirigir o leer un campo de otro atributo | M6 |
| Observación | Avisar al cliente (la UI) cuando algo que observa queda sucio | M0 |
| Lotes | Agrupar escrituras en una sola propagación | M0 |
| Ciclos | Detectarlos y dar un error claro | M0 |
| Depuración | Volcado, contadores, memoria | M8 |

## 4. Preguntas de diseño

| # | Pregunta | Opciones | Propuesta | Quién |
|---|---|---|---|---|
| P1 | ¿Cómo es la API pública? | (a) `Attribute<Value>`: un *struct* ligero con solo el ID, como AttributeGraph. (b) Un objeto nodo, como el `GraphNode` actual | **(a)**: es lo que espera una capa tipo SwiftUI, no expone el almacén y no hay ARC por atributo en la API | [dueño] |
| P2 | ¿Nombres como los de AttributeGraph (`Attribute`, `Rule`, `StatefulRule`, `Subgraph`, `WeakAttribute`)? | Sí / nombres propios | **Sí**, en lo que coincida el concepto: facilita traducir las ideas de OpenSwiftUI y de la documentación existente | [dueño] |
| P3 | ¿Cómo se escribe una regla? | (a) Cierre `() -> Value`. (b) Tipo con `var value` que cumple `Rule` | **Las dos**: el tipo como forma principal (sin reservar un cierre por nodo) y el cierre como atajo | [medida] |
| P4 | ¿Dónde vive el valor? | En el objeto nodo / en almacenes por tipo | Empezar en el nodo (lo probado en G2) y medir | [medida] |
| P5 | ¿Errores? | `throws` en todas partes / `precondition` para errores de programación | **Mixto**: ID de un atributo borrado, ciclo o tipo equivocado son errores de programación (`precondition` con mensaje claro); solo lo recuperable lanza | [dueño] |
| P6 | ¿Hilos? | Un grafo por hilo / grafo compartido con candados | **Un grafo por hilo**, comprobado en depuración | [dueño] |
| P7 | ¿Qué es «igual» para un tipo no `Equatable`? | Siempre distinto / comparar bytes si es trivial / reflexión | **Equatable → `==`; trivial (`_isPOD`) → bytes; resto → distinto** | Decidido por los estudios |
| P8 | ¿El tiempo y las animaciones van en el motor? | Sí, como AttributeGraph / No | **No**: el motor da «valor y versión»; el tiempo es una entrada más que pone la UI | [dueño] |
| P9 | ¿Hace falta compatibilidad con el `GraphNode` actual de SwiftGraph? | Sí / no | **No**: proyecto nuevo. La UI se adaptará una vez, al conectar | [dueño] |
| P10 | ¿Cómo se demuestra que funciona? | Tests unitarios / más un oráculo | **Oráculo**: grafos aleatorios comparados con un modelo simple que lo recalcula todo, más los tests de profundidad, de vida y de rendimiento | Decidido |

## 5. Lo que este documento cambia del plan

Una vez respondidas las preguntas **[dueño]**:
- `PLAN-MOTOR.md` §2 y §4 se actualizan con las respuestas.
- `Package.swift` pasa a `swift-tools-version: 6.2` y se crea la estructura de carpetas de §2.
- Empieza M0.

## 6. Preguntas de comportamiento frente al AttributeGraph de Apple

Añadido tras M0–M9. La hipótesis de trabajo es que **el grafo construido coincide con el AttributeGraph original**.
Como Apple no publica su código, la única vía es la ingeniería inversa por comportamiento: se formula una pregunta, se
**fija la predicción antes de medir**, se observa en el nativo (`NativeProbe`) y en nuestro motor, y se comparan
«ejecuta / salta» y los contadores por regla. Acertar sube la confianza sin demostrar nada general; una divergencia
obliga a corregir el motor o la hipótesis.

Una buena pregunta se responde observando, puede salir mal y es estrecha (una sola cosa por escenario).
Estado: **abiertas**, salvo lo ya cubierto por los ocho escenarios de `ESTUDIO-ATTRIBUTEGRAPH-NATIVO.md` y
`ESTUDIO-DIAMANTES-NATIVOS.md` (reglas `Int`, grafos pequeños).

| # | Tema | Pregunta |
|---|---|---|
| C1 | Reglas con estado | Si la regla no cambia su valor, ¿cuenta como cambio para sus dependientes? |
| C2 | Reglas con estado | ¿Se ejecuta cuando cambia una entrada que no leyó la última vez? |
| C3 | Reglas con estado | ¿Ve el valor anterior si se invalidó y se restauró antes de leer? |
| C4 | Selectores | Al cambiar de rama, ¿se poda de inmediato la dependencia que ya no se lee? |
| C5 | Selectores | ¿Importa el orden de lectura para el corte (leer A antes que B)? |
| C6 | Selectores | Con varias entradas que cambian a la vez, ¿cuántas veces ejecuta? |
| C7 | Diamantes | ¿Puede una regla ver una mezcla de valores viejos y nuevos? |
| C8 | Diamantes | Si se pide primero la hoja o la raíz, ¿cambia el número de ejecuciones? |
| C9 | Vida | Si se invalida el subgrafo durante una regla, ¿termina o falla? |
| C10 | Vida | ¿Qué ocurre al leer un atributo ya borrado? |
| C11 | Escrituras | ¿Escribir el mismo valor propaga algo? |
| C12 | Escrituras | Dentro de una regla, ¿se permite escribir? |
| C13 | Ciclos | ¿Un ciclo falla, se corta o se queda colgado? |

**Límites:** lo observado vale para el runtime y chip medidos (macOS 15.7.9, M1) y puede cambiar con otra versión.
