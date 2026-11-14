# Diseño M7: aristas eficientes (borrado O(1), poda por marca y barrido)

Fecha: 2026-11-14. Parte de [PLAN-MOTOR.md](PLAN-MOTOR.md) §3 (M7). Derivado del límite anotado en M0
(DISENO-M0.md §6: "borrar una arista cuesta O(grado) con arreglos") y M3 (DISENO-M3.md §7:
"hasChanged busca la arista de forma lineal (M7)"). **Estado: implementado** (código, tests y pruebas de escala;
las medidas de rendimiento se validan en Mac M1, Swift 6.2.4).

## 1. Problema

Las aristas de entrada y salida se guardan en arreglos paralelos de `NodeTable`:

```swift
var inputs: [[InputEdge]] = []   // entrada: (source, seenVersion, read, changed), en orden de lectura
var outputs: [[UInt32]] = []     // salida: dependientes, sin orden
```

`InputEdge` no guardaba su posición, así que borrar una arista requería buscarla linealmente:

| Operación | Coste antes de M7 | Por qué |
|-----------|-------------------|---------|
| `removeOutput(_:from:)` | O(grado) | `firstIndex(of:)` busca en `outputs[source]` |
| `recordRead(of:)` | O(grado) | busca el edge y hace `remove(at:)`/`insert(at:)` |
| `pruneEdges(of:keeping:)` | O(grado²) peor caso | llama a `removeOutput` por cada edge podado |
| `inputChanged(of:source:)` | O(grado) | busca linealmente en `inputs[node]` |
| `perform` (invalidación) | O(grado) por arista | `removeOutput` + `removeAll { $0.source == }` |

Un nodo con 100.000 dependientes que pierde la mitad de sus aristas costaba O(100.000 × 50.000).

## 2. Solución: posición guardada + swap-with-last

### 2.1 `InputEdge` guarda `positionInOutputs`

```swift
struct InputEdge {
    var source: UInt32
    var seenVersion: UInt32
    var read: Bool = false
    var changed: Bool = true
    /// Posición del nodo consumidor en `outputs[source]`. Establecida por `recordRead`; mantenida por `removeOutput`.
    var positionInOutputs: UInt32 = Graph.noNode
}
```

Cada arista de entrada sabe dónde está su nodo consumidor en el arreglo de salidas de su fuente.

### 2.2 `removeOutput` es O(1)

```swift
func removeOutput(_ dependent: UInt32, from source: UInt32, at position: UInt32) {
    let s = Int(source)
    let p = Int(position)
    guard p < table.outputs[s].count else { return }
    let last = table.outputs[s].count - 1
    if p != last {
        let movedNode = table.outputs[s][last]
        table.outputs[s][p] = movedNode
        updatePositionInOutputs(movedNode, from: source, to: UInt32(p))
    }
    table.outputs[s].removeLast()
}
```

Como `outputs` no tiene orden (el comentario del código lo dice: "the list has no order"), el swap-with-last es válido y no rompe ninguna semántica. O(1) en lugar de O(grado).

### 2.3 `updatePositionInOutputs` mantiene la posición del nodo movido

Cuando `removeOutput` mueve el último elemento a la posición del borrado, ese elemento movido necesita que su `positionInOutputs` se actualice. Se busca su arista de entrada a `source` (O(entradas del nodo movido), normalmente muy pequeño) y se actualiza.

### 2.4 `recordRead` registra la posición

Al crear una arista nueva:

```swift
table.outputs[Int(source)].append(evaluatingNode)
let position = UInt32(table.outputs[Int(source)].count - 1)
table.inputs[consumer].insert(InputEdge(source: source, seenVersion: version, read: true,
                                        positionInOutputs: position), at: trackCursor)
```

La posición se conoce inmediatamente después del `append`.

### 2.5 `pruneEdges` y `perform` pasan la posición guardada

Ambos ya tienen el `InputEdge` a mano, así que pasan `edge.positionInOutputs` a `removeOutput`. No hay búsqueda linealiar en `outputs[source]`.

## 3. Qué no cambia

- `outputs` sigue siendo `[[UInt32]]` (solo IDs de nodos, sin orden).
- `run()` y `advanceResumable()` iteran `outputs[n]` como antes (el atajo de corte de M1 no se ve afectado).
- `propagateDirty` / `drainDirtyStack` leen `table.outputs[source]` como antes.
- El orden de `inputs` (lectura) sigue siendo el orden de lectura; solo el borrado se hace por posición.

## 4. Tests

### Correctness (`Tests/…/Unit/EdgeRemovalTests.swift`)

1. Lectura condicional poda exactamente la arista no leída; escribir en la fuente podada no vuelve a ensuciar.
2. Lectura condicional que vuelve atrás reañade la arista.
3. Invalidar un subgrafo desprende aristas en ambos sentidos.

### Rendimiento (`Tests/…/Performance/PerformanceTests.swift`)

- `removingHalfOfOneHundredThousandOutputsIsLinear`: 100.000 dependientes leen un mismo nodo; se pierden la mitad.
  Debe ser lineal en el grado (muy por debajo de 5 s). Sin M7, el borrado lineal es O(100.000 × 50.000).

## 5. Límites

- `updatePositionInOutputs` busca la arista del nodo movido entre sus entradas: O(entradas del nodo movido). Una regla no lee dos veces al mismo atributo, así que en la práctica cada source aparece como máximo una vez en las entradas de un nodo.
- Si `positionInOutputs` se desactualizara, el `guard` en `removeOutput` evita borrar el nodo equivocado (no hace nada).
- Sin medir todavía: impacto en las métricas existentes de M0-M5.
