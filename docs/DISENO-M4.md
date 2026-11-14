# Diseño M4: actualización sin desbordar la pila (borrador, pendiente de aprobación)

Fecha: 2026-11-14. Parte de [PLAN-MOTOR.md](PLAN-MOTOR.md) §3 (M4) y §6 («Límites»: «la primera ejecución de una regla
que lee otra regla **nunca ejecutada** anida en la pila nativa»). **Estado: propuesta. No se implementa nada hasta que el
dueño la apruebe.** Incluye una medida del límite actual y un prototipo descartable de la solución propuesta.

## 1. Qué hay hoy y qué dice el plan

M0 recorre las entradas **ya conocidas** de una regla con una pila explícita (`UpdateFrame`): una cadena de 20.000 reglas
ya ejecutadas se actualiza sin recursión. Lo que no puede evitar es la **lectura dinámica**: el cierre de una regla llama a
`Attribute.value` y, si ese atributo está sucio (o nunca se ejecutó), `read` llama a `update` **dentro del cierre**, en la
pila nativa. Una cadena de reglas que se leen por primera vez unas a otras anida un nivel nativo por regla.

El plan pide: «las lecturas dinámicas dentro de una regla tampoco usan la pila nativa; reentrada (actualización
anidada)», con criterio «cadena de 20.000 lecturas dinámicas no declaradas sin desbordar; test de reentrada».

## 2. Medida del límite actual (este Mac, M1, Swift 6.2.4)

Cadena de N reglas nunca ejecutadas, cada una lee la anterior dentro de su cierre; se lee la última
(`graph.value(of: last)`), un ejecutable aparte con los fuentes del motor.

| Configuración | Hilo principal (8 MB) | Hilo secundario (512 KB) |
|---|---|---|
| `-O` | 5.000 pasa; **10.000 se cae** (≈ 1 KB por nivel) | **1.000 se cae** |
| `-Onone` (depuración) | 1.000 pasa; **2.000 se cae** (≈ 4 KB por nivel) | 1.000 se cae |

La profundidad útil hoy es de **unos cientos de niveles en un hilo secundario y unos miles en el principal**, muy por
debajo de los 20.000 del principio 1. Una UI real anida pocos niveles (la profundidad de la jerarquía de vistas), pero el
motor no puede dejar un desbordamiento posible en función de los datos.

## 3. Opciones

| # | Opción | ¿Quita la anidación nativa? | Coste y riesgos |
|---|---|---|---|
| 1 | **Segmentos de pila: continuar la lectura anidada en un hilo auxiliar con pila grande cuando queda poca pila** (propuesta) | No: la recursión sigue, **pero sin tope de profundidad** | Un hilo auxiliar por segmento (≈ 15–25 µs, medido); el código del usuario que corre dentro de un segmento está en **otro hilo** (afinidad de hilo, `@MainActor`); Windows sin verificar |
| 2 | Corrutinas (`makecontext`/`swapcontext`, fibras de Windows) | Sí | **`getcontext` no se puede llamar desde Swift en macOS** (medido: «cannot find 'getcontext' in scope»); haría falta un módulo C, y el paquete es Swift puro |
| 3 | Que las reglas declaren sus entradas por adelantado | Solo para reglas que las declaren | Cambia la API y, por definición, no cubre la lectura dinámica |
| 4 | Abortar la regla en la primera lectura sucia y reintentarla | Sí | Swift no puede desenrollar un cierre sin `throws`; y la regla correría dos veces (los contadores y los efectos de los tests cambiarían). Descartada |
| 5 | No hacer nada y documentar | No | Falla a 2.000–10.000 niveles |

**Honestidad sobre el plan:** una regla es un cierre opaco de Swift; sin corrutinas (opción 2, no disponible) o sin
reintentos (opción 4, descartada) **no se puede suspender en mitad de su ejecución**, así que la frase «tampoco usan la pila
nativa» no se puede cumplir al pie de la letra. Lo que sí se puede es cumplir el criterio («sin desbordar»). La opción 1 lo
consigue para cualquier profundidad que quepa en memoria. Se propone **reformular M4** en el plan como «sin desbordar la pila»
y dejar escrito que la recursión nativa de las lecturas dinámicas se mantiene.

