# Contraste final y contrato mínimo de Binding

Fecha: 2026-11-14. Solo Mac. Continúa ESTUDIO-DUENO-Y-BINDING.md.

## Predicciones previas

Se separan reconstrucción del padre y escritura del dato con tres entradas: Binding con cierres recién construido,
el mismo Binding con cierres conservado y proyección de State. Cada una tiene hijo lector/no lector.

Para los cierres se usa un almacenamiento de prueba no observable: cambiarlo solo no debe programar cuerpos; una acción
separada cambia un State del padre y fuerza su reconstrucción. Así no se confunde lectura anticipada de State con la
comparación del argumento del hijo. La proyección de State es el control con invalidación real.

Predicciones: (1) cambiar únicamente el dato no observable no evalúa padre ni hijo; (2) escribir State proyectado evalúa
solo al hijo que lo consumió; (3) la reconstrucción con un Binding nuevo y dato cambiado puede ejecutar al hijo aunque
no lo lea. Se deja abierta la diferencia entre Binding estable y recién construido al reconstruir el padre sin cambio
del dato; se registrarán ambos cuerpos y las llamadas al getter.

Tras medir, el contrato mínimo del prototipo distinguirá construcción con cierres (get anticipado) de proyección de
State (sin lectura al construir). No se implementará un reconciliador general a partir de estos seis casos.

## Resultados de la sonda corregida

Seis variantes (tres entradas × lector/no lector), siete acciones cada una. Las acciones son reconstruir padre,
escribir 1 sin reconstruirlo, reconstruir, reconstruir sin cambio de dato, escribir 1 otra vez, escribir 2 y reconstruir.
Cada paso procesa el run loop durante 100 ms. Mac M1, macOS 15.7.9, Swift 6.2.4.

El padre ejecuta `[1,0,1,1,0,0,1]` en las seis variantes. La siguiente tabla registra el hijo y las llamadas a los getters
que nosotros instrumentamos, sin contar el montaje inicial:

| Entrada | Hijo no lector | Hijo lector | Getters instrumentados por paso |
|---|---|---|---|
| Binding con cierres nuevo en cada body | 1,0,1,1,0,0,1 | 1,0,1,1,0,0,1 | 2,0,2,2,0,0,2 |
| Mismo Binding con cierres conservado fuera de la vista | 0,0,0,0,0,0,0 | 0,0,0,0,0,0,0 | 0,0,0,0,0,0,0 |
| Proyección `$state` | 0,0,1,0,0,0,1 | 0,1,1,0,0,1,1 | No instrumentado |

- El Binding nuevo ejecuta al hijo aun reconstruyéndolo con el dato igual. No se deduce de esto qué comparación interna
  usa SwiftUI para decidirlo.
- Conservar el mismo Binding sobre almacenamiento no observable deja al hijo lector mostrando 0, incluso después de
  cambiar el dato y reconstruir al padre. **Un getter con un valor distinto no es por sí solo una señal de invalidación.**
- La proyección actualiza directamente al hijo lector al escribir el State. Si el padre se reconstruye después del cambio,
  también puede evaluar al hijo no lector; reconstruirlo otra vez con el dato igual lo omite. Esta observación pertenece
  al paso de actualización/comparación de las vistas, que nuestro montador aún no implementa.
- Las escrituras sin cambio no ejecutan cuerpos. El almacenamiento no observable solo cambia al escribirlo; nunca
  programa por sí mismo una actualización. Las predicciones de esos controles pasan.

### Control de contaminación de la sonda

La primera versión guardaba además un Binding estable como campo del padre, incluso en controles que no lo usaban.
Aparecieron llamadas adicionales a su getter y recuentos distintos en el caso proyectado. Se retiró ese campo: ahora el
Binding estable está en el objeto externo de la sonda y solo se construye para su propio caso. La versión corregida
satisface los controles iniciales. Se guarda el resultado original como `binding-refresh-initial-fixture-*.txt`, **no**
como resultado de paridad ni como perfil del control corregido. Esto evita atribuir al constructor probado lecturas
procedentes de otra propiedad de la vista.

