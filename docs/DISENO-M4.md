# Diseño M4: evaluación reanudable en el hilo del grafo (propuesta revisada)

Fecha: 2026-11-14. Sustituye la propuesta de segmentos mediante hilos auxiliares del commit `1e6f041`.
**Estado: prototipo aislado autorizado y validado en Mac; integración pendiente.** Resultados y órdenes en
[Prototypes/ResumableGraph](../Prototypes/ResumableGraph/README.md). M4 sigue pendiente. La implementación de producción conserva el
contrato actual hasta decidir la migración de API descrita en §6. No se cambian los principios de `AGENTS.md`.

## 1. Problema y garantías que se conservan

M0 actualiza las dependencias conocidas mediante una pila explícita (`UpdateFrame`). Una lectura de una regla sucia
que aparece por primera vez dentro de un cierre llama a `update` desde ese cierre: usa la pila nativa según la
profundidad de los datos. M3 y M5 no eliminan esa limitación.

Se conservan estas garantías:
- El grafo y el código de sus reglas se ejecutan en el hilo que creó el grafo.
- La profundidad del grafo no determina la profundidad de la pila nativa del motor.
- Las reglas se evalúan de forma perezosa, con dependencias exactas y corte por versiones.
- El motor no repite efectos ya realizados para descubrir una dependencia.
- Los nodos, el estado de las reglas y su evaluación pendiente tienen dueño y se liberan con él.

Un cierre síncrono opaco no ofrece al motor un punto donde devolver el control y conservar automáticamente sus
variables locales. Mantener a la vez los cierres actuales sin cambios, lecturas dinámicas ilimitadas y estas garantías
no está resuelto. Esta propuesta cambia la expresión de las reglas que necesitan suspenderse; no afirma haber
resuelto el caso original sin cambiar la API.

## 2. Por qué se retira la propuesta de hilos auxiliares

La nota anterior proponía cambiar de hilo cuando quedara poca pila y bloquear el hilo original hasta terminar.
Eso deja un solo hilo ejecutando el grafo a la vez, pero no conserva la afinidad: el código del usuario cambia de
hilo según la profundidad. Una regla que necesite al hilo original puede bloquearse si ese hilo espera al auxiliar;
las comprobaciones del hilo principal y el almacenamiento por hilo del usuario también cambian de comportamiento.
Además, la recursión nativa continúa y se añaden recursos por segmento. Superar una prueba de profundidad no elimina
esas diferencias de semántica.

Por tanto, no se presta `owningThread`, no se añade `StackSegment.swift` y no se reformulan los principios 1 y 6 para
acomodar esta solución. Los resultados del prototipo anterior siguen en el historial de Git; no son resultados de
M4 ni una prueba de portabilidad a Windows.

## 3. Alternativa recomendada: devolver una petición y reanudar

Una regla reanudable ejecuta un paso y devuelve uno de dos resultados:
1. necesita una entrada; el motor la actualiza con la pila explícita;
2. terminó; el motor publica el resultado aplicando la comparación y la poda habituales.

El método del paso ya ha retornado cuando se apila una dependencia. No queda un cierre de usuario bloqueado en la
pila nativa ni se requiere otro hilo. La regla conserva en sus propiedades la fase y los valores locales necesarios.
No se reinicia desde el principio para descubrir lecturas.

**Boceto de API, no disponible todavía:**

```swift
/// The next action requested by a resumable rule.
public enum RuleStep {
    case needsInput(AnyAttribute)
    case finished
}

/// A read that either has a value or must yield to the graph's update loop.
public enum ReadResult<Value> {
    case ready(Value)
    case pending
}

/// A rule that yields before reading an input that needs an update.
public protocol ResumableRule {
    associatedtype Value
    static var initialValue: Value? { get }
    mutating func resume(_ context: inout RuleContext<Value>) -> RuleStep
}
```

Se añadirían `RuleContext.poll(_:) -> ReadResult<T>` y `isFirstStep`, y
`Graph.makeResumableRule(_:comparison:)`. `poll` nunca llama recursivamente a `update`: devuelve `.pending` si la
entrada necesita actualización. `.ready(nil)` se distingue de `.pending` cuando el valor del atributo es opcional.

Ejemplo de una regla cuyo segundo atributo depende del valor del primero (esquema; los nombres son propuestos):

```swift
struct Choose: ResumableRule {
    let selector: Attribute<Bool>
    let left: Attribute<Int>
    let right: Attribute<Int>
    var selected: Attribute<Int>?

    mutating func resume(_ context: inout RuleContext<Int>) -> RuleStep {
        if context.isFirstStep { selected = nil }
        if selected == nil {
            switch context.poll(selector) {
            case .pending: return .needsInput(selector.erased)
            case .ready(let flag): selected = flag ? left : right
            }
        }
        let source = selected!
        switch context.poll(source) {
        case .pending: return .needsInput(source.erased)
        case .ready(let value):
            context.value = value
            return .finished
        }
    }
}
```

