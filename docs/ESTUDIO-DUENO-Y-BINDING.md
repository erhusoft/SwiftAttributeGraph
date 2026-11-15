# Identidad del dueño y momento de lectura de Binding

Fecha: 2026-11-14. Continuación de ESTUDIO-LECTURAS-DINAMICAS.md. Solo Mac.

## Hipótesis y predicciones previas

1. Cambiar la identidad del consumidor preserva los valores del dueño, pero elimina las lecturas históricas del
   Binding proyectado del hijo. Cambiar la identidad del dueño reinicia los valores y el historial del consumidor.
2. Tras recrear al dueño, escribir segundo antes de que se haya leído no ejecutará al consumidor. Su primera
   escritura a primero sí lo ejecutará. Se contarán dueño e hijo por separado.
3. Se contrastan G0 (construir Binding con cierres no invoca get) y G1 (la construcción invoca get). Primero se prueba
   G0 fuera de cualquier vista, contando get antes de acceder a wrappedValue. El resultado decidirá cuál se conserva.
4. Si G1 se cumple, construir ese Binding dentro del body del dueño puede registrar una lectura aun descartándolo.
   Se predice que el dueño se reevaluará al escribir estado, incluso sin consumidor. La proyección `$state` descartada
   será el control negativo. Un hijo que recibe pero no lee permitirá separar construcción de consumo.

No se cambiará el núcleo para reproducir lecturas que pueda explicar el propio código de adaptación. Se conservarán
las predicciones refutadas y las salidas. Los nuevos tests son sondas; no se añaden algoritmos de producción.

## Observaciones y refutación

Mac M1, macOS 15.7.9, Swift 6.2.4 de Xcode. La sonda inicial falla exactamente en G0: **al terminar de construir el
Binding ya se llamó una vez a get**. Leer después `wrappedValue` lo llama otra vez: 1 llamada antes de la lectura,
2 acumuladas después. Se conserva la salida fallida; el oráculo de regresión comprueba G1. Es comportamiento observado
de este constructor, no código copiado del SDK ni una afirmación sobre el algoritmo interno del grafo.

### Construcción frente a consumo

Cada variante inicia en 0 y recibe las escrituras 1, 1 y 2, separadas por procesamiento del run loop. Los números de
la tabla son incrementos por acción; no incluyen el montaje inicial.

| Variante | Body del dueño | Body del hijo | Llamadas instrumentadas a get |
|---|---|---|---|
| Binding con cierres, construido y descartado | 1,0,1 | 0,0,0 | 1,0,1 |
| Binding con cierres, hijo no lee el valor | 1,0,1 | 1,0,1 | 2,0,2 |
| Binding con cierres, hijo lee el valor | 1,0,1 | 1,0,1 | 2,0,2 |
| Proyección `$state` descartada | 0,0,0 | 0,0,0 | No instrumentado |
| Proyección `$state`, hijo no lee | 0,0,0 | 0,0,0 | No instrumentado |
| Proyección `$state`, hijo lee | 0,0,0 | 1,0,1 | No instrumentado |

El contador `get` solo instrumenta nuestros cierres; el cero que imprimen los controles proyectados no prueba que
SwiftUI nunca lea internamente su ubicación. En la variante descartada no existe un hijo que pueda explicar la
lectura inicial: el constructor se ejecuta dentro del body del dueño, y su cierre lee el State allí. Esto ofrece una
explicación observable de las reevaluaciones adicionales del padre en el estudio anterior.

El caso del hijo que no lee el Binding con cierres también vuelve a evaluar ese hijo. La sonda registra el fenómeno,
pero no demuestra si lo causa la comparación de los nuevos valores de vista, la actualización de propiedades u otra
parte de SwiftUI. No se extrapola ese comportamiento al constructor de Binding de todas las versiones.

### Identidad del consumidor y del dueño

Dueño con primero=0, segundo=100 y selección inicial de primero. El hijo recibe bindings proyectados.

| Acción | Body dueño | Body hijo | Valor |
|---|---:|---:|---:|
| Primero=1 | 0 | 1 | 1 |
| Seleccionar segundo | 0 | 1 | 100 |
| Primero=2, inactivo pero leído antes | 0 | 1 | 100 |
| Recrear solo al hijo | 1 | 1 | 100 |
| Primero=3, inactivo tras recrear hijo | 0 | 0 | 100 |
| Segundo=101 | 0 | 1 | 101 |
| Recrear al dueño | 1 | 1 | **0** |
| Segundo=102, nunca leído por el nuevo hijo | 0 | 0 | 0 |
| Primero=4 | 0 | 1 | 4 |
| Primero=4 otra vez | 0 | 0 | 4 |

