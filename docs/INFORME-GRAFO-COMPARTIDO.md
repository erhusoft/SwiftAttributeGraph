# Informe: `AGGraphCreateShared` (`Graph(shared:)`)

Estado: medido en nativo (macOS 15.8.3). Sin implementar en el motor. Todas las medidas son de la sonda nativa
(`NativeProbe`, `share-*`, `independent-read`, `inherit`) o de apps de SwiftUI de prueba.

## Qué es (firme)

- Devuelve un handle nuevo sobre el **mismo estado** del grafo. Es un objeto de CoreFoundation del tipo del grafo
  (`CFGetTypeID` igual a `AGGraphGetTypeID`).
- La referencia de Swift ocupa 8 bytes: es el puntero del handle.
- Todos los handles de un grafo apuntan al mismo estado (campo `+0x10`).
- Un contador en `+0x20` sube en uno por cada handle nuevo (2 → 3 → 4 → 5). Cuenta los handles que comparten el estado.
- No copia datos. Pasa una referencia, como un `Binding` de SwiftUI.

## Qué comparte (firme)

- Lee y ve los cambios de la primera referencia.
- Hereda todo el grafo, en los dos sentidos: nodos creados antes o después de la referencia, y desde cualquiera de las dos.
- Cuenta los mismos nodos (`nodeCount` igual en las dos).
- Sobrevive si se libera la primera referencia (siempre que sus nodos se hayan evaluado antes).

## Qué no comparte (firme)

- La identidad: son referencias distintas.
- El puntero de contexto de usuario: al fijarlo en un contexto, el otro sigue en `nil`.

## Regla de espacio de nombres (firme)

- Dos grafos normales son espacios separados. Leer desde uno un atributo del otro aborta (código 134):
  `accessing attribute in a different namespace: 536`.
- Un handle compartido sí puede leer el espacio del grafo del que procede.
- Leer un nodo sin evaluar de la primera referencia, después de liberarla, aborta con el mismo mensaje.
- Dos ventanas de la misma app **no** abortan al leerse entre sí: comparten el grafo del proceso (sección siguiente).
  El aborto solo aparece entre grafos normales independientes.

## Uso en SwiftUI (firme, medido en apps de prueba)

- Al arrancar hay **un** `AGGraphCreate` por proceso (el de `sharedGraph`, dentro de un `dispatch_once`).
- Cada host (menús, ventanas, sheets) recibe un `AGGraphCreateShared`. Con una ventana: 9 llamadas (6 de menús,
  1 de la ventana y 1 del `sharedGraph`, más el resto de la infraestructura). Con dos ventanas: 10. Un sheet también suma 1.
- Las dos ventanas comparten el mismo puntero de estado (`0x3f606700` en los nueve handles): **un grafo para todo
  el proceso**, no uno por ventana.
- Un sheet que lee un `Binding` del padre se actualiza una vez por cada cambio (5 evaluaciones para 5 valores).

## Coste (firme)

- Crear un handle compartido: unos 0,14 µs. Crear un grafo independiente: unos 0,7 µs.
- 1.000.000 de handles: 248 ms. Cadena de 200.000 handles compartidos sobre handles: 19 ms. Sin errores.

## Liberación (firme)

- **Comportamiento ante liberación del creador**:
  - Si los nodos fueron evaluados antes de liberar la referencia Swift creadora, la lectura desde el handle compartido sobrevive y retorna el valor esperado (caso 1: `case1|exit=0|evaluatedBefore=42|readAfter=42` en `lifetime.txt`).
  - La supervivencia se mantiene en cadenas de compartidos (compartido de compartido) con independencia del orden en que se liberen las referencias intermedias o la original (casos 3a y 3b: `case3a|exit=0` y `case3b|exit=0` en `lifetime.txt`).
  - Si el nodo no se evaluó antes de liberar el grafo original, la lectura posterior desde el compartido aborta con SIGABRT (caso 2: `case2|exit=134|message=accessing attribute in a different namespace: 536` en `lifetime.txt`).
- **Mecanismo de invalidación (`AGGraphInvalidate`)**:
  - `AGGraphInvalidate` lee la marca booleana en `handle + 0x58`. Si es distinta de 0, retorna de inmediato (`tbnz w8, #0x0`; verificado en desensamblado con lldb de `AGGraphInvalidate`).
  - Si es 0, invoca `AG::Graph::Context::~Context()` pasando como argumento el puntero al contexto en `handle + 0x10` (`add x0, x0, #0x10; bl AG::Graph::Context::~Context()`; verificado en desensamblado de `AGGraphInvalidate`).
  - Tras retornar del destructor del contexto, escribe `1` en `handle + 0x58` (`mov w8, #0x1; strb w8, [x19, #0x58]`; verificado en desensamblado de `AGGraphInvalidate`, confirmado con caso 5 en `lifetime.txt`).