Aquí no se vuelve a consultar el selector tras haberlo consumido: la elección queda en `selected`. Los efectos que
deban ocurrir una vez se asocian a una fase guardada, no a cada entrada a `resume`. El método puede llamarse varias
veces en una evaluación; no se debe equiparar ese número con las ejecuciones completas de una regla de M0.

## 4. Integración que debe probar el prototipo

- **Marcos:** guardar nodo, fase del motor, cursor de rastreo y petición pendiente. El bucle alterna verificación,
  paso de regla, actualización de la fuente pedida y reanudación. La pila explícita contiene toda la profundidad.
- **Lecturas:** `.needsInput` expresa una lectura. Tras actualizar la fuente, el motor registra su versión y la
  dependencia en ese punto; un `poll` posterior de la misma fuente no duplica la arista. El orden es el de las
  peticiones y lecturas, no el de creación de nodos. Se comprueban ID vivo y ciclos antes de apilar.
- **Rastreo:** preparar las aristas viejas una vez por evaluación; conservar el cursor entre pasos y podar solo al
  finalizar. No reiniciar el rastreo ni publicar versiones entre pasos.
- **Estado:** conservar el valor propuesto y `wasWritten` entre pasos. Al finalizar, no escribir conserva el valor y
  la versión, como M3; escribir aplica M2. La primera evaluación sin valor inicial debe producir uno.
- **Consultas de cambio:** verificar las entradas anteriores y fijar la instantánea de `changed` antes del primer
  paso, como M3. Debe definirse y probarse el coste frente a las reglas normales y con estado existentes.
- **Contexto:** instalar y restaurar el grafo, el nodo, el cursor y el dueño alrededor de cada paso. El contexto no
  puede usarse fuera de su paso ni de otra evaluación: hay que impedirlo o comprobar su vigencia con un error
  controlado. No trasladar una referencia `unowned(unsafe)` escapable al nuevo camino sin protección.
- **M5:** conservar las invalidaciones diferidas mientras haya marcos activos. Copiar el resultado de la lectura
  externa antes de liberar su dueño, incluso si se invalidó a sí mismo. Usar los límites de conjunto corregidos de M5.
- **Memoria:** los marcos pertenecen a la actualización del grafo y el estado persistente al nodo; no hay hilos,
  continuaciones globales ni nodos persistentes auxiliares sin dueño.

## 5. Opciones y alcance

| Opción | Qué permite | Qué falta o cambia |
|---|---|---|
| Regla reanudable por pasos (recomendada para prototipo) | Pila explícita, hilo original, API externa de lectura síncrona | Adaptar las reglas que esperan otras reglas; expresar las fases |
| Declarar entradas antes del cálculo | Actualizar lo conocido antes de llamar al cierre | No cubre por sí sola una dependencia elegida dinámicamente |
| API `async` con suspensión del lenguaje | Conservar locales entre suspensiones | Cambia la API; requiere diseñar ejecución en el hilo original y medirla, no basta con usar `Task` |
| Corrutinas o fibras de plataforma | Investigar si permiten conservar el cierre síncrono | Requieren validar ABI, runtime de Swift y portabilidad; no se proponen como implementación probada |
| Hilos auxiliares o reintentos del cierre | Prototipos anteriores | No se recomiendan: cambian afinidad o repiten efectos |

La inexistencia de una función importada directamente en Swift no demuestra que todas las alternativas de corrutinas
sean imposibles. Tampoco se ha verificado una que cumpla las restricciones del paquete. No se añade C ni ensamblador
como si ya estuvieran autorizados por el requisito de Swift puro.

## 6. Compatibilidad y decisión pendiente

Las APIs actuales (`Rule`, `StatefulRule`, `makeRule` con cierre y `Attribute.value`) no desaparecen por escribir esta
nota. Hoy siguen teniendo el límite documentado de lecturas dinámicas profundas.

**El cambio de contrato propuesto debe ser explícito:** las reglas capaces de pedir entradas sucias durante su cálculo
usarían la API reanudable. En un cierre síncrono ordinario, una lectura que necesite anidar una actualización debería
rechazarse antes de anidar, con un error que indique la API requerida. No basta con introducir la nueva API y dejar el
camino antiguo desbordando la pila. La compatibilidad, migración y posible deprecación son parte de M4.