Se confirman las predicciones iniciales. La recreación del hijo conserva los State del dueño y elimina una lectura
anterior del consumidor. Recrear al dueño reinicia tanto valores como selección y el nuevo hijo no responde al segundo
estado antes de consumirlo. El cambio de identidad del hijo reevalúa al dueño porque este lee su contador de identidad;
no es una evaluación causada por el dato inactivo.

## Contraste con el prototipo y el núcleo

**Existe otra diferencia explícita en ShellUI:** su `Binding(get:set:)` difiere la llamada a get hasta `wrappedValue`.
El nuevo test conserva ese comportamiento actual como una limitación identificada: 0 llamadas tras construcción y 1
tras lectura, frente a 1 y 2 en SwiftUI. Que la batería pase no significa paridad de estos constructores.

Además, `State.projectedValue` en nuestro prototipo usa ese mismo constructor con cierres. Hacer que todos los bindings
llamen get al construirse sería una corrección incompleta: podría convertir una proyección `$state` en una lectura
anticipada del padre, justamente donde las sondas nativas muestran que no ocurre. La implementación futura necesita
separar la proyección del almacenamiento de la creación pública mediante cierres, con tests antes de implementar.
Todavía falta especificar el comportamiento posterior de actualización del Binding antes de promoverlo a compatibilidad.

El oráculo del núcleo comprueba que sustituir al consumidor conserva el objeto almacenado por el dueño; destruir al
dueño lo libera y deja `nodeCount == 0`, `edgeCount == 0` y solo el subgrafo raíz. La referencia débil verifica liberación
real del objeto, además del contador de nodos. El nuevo consumidor vuelve a leer el valor conservado.
Esta comprobación de liberación se hace en nuestro grafo; la sonda SwiftUI comprueba reinicio de valores, no liberación
inmediata de todos los objetos internos de Apple.

No se cambiaron fuentes de producción ni el contrato de poda. No se añadieron recorridos ni costes nuevos del motor.
Los resultados afinan la adaptación de propiedades y la identidad por encima del núcleo. Windows continúa aplazado.

## Validación y reproducción

- Descubrimiento: tres tests, un fallo esperado de hipótesis G0. No se trató ese fallo como evidencia de un defecto del motor.
- Regresión: cinco tests nuevos. Afirman constructor nativo, perfiles completos de identidad y seis variantes de
  construcción/consumo, la diferencia actual de ShellUI y la vida del objeto en el núcleo.
- Batería completa de Views: **23 tests en debug y release**, con el known issue previo de paridad. No se agregaron
  known issues para ocultar resultados nuevos: el contraste del prototipo afirma explícitamente su diferencia.
- Salidas originales en `Views/Results/owner-binding-*.txt`; fuente en `Views/Tests/ShellUITests/OwnerBindingProbeTests.swift`.

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test --package-path Views --filter ownerBinding
swift test --package-path Views -c release -Xswiftc -enable-testing
```

Se usaron `--disable-sandbox`, scratch y cachés bajo `/private/tmp` en el entorno restringido. Una primera forma de invocar
el resultado de `#require` directamente dentro del switch hizo fallar el compilador Swift 6.2.4; separar extracción de
la acción e invocación evitó el problema. No era un fallo en ejecución del motor.

Límites: pasos de run loop de 100 ms; se verifican los valores y recuentos al terminar esa ventana. No se mide latencia,
ni se descarta trabajo posterior bajo otras cargas. Los perfiles completos se fijaron tras descubrimiento y se
verificaron en procesos separados de debug y release; no son nuevas predicciones independientes de todos sus campos.
Las predicciones de reinicio y de reevaluación al descartar el Binding con cierres sí se escribieron antes de descubrirlos.

Siguiente paso: especificar y probar por separado la construcción pública de Binding con cierres y la proyección de State,
incluida la actualización del hijo que recibe un Binding sin consumirlo. Después se decidirá la implementación de esa
capa. Estos experimentos todavía no justifican cambiar las dependencias exactas del núcleo.
