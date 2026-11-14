# Prototipo aislado de M4: reglas reanudables

Fecha: 2026-11-14. Experimento de la [propuesta de M4](../../docs/DISENO-M4.md), autorizado por el dueño para explorar
la API. **No sustituye el motor ni completa M4.** El paquete principal no depende de este módulo. El único paquete
que usa el experimento es el motor local (`../..`), exclusivamente desde los benchmarks de comparación.

**Actualización:** [perfil y optimización](PERFIL.md): el caso caliente baja a **76,17 ms**, frente a **33,20 ms** del
motor actual (**2,29×**). Pasan 24 pruebas. Windows queda aplazado hasta completar el motor en Mac.

## Qué demuestra

Una regla devuelve `.needsInput` cuando necesita un atributo sucio. Su método ya ha retornado cuando el bucle del
motor apila la dependencia; después se reanuda en el mismo hilo. El estado del paso queda en las propiedades de la
regla y el valor propuesto en una evaluación que vive hasta `.finished`.

- Las cadenas frías de 20.000 y 100.000 reglas se leen directamente desde el último nodo, sin precalentarlas.
- Una cadena fría de 100.000 también pasa en un hilo al que se solicita una pila de 512 KB. Cada paso comprueba la
  identidad del hilo original y la profundidad máxima de llamadas simultáneas de reglas es 1.
- Las reglas con estado conservan el valor anterior, las escrituras propuestas durante una suspensión y su estado
  propio; no escribir mantiene la versión y corta las ejecuciones posteriores.
- Los cambios de rama podan dependencias; las lecturas repetidas no duplican aristas; `.ready(nil)` es un valor.
- Un modelo independiente de demanda y un recálculo completo verifican valores, ejecuciones, versiones y aristas
  en 12 semillas × 100 operaciones sobre DAG con lecturas condicionales.
- Las reglas y su estado se liberan con un dueño plano, también en una cadena de 20.000. La autoinvalidación espera
  hasta copiar el resultado de la lectura externa.
- El contexto usa una referencia débil al grafo y un identificador de paso. Guardarlo y usarlo después de su paso
  produce un error controlado. No retiene el grafo ni usa una referencia `unowned(unsafe)`.

`resume` puede entrar varias veces por evaluación. Los efectos que deban ocurrir una vez deben guardarse por fase o
protegerse con `isFirstStep`; la API no convierte automáticamente un cierre síncrono ni conserva sus locales.

## Cómo reproducirlo

Desde la raíz del repositorio, con Swift 6.2 o posterior:

```bash
swift test --package-path Prototypes/ResumableGraph
swift test --package-path Prototypes/ResumableGraph -c release -Xswiftc -enable-testing --skip Performance
swift test --package-path Prototypes/ResumableGraph -c release -Xswiftc -enable-testing --filter Performance
```

En este Mac, `swift` por omisión es 6.1.2; se usó Swift 6.2.4 de Xcode. Se puede seleccionar para cada orden sin
modificar la configuración global:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --package-path Prototypes/ResumableGraph
```

Foundation y Dispatch aparecen solo en el test que crea y espera al hilo de pila pequeña. El módulo del prototipo
usa la biblioteca estándar y una función nativa de identidad de hilo aislada en `ThreadIdentity.swift`.

## Validación realizada

- Tests primero: la compilación de las primeras ocho pruebas falló por la API aún inexistente; después se implementó
  el módulo y se amplió la especificación. No se presenta ese rojo como una mutación de comportamiento del motor.
- Resultado tras optimizar: **24 pruebas en depuración**; en release, **21 funcionales y 3 de rendimiento**, ejecutadas por
  separado para medir sin las otras suites. Sin problemas conocidos ni errores en el prototipo.
- Mutación comprobada: quitar la comparación del identificador de paso permitió reutilizar un contexto anterior;
  `aContextFromThePreviousStepCannotBeReused` falló. Se restauró la protección y la batería volvió a pasar.

## Medidas iniciales en release (antes del perfil)

Mac M1, Swift 6.2.4. Medianas de 5 muestras para cadenas y lecturas; 7 para ciclos calientes. Se ejecutó la suite de
rendimiento sola. Las aserciones quedan fuera del intervalo medido; las comprobaciones del motor siguen activas.

| Caso | Prototipo | Motor actual |
|---|---:|---:|
| Primera lectura de una cadena fría de 20.000 reglas, sin incluir creación | 32,62 ms | No se mide: la cadena fría desborda el motor actual |
| Ídem, 100.000 reglas | 164,75 ms | No se mide |
| 50 ciclos × 1.000 reglas con estado de 2 entradas, sin incluir creación ni precalentamiento | 109,66 ms | 33,26 ms |
| 1.000.000 de lecturas limpias de una regla | 116,50 ms | No se midió en esta suite |

Los elementos reservados para los marcos ocupan **1.048.520 bytes** en la cadena de 20.000 y **4.194.240 bytes** en la
de 100.000, según `Array.capacity × MemoryLayout<Frame>.stride`. Esto **no es memoria total**: excluye nodos, reglas,
evaluaciones, diccionarios, conjuntos, valores y sobrecoste del asignador.

El caso caliente es **3,30×** más lento que el motor actual. Ambas cargas leen las mismas dos entradas, consultan
`hasChanged` y publican el mismo resultado, pero las implementaciones no aíslan una sola variable: el prototipo usa
clases, diccionarios y conjuntos, y comprueba hilo, tipo y vigencia también en release; el motor actual usa tablas y
resuelve comparadores al crear atributos. La cifra no mide únicamente el precio de reanudar. Tampoco compara con
SwiftUI ni con AttributeGraph de Apple. **No hay evidencia todavía de rendimiento cercano al nativo.**

## Límites y siguiente decisión técnica

- Solo comparación `Equatable`: no están las políticas de M2 ni su resolución por tipo.
- Dueños planos: no están la jerarquía, los avisos ni toda la reentrada e invalidación de M5.
- No se reutilizan ranuras de nodos o dueños; las tablas crecen con el histórico. El prototipo valida liberación de
  objetos y nodos vivos, no un almacén adecuado para producción ni memoria estable bajo altas y bajas ilimitadas.
- Se exige `poll` dentro de las reglas; `Graph.value` anidado no se permite. No hay conversión ni migración de las
  APIs síncronas actuales. Los tipos son internos al experimento.
- No se ha compilado ni ejecutado en Windows. La rama de identidad de hilo está escrita, pero no verificada allí.
- Las medidas son medianas de este Mac, sin análisis de percentiles ni perfil de asignaciones. No representan una
  UI real ni permiten asegurar el presupuesto de un fotograma.

La viabilidad funcional del bucle está demostrada en los casos descritos. El [perfil posterior](PERFIL.md) identifica
costes y reduce la carga caliente, pero antes de integrar hay que contrastar con el almacén real y diseñar la
convivencia con las reglas síncronas. M4 sigue pendiente de integración y validación completa de M2 y M5 en Mac.
Windows se validará después de completar el motor en Mac.
