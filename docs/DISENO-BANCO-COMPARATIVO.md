# Diseño del banco comparativo: ¿es de alto rendimiento el motor? (borrador, pendiente de aprobación)

Fecha: 2026-11-14. Parte de [INFORME-RENDIMIENTO.md](INFORME-RENDIMIENTO.md) §6 («Lo que este informe no prueba») y de la
decisión del dueño de verificar el motor en el Mac. **Estado: propuesta. No se escribe ni se ejecuta nada hasta que el dueño
la apruebe.**

## 1. Qué hay que demostrar

Hoy solo se compara el motor consigo mismo y con cargas sintéticas. Para afirmar «alto rendimiento» faltan tres cosas:
1. un **caso de UI realista** (el de `DISENO-M0.md` §7: unas 1.000 filas con 5–10 atributos cada una, un subgrafo por fila);
2. una **referencia externa** medida en la misma máquina;
3. **percentiles y memoria** con muestras suficientes.

## 2. Qué referencias son posibles aquí (comprobado en solo lectura)

| Referencia | ¿Viable en este Mac? | Notas |
|---|---|---|
| **SwiftUI real** (macOS 15.7.9) | **Sí** | Ya se usa como oráculo de paridad (`parity/`). Mide la latencia extremo a extremo: mutación → último `body` ejecutado. Incluye el planificador de SwiftUI y el diferencial; **no aísla el coste del grafo**, es una cota superior |
| **Compute** (`jcmosc/Compute`, MIT) | **No ahora** | Su `Package.swift` pide `swift-tools-version: 6.3` y este Mac tiene **Swift 6.2.4** (Xcode). Además necesita descargar `swift-algorithms`, `Semaphore`, `swift-sexp` y el submódulo `swift-runtime-headers` (rama `release/6.3`). Habría que instalar una cadena 6.3: no se ha comprobado su tamaño |
| **AttributeGraph de Apple** directamente | No recomendada | Es un framework privado; llamarlo exigiría declarar su ABI a mano y es frágil. SwiftUI ya lo usa por debajo |
| Motores de otros lenguajes (Salsa, Preact Signals) | No | No son comparables en este entorno |

Con lo disponible, la comparación útil es **motor frente a SwiftUI real**, más la **serie histórica propia** (cada pieza medida
contra su estado anterior). Compute queda como ampliación si el dueño autoriza instalar la cadena 6.3.

## 3. Principio de la comparación (y su límite)

SwiftUI y el motor **no hacen el mismo trabajo**: SwiftUI además diferencia, hace layout y planifica. Por eso:
- Se mide el **mismo escenario lógico**: cuántos `body` deben ejecutarse tras unas mutaciones, y que **el número de `body` ejecutados
  coincida** con el de SwiftUI (es el criterio de paridad que ya tenemos; si no coincide, la comparación de tiempo no vale).
- Los `body` hacen un trabajo trivial e idéntico (una operación aritmética y una cadena corta).
- Se informa de dos cosas separadas: la **latencia total de SwiftUI** (cota superior) y la del **motor** (su coste real). La
  pregunta que se responde es si el motor consume una **fracción pequeña del presupuesto de un fotograma** (16,6 ms a 60 Hz;
  8,3 ms a 120 Hz), no si «es más rápido que SwiftUI».

## 4. Escenarios (mismos en las dos implementaciones)

| # | Escenario | Qué mide |
|---|---|---|
| S1 | 1.000 filas, 5–10 atributos cada una, un subgrafo por fila; en cada fotograma se cambia el estado de k filas (k = 1, 10, 50, 100) | latencia por fotograma; cuántos `body` corren (deben ser k) |
| S2 | Valor de entorno leído por N vistas (N = 100, 1.000, 10.000), de las que solo la mitad lo lee; se cambia el valor | fan-out y que no corran las que no lo leen |
| S3 | `ForEach` de 1.000 filas: añadir una al principio, quitar una del medio, reordenar | coste de altas, bajas y de no ejecutar nada al reordenar |
| S4 | Jerarquía profunda (50 y 200 niveles) con un valor que se propaga hacia abajo y se muta en la raíz | propagación en cadena |
| S5 | Cambio de rama con 100 hijos con estado, de ida y vuelta | creación y destrucción de subgrafos |
| S6 | Arranque: construir y evaluar por primera vez S1 | coste en frío |

## 5. Métricas y método