- **Destrucción del contexto (`AG::Graph::Context::~Context()`)**:
  - Lee el puntero al grafo `AG::Graph*` desde el primer campo del contexto (`ldr x0, [x19]`), lee y decrementa en 1 el campo `+0x1a4` del grafo (`ldr w8, [x0, #0x1a4]; subs w8, w8, #0x1; str w8, [x0, #0x1a4]`; verificado en desensamblado de `AG::Graph::Context::~Context()`).
  - Si el resultado es cero (`b.ne` no salta), invoca el destructor `AG::Graph::~Graph()` y libera la memoria con `operator delete` (`bl AG::Graph::~Graph(); bl operator delete`; verificado en desensamblado de `AG::Graph::Context::~Context()`).

## Hipótesis sobre liberación y ciclo de vida

- **Hipótesis 1: El campo `+0x20` es un identificador secuencial que no decrementa**:
  - *Estado*: Compatible con las lecturas (`idG1=2, idS1=3, idS2=4`, y `idS1` sigue en 3 tras liberar s2 en caso 4 de `lifetime.txt`), pero **no está demostrado**.
  - *Prueba que la confirmaría*: Desensamblar la función constructora que inicializa el handle (`AGGraphCreate` / `AGGraphCreateShared`) y localizar la instrucción exacta que asigna el valor en `handle + 0x20` desde un contador global o de proceso.
- **Hipótesis 2: La causa del fallo de `CFRelease` a mano es un double free**:
  - *Estado*: **No identificada**. El fallo ocurre en `CF_IS_OBJC` / `objc_release` con código 139 al invocar `CFRelease` sobre un handle con retain count 1. No se puede afirmar que sea un double free.
  - *Prueba que la confirmaría*: Rastrear en lldb la estructura de la cabecera de objeto CF/ObjC del handle, su puntero de isa/clase y el estado de retain en el runtime al momento del fallo.
- **Hipótesis 3: El caso 2 falla porque el contexto se destruye antes de materializar el enlace**:
  - *Estado*: Es una explicación plausible de por qué aborta con `accessing attribute in a different namespace: 536` al soltar el grafo sin haber evaluado el nodo, pero **no está demostrada**.
  - *Prueba que la confirmaría*: Inspeccionar con lldb la rutina interna de evaluación y resolución de dependencias entre espacios de nombres (`AG::Graph::resolve_attribute` / `namespace_id`), comprobando qué estructura se elimina durante `Context::~Context()` que impide resolver atributos no cacheados.
- **Hipótesis 4: Las mediciones `ref0..ref2` y `refAfterS1Invalidate` leen exactamente el refcount `+0x1a4` del grafo**:
  - *Estado*: En la sonda se leyó el offset `state + 0x1a4` (`ref0=1, ref1=2, ref2=3`, decrementando a 2, 1 y 0 en caso 4 de `lifetime.txt`), coincidiendo con el offset decrementado en el desensamblado de `Context::~Context()`. Sin embargo, no está formalmente comprobado si ese campo es un refcount exclusivo o si codifica flags adicionales en bits altos.
  - *Prueba que la confirmaría*: Desensamblar `AGGraphCreate` y `AGGraphCreateShared` completos para confirmar que `+0x1a4` se manipula únicamente como entero atómico de conteo de referencias.

## Abierto

- Dependencia cruzada entre ventanas **a nivel de grafo**. La prueba con dos ventanas usó un `ObservableObject`
  (mecanismo de SwiftUI), no una lectura directa del grafo.
- Dos hosts con dos grafos independientes y un handle cada uno: la sonda falla dentro de `AG::Graph::value_ref`
  (139), antes de la comparación. Puede ser un error de la sonda.

## Consecuencias para el motor

- Un solo estado con varios handles es el modelo que usa SwiftUI. El handle de reenvío del diseño
  (`docs/DISENO-GRAFO-COMPARTIDO.md`) va en esa dirección.
- La decisión de implementar `Graph(shared:)` sigue pendiente, con la regla de liberación y la marca `+0x58` como
  prerequisitos.

## Dónde están las pruebas

- `NativeProbe/Results/shared-graph-macos-15.8.3/`: `native.txt`, `fault.txt`, `handle-count.txt`,
  `release-rule.txt`, `rules.txt`.
- Sondas en `NativeProbe/Sources/Probe/SharedGraphProbe.swift`.
