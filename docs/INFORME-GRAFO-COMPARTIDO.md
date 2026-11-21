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

## Estado de las hipótesis de liberación (verificación empírica y desensamblado)

### Firmes

- **Hipótesis 1: El campo `+0x20` es un identificador secuencial que no decrementa**:
  - *Resultado*: **Firme**.
  - *Prueba*: Desensamblado de `AGGraphCreateShared` (0x1c2c4033c) y `AG::Graph::Context::Context(AG::Graph&)` (0x1c2c26f64). Al inicializar el contexto (0x1c2c26f7c), se invoca `AGMakeUniqueID` (0x1c2c26470) y su resultado se almacena en `[context + 0x10]` (que corresponde exactamente al offset `handle + 0x20`). `AGMakeUniqueID` es un generador atómico global monótono (`ldadd` de 1 sobre un contador global), por lo que nunca decrementa al liberar o invalidar.
- **Hipótesis 3: El caso 2 falla porque el contexto se destruye antes de materializar el enlace**:
  - *Resultado*: **Firme**.
  - *Prueba*: Desensamblado de `AG::Graph::input_value_ref_slow` (0x1c2c2ae54). Al resolver el nodo de entrada en `AG::data::_shared_table_bytes`, en 0x1c2c2aee0 se lee el contexto registrado `[node + 0x28]` y en 0x1c2c2aee4 se compara contra el contexto actual (`cmp x8, x24`). Si el contexto original fue destruido por la liberación del creador, los contextos no coinciden y salta a 0x1c2c2b214 emitiendo `accessing attribute in a different namespace: %u`. Al evaluar antes de liberar (caso 1), la arista queda enlazada en la tabla compartida y no vuelve a pasar por la validación fallida.
- **Hipótesis 4: Las lecturas `ref0..ref2` y `refAfterS1Invalidate` corresponden al campo `+0x1a4`**:
  - *Resultado*: **Firme**.
  - *Prueba*: Desensamblado de `AGGraphCreateShared` (0x1c2c40388: `add w8, w8, #1; str w8, [x20, #0x1a4]`) y `AG::Graph::Context::~Context` (0x1c2c270dc: `subs w8, w8, #1; str w8, [x0, #0x1a4]`), contrastado con lecturas directas en `test_h4_standalone.swift` y caso 4 de `lifetime.txt`. Los valores observados (1, 2, 3, 2, 1, 0) corresponden exactamente a las manipulaciones atómicas del campo `+0x1a4` del estado `AG::Graph`.

### Refutadas

- **Hipótesis 2: El fallo de `CFRelease` a mano es un double free**:
  - *Resultado*: **Refutada**.
  - *Prueba*: En un handle recién creado en C puro con `AGGraphCreate()`, invocar `CFRelease` tiene éxito limpio (retain count 1 -> 0 sin fallar). En Swift, el crash al forzar `c_CFRelease(rawPtr)` sobre un objeto gestionado por ARC no ocurre por memoria liberada (double free), sino por una trampa de autenticación de punteros (`EXC_BREAKPOINT` en `CoreFoundation` `CF_IS_OBJC + 64` al fallar `autda` y ejecutarse `brk #0xc472`), provocada por una incompatibilidad en la cabecera del modelo de objetos CF/ObjC puenteada con Swift.

### Sin resolver

- *Ninguna* (las cuatro hipótesis planteadas han sido resueltas mediante mediciones y desensamblado).

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
