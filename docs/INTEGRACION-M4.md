# Integración aditiva de reglas reanudables en Mac

Fecha: 2026-11-14. Base: `db21efa`. **Decisión: conservar la candidata**, porque pasa las pruebas y los presupuestos
fijados antes de medir en [DISENO-M4.md §9](DISENO-M4.md#9-criterios-previos-de-la-integración-candidata).
**M4 sigue parcial:** los cierres síncronos existentes conservan su límite de profundidad. Windows queda aplazado.

## Qué se integra

- `ResumableRule`, `RuleStep`, `ReadResult`, `ResumableRuleContext` y `Graph.makeResumableRule(_:comparison:)`.
- El camino nuevo usa la tabla de nodos, rastreo ordenado, versiones y poda reales. Una petición de entrada vuelve
  al bucle y apila la fuente; el paso anterior ya retornó. No se crean hilos ni se reintenta un cierre opaco.
- El cursor de lectura se conserva en el marco usando `next = -cursor - 1` durante una suspensión. La fuente
  pendiente ocupa relleno del marco: **24 bytes**, igual que la base, en el Mac ARM64 medido.
- El estado común pasa de `UInt8` a `UInt16` para el bit de regla reanudable: **un byte adicional por ranura**.
  Las cajas de reglas antiguas no reciben objetos de evaluación nuevos.
- El valor propuesto y el token viven en una evaluación propiedad del nodo. Se reutiliza sin reiniciar el token;
  el valor propuesto se vacía al terminar. El grafo se referencia con `unowned` **comprobado**, no `unowned(unsafe)`:
  no se retiene su vida y el runtime rechaza el acceso después de destruirlo. Los tokens rechazan pasos antiguos.
- Los comparadores de M2 se resuelven al crear el atributo y se aplican al publicar, incluyendo la primera escritura
  contra un valor inicial. El inicial se calcula una vez, perezosamente en la primera evaluación.
- Se conserva M5: dueño actual, jerarquía, avisos antes de liberar, invalidación diferida y copia del resultado antes
  de autodestruir al dueño. Un paso de una regla cuyo dueño cae crea en el ancestro vivo, como las demás reglas.

No se modifica el contrato de `Rule`, `StatefulRule` ni sus fábricas. Una lectura síncrona limpia dentro de un paso
puede usar el camino habitual; una lectura sucia se rechaza indicando `poll` y `needsInput`. Una dependencia síncrona
antigua puede todavía anidar su propia actualización: no se presenta como resuelta la recursión de esas APIs.

## Rendimiento: criterios y resultado

Condiciones: Mac M1, macOS 15.7.9, Swift 6.2.4; release con `-enable-testing`, sin desactivar exclusividad ni usar
`-Ounchecked`. Las suites de rendimiento se ejecutan separadas. [Datos por caso y muestras](MEDIDAS-M4-INTEGRACION.txt).

**Criterio nuevo, fijado antes:** razón reanudable / síncrona **≤ 1,30** en 50 ciclos × 1.000 reglas de tipo, dos
entradas, misma consulta `hasChanged` y resultado. Ambas usan la misma política y el almacén real. Creación y
precalentamiento quedan fuera; siete muestras por ejecución, alternando qué variante se mide primero.

| Candidata | Síncrona | Reanudable | Razón | Resultado |
|---|---:|---:|---:|---|
| Primera versión | 36,16 ms | 51,53 ms | 1,425 | No aceptada |
| Contexto especializado y referencia no propietaria comprobada | 35,37 ms | 33,56 ms | 0,949 | Pasa |
| Repetición 1 | 35,21 ms | 33,01 ms | 0,938 | Pasa |
| Repetición 2 | 35,01 ms | 33,14 ms | 0,947 | Pasa |
| Repetición 3 | 35,01 ms | 33,03 ms | 0,944 | Pasa |
| Verificación final tras corregir inicialización perezosa | **35,23 ms** | **32,90 ms** | **0,934** | Pasa |

La primera candidata quedó fuera del presupuesto. La especialización entre módulos y la referencia comprobada
redujeron el coste sin quitar validación de vigencia ni introducir acceso inseguro. No se aumentó el límite tras
ver los resultados. Las cifras no prueban una ventaja general frente a las reglas síncronas, ni equivalencia de
rendimiento con AttributeGraph de Apple; solo validan esta carga y este equipo.

**Criterio de compatibilidad de rendimiento:** ninguna regresión sostenida > 10 % en caminos existentes. Se
compararon **43 métricas** de la suite de la base con la candidata; el mayor aumento observado fue **1,43 %**.
No apareció un caso > 10 % que requiriera repetición para discriminar ruido. Ejemplos:

| Caso existente | Base | Candidata |
|---|---:|---:|
| 50 ciclos de escribir y actualizar 1.000 reglas simples | 18,23 ms | 18,49 ms |
| Actualizar cadena caliente de 20.000 | 5,37 ms | 5,42 ms |
| Corte en la primera regla de 20.000 | 0,72 ms | 0,73 ms |
| Regla de 20.000 entradas pierde la mitad | 74,47 ms | 75,17 ms |

Medidas nuevas de cadena fría, cinco muestras, sin creación ni destrucción: **15,23 ms** para 20.000 reglas y
**75,55 ms** para 100.000. Se usa una regla mínima sin los contadores de la fixture del prototipo: no es una
comparación aislada con aquel. Memoria total y percentiles siguen sin medir; las evaluaciones se conservan por nodo.

## Correctitud y TDD

- Las primeras pruebas de API fallaron al compilar antes de implementarla.
- Una prueba adicional detectó que `initialValue` se calculaba al crear la regla. Se observó el rojo (una llamada
  antes de la primera lectura), se movió al inicio de la primera evaluación y se verificó el verde y la llamada única.
- Se comprobó una mutación: quitar la comparación del token permitió revivir un contexto anterior; su prueba falló.
  Se restauró la comprobación antes de la batería final.
- **169 pruebas de depuración sin rendimiento** y **168 funcionales de release** pasan. Las **14 pruebas de rendimiento
  existentes** y las **2 nuevas** pasan por separado: 184 pruebas verificadas en release. Persisten exclusivamente
  los dos problemas conocidos de comparación de M2.
- Profundidad: 20.000 y 100.000 reglas frías, 20.000 acumuladores, 20.000 entradas y 100.000 reglas en un hilo con
  pila solicitada de 512 KB. El cuerpo de cada regla de las cadenas comprueba también el hilo original en release.
- El oráculo mezcla reglas síncronas con estado y reanudables: 12 semillas × 100 operaciones. Compara valores,
  ejecuciones, versiones y aristas frente a un modelo iterativo de demanda y un recálculo completo.
- Pruebas de las cinco políticas de comparación con cero con signo y NaN, existenciales, opcionales, poda,
  conservación de propuestas, escritura omitida, contextos escapados, grafo liberado, ciclo y lectura sucia incorrecta.
- Vida y M5: estado liberado con un subgrafo de 20.000 reglas, autoinvalidación con descendientes y avisos, y
  conjuntos diferidos relacionados con lectores reanudables. Los contadores vuelven a la base.

## Reproducción

Usar Swift 6.2 o posterior; en este Mac se seleccionó Xcode por orden mediante `DEVELOPER_DIR`, sin cambiar el sistema.

```bash
swift test --skip Performance
swift test -c release -Xswiftc -enable-testing --skip Performance
swift test -c release -Xswiftc -enable-testing --filter '^SwiftAttributeGraphTests[.]PerformanceTests/'
swift test -c release -Xswiftc -enable-testing --filter ResumablePerformanceTests
```

Las dos últimas órdenes se ejecutan secuencialmente para evitar competencia entre suites. La prueba del presupuesto
se comprueba solo en release; en depuración se miden los tiempos sin aplicar ese criterio de aceptación.

## Pendiente para cerrar M4 y el motor

Definir la convivencia y migración de lecturas dinámicas de los cierres antiguos, medir memoria total y cargas más
representativas, y completar el resto del plan en Mac. Este paso conserva un camino explícito y validado; no
convierte automáticamente los `body` de una futura UI ni cierra M4 por sí solo. Windows se abordará después.