Los perfiles completos se fijaron después del descubrimiento y antes de verificarlos en procesos independientes de
debug y release. No se presentan todos sus campos como predicciones previas.

## Contrato mínimo implementado en ShellUI

1. `Binding(get:set:)` llama una vez a get al construirse. Cada lectura posterior vuelve a llamarlo. Copiarlo y escribir
   mediante set no añade llamadas a get en nuestro contrato probado.
2. `State.projectedValue` construye una proyección interna que **no** lee el valor. Leer el wrappedValue de esa proyección
   sí consulta al almacenamiento y registra una dependencia si se evalúa un cuerpo.
3. Crear y descartar un Binding público dentro de una regla registra la lectura que hace su getter. Crear y descartar
   la proyección de State no registra esa arista. Escribir sigue siendo perezoso y destruir al dueño libera los nodos.

La implementación separa dos inicializadores en Binding, uno público con lectura anticipada y otro interno para
proyectar almacenamiento. Se mantienen las firmas públicas existentes; no hay un nuevo tipo de nodo ni cambios del
motor. No se necesita un recorrido nuevo y no se introducen dependencias externas.

**Alcance:** se cierra la diferencia de llamadas al getter durante construcción del estudio anterior. No se implementa
una caché de valores para comparar argumentos, actualización de DynamicProperty, descubrimiento automático de propiedades,
reconciliación de hijos ni persistencia de lecturas por identidad. Por tanto, el prototipo todavía no reproduce los
perfiles de actualización completos de la tabla nativa. El known issue anterior de reevaluación histórica sigue vigente.
El constructor anticipado también puede tener efectos de usuario dentro del getter, igual que en la sonda nativa:
no se oculta ni se convierte en una lectura perezosa.

## TDD y comprobaciones

- Antes de implementar, tres tests fallan con ocho aserciones: llamadas al getter, copia/escritura y dependencia del
  cuerpo que construye el Binding. La salida se conserva.
- Tras separar los inicializadores, los contratos pasan. Una mutación que hace que State.projectedValue use otra vez el
  constructor público falla en dos aserciones: aparece una arista y una reevaluación indebidas en el padre. Se restaura
  la implementación y se comprueba de nuevo el verde.
- Se conserva el contraste nativo de construcción (una llamada al construir, dos acumuladas al leer) y se actualiza el
  test del prototipo para afirmar ahora ese mismo resultado, en lugar de la diferencia histórica.
- Los ejemplos de Samples pasan type-check contra SwiftUI y contra ShellUI con el SDK de Xcode explícito.
- Batería de Views: **27 tests en debug y release**, con el known issue anterior. Las nuevas diferencias de reconciliación
  están descritas como límites, no como funcionalidad implementada. No se volvió a ejecutar la batería raíz porque no
  se cambiaron sus fuentes; se ejecutan los oráculos del grafo incluidos en Views.

## Rendimiento y reproducción

`PerformanceBindingConstructionPaths` mide 10.000 construcciones y lecturas de cada camino. El público lee dos veces
(construcción y wrappedValue), la proyección una. Se comprueba el resultado acumulado y la liberación del dueño. Es un
microbenchmark agregado, no p99 de una UI ni una comparación de velocidad con SwiftUI. Resultado release, una muestra: **4,472 ms** para constructor público + lectura y **4,325 ms** para proyección + lectura.
No se establece un umbral de regresión ni se infiere una proporción estable de esos dos tiempos.

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test --package-path Views
swift test --package-path Views -c release -Xswiftc -enable-testing
swift test --package-path Views -c release -Xswiftc -enable-testing --filter PerformanceBindingConstructionPaths
```

En el entorno restringido se usaron scratch y cachés bajo `/private/tmp`, además de `--disable-sandbox`. Las salidas
originales se guardan en `Views/Results/binding-*.txt`. Como en estudios anteriores, las esperas de 100 ms no descartan
trabajo posterior bajo otra carga; los resultados están limitados a estos valores, árboles y versión de SwiftUI.
Windows continúa aplazado.