## 4. Prototipo de la opción 1 (descartable, en el directorio temporal; no está en el repositorio)

Se cambió `read` para que, en una lectura anidada, cuente la profundidad y a los 300 niveles continúe `update` en un hilo
auxiliar (`pthread_create` con 256 MB de pila reservada y `pthread_join`). Cadena de N reglas nunca ejecutadas:

| N | Hilos auxiliares | `-O` | `-Onone` |
|---|---|---|---|
| 1.000 | 3 | 1,1 ms | 3,3 ms |
| 20.000 | 66 | 43 ms | 85 ms |
| 100.000 | 333 | 203 ms | 883 ms |
| 1.000.000 | 3.333 | 1.514 ms | 3.945 ms |

Todas dan el valor correcto. Para comparar: crear y ejecutar por primera vez 20.000 reglas sin anidar cuesta ≈ 16 ms
(0,8 µs por regla), así que anidar a 20.000 niveles cuesta ≈ 2,7× más: el coste es de los hilos y de tocar pila nueva, y solo
se paga en el caso patológico. Hallazgos del prototipo que condicionan el diseño:
1. La instalación del grafo en el almacenamiento por hilo (`ThreadLocalGraph.install`) ya se hace en cada `run`, así que el
   hilo auxiliar lo recibe sin cambios.
2. La comprobación de hilo de depuración (`assertOwnThread`) falla en el auxiliar: hay que **prestarle el «dueño»** mientras dure
   el segmento (el hilo que llama está bloqueado en `pthread_join`: sigue habiendo un solo hilo ejecutando el grafo).
3. Contar niveles es un criterio malo: 300 niveles caben en un hilo de 8 MB y no en uno de 512 KB en depuración (≈ 1,2 MB).
   El criterio correcto es **la pila que queda** (§5).

## 5. Diseño propuesto

**Cuándo cambiar de segmento.** En `read`, solo cuando hay una lectura anidada (`evaluatingNode != noNode`) de un atributo
sucio, se compara la dirección de una variable local (aproximación del puntero de pila) con un **límite por hilo**
(`stackLimit`), calculado una vez por hilo/segmento: base de la pila del hilo menos su tamaño más un **margen** (propuesta:
256 KB, para el código del usuario que corra entre dos lecturas). Si la dirección está por debajo del límite, `update`
continúa en un segmento nuevo. Coste en el caso normal: una comparación por lectura anidada sucia.
- Darwin: `pthread_get_stackaddr_np` / `pthread_get_stacksize_np`; Linux: `pthread_getattr_np`; Windows:
  `GetCurrentThreadStackLimits`. Todo en un archivo aislado nuevo, `Tracking/StackSegment.swift`, como `ThreadLocalGraph.swift`.

**El segmento.** `runOnFreshStack(_ body:)` crea un hilo con una pila de **64 MB reservados** (la memoria se compromete al
tocarla; medido: crear y esperar un hilo cuesta 14–24 µs sea cual sea la reserva), le pasa el cierre por una caja con
`Unmanaged` (sin pasar por la comprobación de `Sendable`), espera con `join`, y devuelve. Dentro, se instala el límite del
segmento y se presta el dueño del grafo; al volver se restauran. Un fallo de `precondition` dentro del segmento termina el
proceso como en cualquier hilo.

**Reentrada (la otra mitad de M4).** Se fija y se prueba lo que ya funciona y lo que debe seguir funcionando: una regla que
llama a `graph.value(of:)` para otro atributo sucio; un aviso (de atributo o de subgrafo) que lee o escribe y dispara
actualizaciones; ciclos descubiertos a través de una lectura anidada (siguen siendo `precondition`); una invalidación
diferida que termina cuando acaba la actualización **más externa** aunque haya segmentos de por medio.

