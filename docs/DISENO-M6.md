# Diseño M6: atributos indirectos y desplazados

Fecha: 2026-11-14. Parte de [PLAN-MOTOR.md](PLAN-MOTOR.md) §3 (M6). **Estado: implementado** (código y tests; las
medidas de rendimiento se validan en Mac M1, Swift 6.2.4).

## 1. Problema

A veces la UI necesita exponer un atributo que es, en realidad, una redirección a otro atributo existente: por
ejemplo, un campo de un struct grande como atributo independiente sin duplicar el nodo ni la versión. M6 añade
**atributos indirectos**: un atributo que no tiene valor propio ni ranura de valor, sino que lee/escribe a través de
otro atributo (el *source*).

## 2. API pública

```swift
extension Graph {
    /// Creates an indirect attribute that redirects to `source`, in the current subgraph.
    ///
    /// Reading the indirect attribute reads `source`; writing it writes to `source`. It has no
    /// value of its own and shares `source`'s version, so the value cut applies to `source`.
    /// `source` must not be a rule (rules cannot be written to).
    public func makeIndirect<Value>(_ source: Attribute<Value>) -> Attribute<Value>
}
```

## 3. Estructuras internas

### 3.1 `NodeState.indirect` (bit 1 << 9)

Nuevo bit en `NodeState` que marca los nodos indirectos en `NodeTable.state`.

### 3.2 `IndirectNode<Value>: NodeBox`

```swift
final class IndirectNode<Value>: NodeBox {
    /// The attribute this indirect redirects to.
    let source: AttributeID

    init(source: AttributeID)
}
```

Hereda de `NodeBox` directamente (no de `TypedNode`): no tiene valor propio (`value` siempre nil) ni comparador
`isEqual`. Almacena solo el `source` al que redirige.

### 3.3 `Graph.makeIndirect(_:)`

```swift
public func makeIndirect<Value>(_ source: Attribute<Value>) -> Attribute<Value> {
    precondition(table.isLive(source.id), "the source attribute is dead")
    precondition(table.state[source] & NodeState.isRule == 0, "cannot redirect to a rule")
    let id = allocate(IndirectNode(source: source.id), state: NodeState.hasValue)
    return Attribute(id: id)
}
```

Precondiciones:
- El `source` debe estar vivo.
- El `source` no debe ser una regla (no se puede escribir en una regla).

## 4. Lectura y escritura

### Lectura (`Graph.read`)

Cuando el nodo leído tiene el bit `indirect`:

1. Se verifica que el `source` siga vivo (`precondition`).
2. Si hay una regla en ejecución, se registra la lectura del indirecto (`recordRead`).
3. Se delega la lectura al `source` mediante una llamada recursiva a `read(Attribute(id: source))`. Esa llamada
   registra también la lectura del `source` como dependencia de la regla en curso, así que cambiar el `source`
   ensucia a quien lee el indirecto.

### Escritura (`Graph.setValue`)

Cuando el nodo escrito tiene el bit `indirect`:

1. Se verifica que el `source` siga vivo (`precondition`).
2. Se delega la escritura al `source` mediante `setValue(value, for: Attribute(id: source))`.
3. `globalVersion` sube una sola vez, en el source real (no en el indirecto).

## 5. Corte por versiones

El indirecto no tiene versión propia: comparte la del `source`. Escribir el mismo valor en el `source` no sube la
versión, así que el indirecto refleja el corte del source. Una regla que lee el indirecto depende del source y se
corta si el source no cambió.

## 6. Tests (`Tests/…/Unit/IndirectTests.swift`)

1. Leer un indirecto devuelve el valor del source.
2. Escribir en un indirecto escribe en el source (y viceversa).
3. El indirecto comparte el corte de versión del source.
4. Una regla que lee un indirecto depende del source: cambiar el source ensucia la regla.
5. Una regla que lee un indirecto no se re-ejecuta si el source no cambió.
6. Varios indirectos comparten el mismo source.
7. Escribir en un indirecto está permitido (no es una regla).

## 7. Límites

- Un indirecto solo puede redirigir a un atributo de entrada (no a una regla).
- Redirigir a otro indirecto crea una cadena resuelta por recursión en `read`/`setValue`; ciclos entre indirectos
  son un error de programación no detectado.
- No hay API para cambiar el destino de un indirecto tras crearlo ("cambio de destino" del plan queda como límite
  conocido; se añadiría con `redirect(_:)` si la UI lo necesita).
- El desplazamiento por key path (leer un campo del source sin nodo propio) no está cubierto en esta versión; se
  deja para una iteración posterior.