- **Latencia por fotograma:** mediana, p95 y p99 de **≥ 1.000 fotogramas** por escenario (hoy son 60: el p99 es el máximo), en
  **≥ 5 ejecuciones** de proceso, alternando el orden entre SwiftUI y el motor. Se descartan los 50 primeros fotogramas.
- **Cómo se mide en SwiftUI:** `NSHostingView` en una ventana fuera de pantalla (como en `parity/Compare`); las mutaciones se hacen en
  el hilo principal; el tiempo va de justo antes de mutar a la marca de tiempo del **último `body`** (marcas tomadas dentro de los
  `body` con `mach_continuous_time`), no al final del `pump` del bucle de ejecución, para no medir la granularidad de la espera.
- **Memoria:** memoria residente del proceso (`task_info`) antes y después de montar S1, dividida por filas; para el motor,
  además, `Graph.estimatedMemoryFootprint` (M8, una estimación). Se registra aparte la memoria que retienen las evaluaciones reanudables.
- **Ruido:** se registra la dispersión entre ejecuciones; diferencias menores que ella no se interpretan.
- **Dónde vive el código:** un paquete local `parity/Bench` que depende del motor por ruta (como `parity/Compare`), con ambas
  implementaciones en el mismo proceso. `parity/` no se versiona; los resultados resumidos se copian a `docs/`.

## 6. Criterios de aceptación (se fijan antes de medir)

1. **Paridad:** en S1–S5 el número de `body` ejecutados por el motor coincide con el de SwiftUI en cada paso.
2. **Presupuesto del motor:** p99 del motor **≤ 1,6 ms** (10 % de 16,6 ms) en S1 con k = 50 (5 % de las filas) y en S2 con N = 1.000.
3. **Sin sorpresas de escala:** S1 y S2 crecen **casi linealmente** con k y N (se comprueba con la pendiente, no con un umbral).
4. **Memoria:** el valor medido por fila se registra; **el umbral se fija tras la primera medida** (no se inventa uno ahora).
5. **Sin regresión:** las cifras de las piezas anteriores no empeoran más del ≈ 10 % (serie histórica del plan).

Si algo no cumple, se informa tal cual y se decide si se optimiza (midiendo antes) o se acepta el límite.

## 7. Riesgos y límites

- **SwiftUI es una caja negra:** su latencia incluye planificación y no se puede separar el coste del grafo. La comparación es de
  orden de magnitud, no de eficiencia relativa del algoritmo.
- **Ventana fuera de pantalla:** SwiftUI puede comportarse distinto sin renderizar; ya se midió así en las rondas de paridad, y el
  `body` se ejecuta igual.
- **Una sola máquina y versión (M1, macOS 15.7.9).** No se extrapola a Windows ni a otros chips.
- **Modelo de UI simplificado:** las «filas» del motor son subgrafos con reglas, escritas a mano; no pasan por una capa de vistas.
  Un número bueno aquí no garantiza el de una UI real, pero uno malo sí sería una alarma.
- **Compute:** sin instalar la cadena 6.3 no hay referencia de motor; se pospone y se anota.

## 8. Orden de trabajo

1. Escribir el banco en `parity/Bench` con S1 en las dos implementaciones, y comprobar la **paridad de cuentas de `body`**.
2. Medir S1 (k = 1, 10, 50, 100) con ≥ 1.000 fotogramas × 5 ejecuciones; informe breve.
3. Añadir S2–S6, con su informe.
4. Contrastar con los criterios de §6 y escribir los resultados en `INFORME-RENDIMIENTO.md` (una sección nueva, con las
   salvedades) y en `PLAN-MOTOR.md`.
5. Un commit con el informe; el código de `parity/` no se versiona.

## 9. Preguntas para el dueño

1. ¿Aceptas «motor frente a SwiftUI real» como referencia principal y dejar Compute para una segunda fase?
2. ¿Autorizas, si se quisiera Compute, **descargar e instalar una cadena de Swift 6.3** (tamaño por comprobar)? Es un cambio en
   tu equipo; no lo haría sin tu confirmación.
3. ¿El objetivo es 60 Hz (16,6 ms) o 120 Hz (8,3 ms)? Cambia el presupuesto: 1,6 ms es el 10 % de 16,6 ms; para 120 Hz serían 0,8 ms.
4. ¿Los criterios de §6 son los que quieres, o hay otros umbrales que ya tienes en mente?