**Cambios en el motor.** (1) `StackSegment.swift` (límite de pila, segmento, plataformas); (2) `Graph.read`: la
comprobación en la ruta anidada y sucia; (3) `Graph.owningThread` pasa a variable para prestarse en el segmento; (4) contador
interno `stackSegmentCount` (introspección y pruebas).

## 6. Tests (primero; deben fallar antes de implementar)

- **Profundidad (principio 1):** cadena de 20.000 y de 100.000 reglas nunca ejecutadas, cada una lee la anterior dentro de su
  cierre: (a) en el hilo del test, (b) en un hilo con 512 KB de pila, (c) en depuración y en release. Valores correctos y
  `stackSegmentCount > 0` donde corresponda. Árbol binario profundo de lecturas dinámicas. Una cadena de 20.000 de reglas
  **con estado** que leen dinámicamente.
- **Sin coste en lo normal:** una cadena corta (100 niveles) no crea ningún segmento (`stackSegmentCount == 0`).
- **Reentrada:** las del §5; que `nodeCount` vuelve a la base; que un `precondition` (ciclo) dentro de un segmento termina el
  proceso (`processExitsWith`).
- **Hilos:** dentro de un segmento, `ThreadLocalGraph.current()` es el grafo y se puede crear atributos (la comprobación de
  hilo de depuración no falla); tras volver, el dueño es el original.
- **Rendimiento (release):** los de M0 a M5 sin cambio (criterio ≈ 2 %: es una comparación en una ruta rara); nuevo:
  20.000 niveles anidados (esperado ≈ 40 ms) y el coste de un segmento.

## 7. Orden de trabajo

1. Tests rojos. 2. `StackSegment.swift` y las pruebas de pila. 3. `read` con el límite y el segmento; dueño prestado.
4. Verde en depuración y release; medidas; `PLAN-MOTOR.md` (§10). 5. Un commit.

## 8. Riesgos y límites

- **El código del usuario dentro de un segmento corre en otro hilo.** Cualquier regla que dependa de la afinidad de hilo
  (`MainActor.assumeIsolated`, almacenamiento por hilo propio, `Thread.current`, APIs que exijan el hilo principal) **fallará
  solo cuando la lectura anidada sea tan profunda que agote la pila** (cientos de niveles en un hilo secundario, miles en el
  principal). Se documenta en `Rule`, `StatefulRule` y `Graph`. La capa de vistas debe ejecutar sus `body` sin depender de
  esto, o evitar anidaciones tan profundas; no es un problema del caso normal.
- **Hilos bloqueados:** durante la anidación hay un hilo bloqueado por segmento; con 64 MB por segmento son pocos (3.333
  en el prototipo con 1.000.000 de niveles y 300 niveles por segmento; con el criterio de pila serán muchos menos).
- **Windows no está verificado** (`CreateThread` con `STACK_SIZE_PARAM_IS_A_RESERVATION`); la rama de Windows se escribe
  y se marca como no verificada.
- **Principio 6 («un solo hilo por grafo»):** se matiza a «un solo hilo **ejecutando** el grafo a la vez»: el hilo que
  llama espera mientras el segmento trabaja. Se documenta; no se permite uso concurrente.
- **No hay `async`/corrutinas reales:** si Swift ofreciera un modo de suspender cierres síncronos, se sustituiría la
  opción 1 por una solución sin hilos.

## 9. Preguntas para el dueño

1. ¿Aceptas reformular M4 como «las lecturas dinámicas anidadas no desbordan la pila, sin límite de profundidad» (sin
   prometer que dejen de usar la pila nativa)?
2. ¿Aceptas el hilo auxiliar con la afinidad de hilo como límite documentado (§8)?
3. ¿Margen de 256 KB y segmentos de 64 MB (propuestos)?
4. ¿Escribo la rama de Windows sin poder verificarla, marcada como tal?