El motor podría mantener `Graph.value(of:)` síncrono para el llamador externo: el bucle termina toda la actualización
antes de devolver. Lo que cambia es cómo la regla entrega una petición durante el cálculo.

Para la futura UI hay que comprobar que las reglas internas pueden expresarse por etapas. Esta propuesta no convierte
automáticamente un `body` arbitrario ni todas sus lecturas implícitas en una máquina de estados. Si conservar esa
sintaxis en cualquier profundidad es un requisito, sigue abierta la investigación de otra estrategia.

**Decisión del dueño (2026-11-14):** aprobada la exploración de esta API mediante un prototipo aislado. No equivale a
aprobar la sustitución de las APIs de producción ni su migración. El prototipo está en
`Prototypes/ResumableGraph`; antes de integrar se debe resolver el coste caliente y concretar la convivencia de APIs.

## 7. Validación y criterio de terminado

Primero un prototipo aislado, sin sustituir el motor; después, si se acepta la dirección, TDD sobre la integración:

1. Cadenas de 20.000 y 100.000 reglas nunca evaluadas, incluidas reglas con estado; lectura final directa, sin
   precalentar nodo a nodo. Mismo hilo en todos los pasos, también desde un hilo con pila de 512 KB.
2. Selección condicional de nuevas fuentes, poda, lecturas repetidas y valores opcionales: oráculos de valores,
   dependencias, versiones y efectos ejecutados una sola vez por fase.
3. Ciclos, reentrada y contexto fuera de vigencia: errores controlados; ninguna dependencia provoca recursión nativa.
4. M3: valor anterior, escritura omitida y comparación; M5: autoinvalidación, avisos y varios conjuntos diferidos
   relacionados. `nodeCount` y subgrafos vivos vuelven a la base; no quedan marcos al terminar.
5. Migrar los casos existentes que dependen de lecturas síncronas anidadas. Probar el comportamiento documentado de
   ambas APIs; no presentar una caída evitada mediante rechazo como compatibilidad transparente.
6. Batería en depuración y release. Medir evaluación inicial profunda, actualización caliente, lecturas limpias y
   memoria de los marcos. Comparar con la base anterior de este Mac; fijar umbrales después del prototipo.
7. Compilar y ejecutar los casos de profundidad y afinidad en Windows ARM64 antes de afirmar portabilidad verificada.

**Prioridad del dueño (2026-11-14):** primero completar el motor en Mac. El punto 7 queda para la etapa posterior;
no se trabaja en Windows ahora ni se exige esa validación para cerrar M4 en Mac.

## 8. Resultado del prototipo aislado

Mac M1, Swift 6.2.4: 21 pruebas de depuración; 18 funcionales y 3 de rendimiento en release. Pasan cadenas frías de
20.000 y 100.000 reglas, 100.000 en un hilo con pila solicitada de 512 KB, 20.000 reglas con estado, poda condicional,
oráculo de 12 semillas × 100 operaciones, corte por igualdad, vida del dueño, autoinvalidación y protección del contexto.
Cada paso comprueba el hilo original; la profundidad máxima de pasos simultáneos es 1.

Medianas release: cadena fría de 20.000, **32,62 ms**; de 100.000, **164,75 ms** (solo evaluación). En 50 ciclos de
1.000 reglas con estado y dos entradas: prototipo **109,66 ms**, motor actual **33,26 ms** (sin creación). El coste
caliente es **3,30×**: aún no satisface un objetivo de integración de alto rendimiento y no aísla el coste de la API.
Detalle de la comparación, memoria parcial y límites en el [README del prototipo](../Prototypes/ResumableGraph/README.md).

**Perfil y optimización posteriores:** [informe](../Prototypes/ResumableGraph/PERFIL.md). 24 pruebas en verde; el caso
caliente baja de 111,99 ms (base repetida de la sesión) a **76,17 ms**, frente a **33,20 ms** del motor actual:
aproximadamente **32 %** menos, todavía **2,29×**. Se reutilizan evaluaciones y buffers y se especializan operaciones
del contexto entre módulos, conservando comprobaciones. La carga caliente no suspende; la diferencia restante no
puede atribuirse al acto de suspender. La memoria retenida por regla aumenta y aún no se ha cuantificado en total.

**No verificado:** integración con el motor, políticas de M2, M5 completo, migración de APIs, perfil de asignaciones,
percentiles, cargas reales de UI y Windows. El prototipo usa `Equatable`, dueños planos y no reutiliza ranuras.
Los estudios externos enumerados en `AGENTS.md` §5 no están disponibles en las rutas locales consultadas; esta revisión
parte del código y los diseños de este repositorio. Deben contrastarse antes de cerrar el diseño de implementación.
