# Diseño M3: reglas con estado (borrador, pendiente de aprobación)

Fecha: 2026-11-14. Parte de [PLAN-MOTOR.md](PLAN-MOTOR.md) §3 (M3), [FUNDAMENTOS.md](FUNDAMENTOS.md) (nombres de
AttributeGraph: `StatefulRule`) y de [PREGUNTAS.md](PREGUNTAS.md) (`DynamicBody` necesita «qué propiedades cambiaron»).
**Estado: propuesta. No se implementa nada hasta que el dueño la apruebe.**

## 1. Qué es y qué falta

Una `Rule` de M0 calcula su valor desde cero con lo que lee. Una **regla con estado** además:
1. ve su **valor anterior** y puede **decidir no cambiarlo**;
2. sabe **qué entradas cambiaron** desde su última ejecución (`anyInputsChanged`, `hasChanged`);
3. puede guardar **estado propio** entre ejecuciones (es un valor de Swift que vive en el nodo).

Sirve para valores que acumulan (historial, contador de cambios) y para reglas que leen varias entradas pero solo
reaccionan a una (`DynamicBody`). No es observable por separado en SwiftUI: lo que sí es observable es lo que se
construye encima (qué `body` corre), así que **M3 no se mide contra SwiftUI**; es un contrato del motor con tests propios.
Lo que **no** se sabe de SwiftUI/AttributeGraph y se supone aquí está marcado como supuesto (§7).

## 2. API propuesta

```swift
/// A rule that sees its previous value and which inputs changed.
public protocol StatefulRule {
    associatedtype Value
    /// The value before the first run, if the rule has one (default: none).
    static var initialValue: Value? { get }
    /// Runs when an input changed (and the first time). Set `context.value` to change the attribute; leave it alone to keep it.
    mutating func updateValue(_ context: inout RuleContext<Value>)
}
extension StatefulRule { public static var initialValue: Value? { nil } }

public struct RuleContext<Value> {
    public var value: Value { get set }      // previous value on entry (precondition if there is none); writing marks it changed-by-the-rule
    public var hasValue: Bool { get }        // false only on the first run without `initialValue`
    public func hasChanged<T>(_ attribute: Attribute<T>) -> Bool
    public func anyInputsChanged(excluding: [AnyAttribute] = []) -> Bool
    public func changedValue<T>(of attribute: Attribute<T>) -> (value: T, changed: Bool)   // reads and reports
}

extension Graph {
    public func makeStatefulRule<R: StatefulRule>(_ rule: R, comparison: Comparison = .viewValue) -> Attribute<R.Value>
    public func makeStatefulRule<Value>(initialValue: Value? = nil, comparison: Comparison = .viewValue,
                                        _ body: @escaping (inout RuleContext<Value>) -> Void) -> Attribute<Value>   // closure shortcut (P3)
}
```

Elecciones y alternativas:

| Tema | Propuesta | Alternativa | Por qué |
|---|---|---|---|
| Forma | **Contexto `inout`** que lleva valor, `hasValue` y las consultas | `updateValue(previous:changes:) -> Value?` | El contexto deja leer el valor anterior, no tocarlo y consultar a la vez; AttributeGraph hace lo mismo con su contexto implícito. Un tipo explícito se prueba sin hilo local |
| Lecturas | Siguen siendo implícitas: `attribute.value` dentro de `updateValue` (igual que `Rule`) | Pasarlas por el contexto | Coherencia con M0 (decisión §9.1 de `DISENO-M0.md`) |
| Estado propio | `mutating`: el struct de la regla vive en el nodo y conserva lo que se escriba en él | `nonmutating` + valor | Más simple para acumuladores; el nodo es su dueño y muere con su subgrafo (principio 2) |
| Política de comparación | La misma que el resto (`Comparison`, M2): al escribir `context.value`, el valor nuevo pasa por ella contra el anterior y **solo sube la versión si cuenta como cambio** | Siempre sube | Mantiene el corte por versiones |

## 3. Semántica

- **Primera ejecución:** `hasValue` es `true` solo si hay `initialValue`. Si la regla no escribe `value` y no hay `initialValue`:
  `precondition`. Con `initialValue` y sin escribir, el atributo queda con ese valor y su versión no sube.
  `hasChanged`/`anyInputsChanged` devuelven `true` para toda entrada leída (no hay ejecución anterior).
- **Ejecuciones siguientes:** `context.value` empieza siendo el valor anterior. Si la regla no lo escribe, **no cambia**:
  la versión no sube y los dependientes se saltan (el corte de M0 se aplica tal cual).
- **«Cambió» = la versión de la fuente es distinta de la que la regla vio en su última ejecución** (la `seenVersion`
  de la arista, la misma información que usa M0 para decidir si corre). Una entrada leída por primera vez en esta
  ejecución cuenta como cambiada. `hasChanged` sobre un atributo que la regla **nunca** ha leído devuelve `false` y no
  lo lee.
- **Perezoso como siempre:** si se escribe varias veces antes de leer, la regla corre **una** vez y ve el último valor;
  no ve cada escritura. (Igual que una regla normal; se documenta con un test porque un acumulador depende de ello.)

## 4. Cambios en el motor

1. **Aristas:** `InputEdge` gana `changed: Bool` (cabe en el relleno actual: 12 bytes). Antes de ejecutar una regla con
   estado se calcula `changed = versions[source] != seenVersion` para cada arista, **antes** de que la ejecución
   reescriba las versiones vistas. Las reglas normales no pagan nada.
