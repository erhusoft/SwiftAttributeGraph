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

## Liberación (abierto)

- Soltar la referencia de Swift no baja el contador de CoreFoundation (1 → 1) ni el contador `+0x20`.
- Liberar a mano con `CFRelease` falla (139) dentro de `CF_IS_OBJC`. El finalizador de la clase del grafo es nulo.
  La causa no está identificada.
- No sabemos quién es dueño del handle, ni cuándo baja el contador `+0x20`.

## Abierto

- Dependencia cruzada entre ventanas **a nivel de grafo**. La prueba con dos ventanas usó un `ObservableObject`
  (mecanismo de SwiftUI), no una lectura directa del grafo.
- Qué significa la marca `+0x58` del handle (vale 0 en uso normal; su ruta de error no se ha activado).
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