2. **Verificación sin salida temprana (solo reglas con estado):** hoy una regla sucia deja de verificar en la primera
   entrada con otra versión. Para saber qué cambió hay que tener **todas** las entradas al día. Por eso, en una regla
   con estado el bucle de `update` **sigue recorriendo** las aristas tras la primera diferencia y apila las fuentes
   sucias en la pila explícita, y solo después ejecuta. Así `hasChanged` nunca provoca una actualización anidada en la
   pila nativa y las cadenas profundas (principio 1) siguen sin recursión. Un bit nuevo `NodeState.stateful` evita
   mirar el tipo de la caja en el camino caliente.
3. **Nodo:** `StatefulRuleNode<R>` y `ClosureStatefulRuleNode` (cierre). `NodeBox.evaluate()` pasa a recibir el grafo y el
   índice del nodo (las reglas normales lo ignoran) para construir el contexto.
4. **Contexto:** `RuleContext` guarda el valor propuesto, si se escribió, y una referencia no retenida al grafo y el
   índice del nodo para responder a las consultas. No sobrevive a la llamada.
5. **Rastreo:** `changedValue(of:)` registra la lectura como cualquier otra; `hasChanged` y `anyInputsChanged` no
   registran nada.

## 5. Tests (primero; deben fallar antes de implementar)

**Los dos del plan:**
1. *Acumulador:* una regla suma el valor de una entrada al valor anterior cada vez que cambia; tras escribir 1, leer, escribir 2,
   leer: 3. Tras dos escrituras seguidas y una lectura: la regla corrió una vez (§3).
2. *Reacciona a una entrada:* lee `a` y `b`; solo cuando `a` cambió incrementa un contador. Escribir `b` ejecuta la regla,
   no cambia el valor, no sube la versión y un dependiente se salta.

**Más:** `initialValue` (sin escribir; escribiendo); regla que no escribe nunca tras la primera ejecución (versión
estable, dependientes saltan); estado propio (`mutating`) conservado entre ejecuciones; `hasValue`; `anyInputsChanged(excluding:)`;
`changedValue(of:)` con una entrada nueva (cambiada) y con una vieja; política de comparación aplicada al valor escrito
(`.stateWrite` con `Double` -0.0 no sube la versión); errores de programación con `precondition` (primera ejecución sin
valor; leer `value` sin valor; escribir el grafo dentro de la regla).
**Profundidad:** cadena de 20.000 reglas con estado, cada una llamando a `anyInputsChanged`, escribiendo en la raíz y
leyendo al final: sin desbordar la pila. **Vida:** `nodeCount` vuelve a la base y el estado propio de la regla (un
objeto con contador de `deinit`) se libera con su subgrafo. **Oráculo:** el de ejecuciones de M0 (una regla corre si y solo
si una entrada que leyó cambió de versión) con reglas que cuentan sus ejecuciones: el contador del estado debe coincidir
con el modelo, también con reglas normales mezcladas.
**Rendimiento (release):** 1.000 reglas con estado × 50 ciclos de escribir y actualizar, frente a 1.000 reglas normales
(M0: 17,3 ms): criterio **≤ +30 %**; el coste esperado es el recorrido completo de las aristas y el contexto.

## 6. Orden de trabajo

1. Tests rojos (§5). 2. `InputEdge.changed`, bit `stateful`, `update` con verificación completa. 3. `RuleContext`,
`StatefulRule`, nodos y `makeStatefulRule`. 4. Verde en depuración y release. 5. Medida y `PLAN-MOTOR.md` (§8 resultados de M3).
6. Un commit.

## 7. Supuestos, límites y riesgos

- **Supuesto, sin medir en AttributeGraph/SwiftUI:** que «cambió» es la diferencia de versión por arista. La alternativa
  (una marca `Changed` por arista puesta al actualizar la fuente, como en Compute) da lo mismo cuando todas las entradas
  están al día, que es lo que garantiza §4.2.
- **Pérdida de la salida temprana en reglas con estado:** una regla con estado verifica todas sus entradas aunque la
  primera ya haya cambiado. Coste lineal en el número de entradas, medido en §5. Las reglas normales no cambian.
- **`hasChanged` de un atributo no leído** devuelve `false` (no `precondition`); se prefiere no romper a una regla
  condicional que aún no ha leído esa rama.
- **No cubre:** reglas que lanzan o se cancelan (aplazado, `PLAN-MOTOR.md` §4), escribir dentro de una regla, y
  `changedValue` con opciones de AttributeGraph (`.syncMainRef`, etc.).
- **Interacción con M4:** una lectura **nueva** dentro de `updateValue` sigue usando la pila nativa (límite ya
  documentado de M0, lo quita M4); el test de profundidad solo cubre entradas ya leídas.

## 8. Preguntas para el dueño

1. ¿Contexto `inout` (propuesto) o `updateValue(previous:changes:) -> Value?`?
2. ¿Aceptas que una regla con estado verifique todas sus entradas antes de ejecutar (§4.2)? Es lo que evita la recursión nativa.
3. ¿Estado propio con `mutating` (propuesto) o sin él?
4. ¿M3 sin medida contra SwiftUI (solo tests propios) hasta que exista la capa de vistas?
