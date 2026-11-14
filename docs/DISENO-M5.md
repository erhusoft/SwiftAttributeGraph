# Diseño M5: subgrafos jerárquicos e invalidación diferida

Fecha: 2026-11-14. Parte de [PLAN-MOTOR.md](PLAN-MOTOR.md) §3 (M5), [DISENO-M0.md](DISENO-M0.md) (subgrafo plano) y de la
paridad con SwiftUI medida (E7, E8, E19 en `parity/ANALISIS.md`, y la ronda 7 de esta nota, §1).
**Estado: aprobada e implementada** (resultados, límites y lo no verificado en [PLAN-MOTOR.md](PLAN-MOTOR.md) §9). Desviación: el coste de «2.000 subgrafos × 5 atributos» subió un 12 % (el criterio era ≈ 10 %).

## 1. Qué hay hoy y qué falta

M0 tiene un **subgrafo plano**: `makeSubgraph()`, `withCurrent(_:_:)` e `invalidate(_:)`, que libera lo suyo y deja a
los lectores de fuera sucios y sin esas aristas (`pending`). Falta:

1. **Jerarquía.** Una rama, o una fila de un `ForEach`, contiene otras ramas y otras filas. Invalidar el padre debe
   invalidar a los hijos, sin recursión (principio 1).
2. **Invalidación durante una actualización.** Hoy `invalidate` hace `precondition(evaluatingNode == noNode)`. Un `body`
   que cambia de rama la ejecuta **desde dentro de una regla**. Hay que diferirla hasta que acabe la actualización.
3. **Subgrafo actual al ejecutar una regla.** Una regla que crea atributos o subgrafos hijos debe crearlos en **su**
   subgrafo, para que mueran con él.
4. **Aviso de que un subgrafo va a desaparecer** (el `onDisappear` de la capa de vistas), con el orden medido.

## 2. Lo medido en SwiftUI (ronda 7, macOS 15.7.9; `parity/Compare/resultados-macos-15.7.9-ronda7-ramas.txt`)

Tres ejecuciones, mismo resultado. Cada línea es el orden de eventos tras la acción.

| Caso | Orden medido |
|---|---|
| Cambio de rama `Outer{Inner1, Inner2}` → `Other` | `Other` se **construye entero** (estado, body, onAppear) **antes** de que nada de la rama vieja desaparezca. Después: `Inner2 onDisappear`, `Inner1 onDisappear`, `Outer onDisappear` (los hijos **antes** que el padre; entre hermanos, el último primero). Al final se liberan los estados: `Inner2`, `Inner1` |
| Volver a `Outer` | Igual: `Outer` (con estado nuevo) se construye antes de que `Other` haga `onDisappear` y libere su estado |
| `ForEach`: quitar la fila 2 | `Row2 onDisappear` y **después** su estado se libera |
| `ForEach`: sustituir `[1,3]` por `[7,8]`; quitar todas | Las nuevas se construyen y hacen `onAppear` primero; las viejas hacen `onDisappear` **en orden de creación** (`Row1`, `Row3`; `Row7`, `Row8`) y luego liberan los estados |

Hechos que se usan: (a) **todo `onDisappear` va antes de liberar el estado**; (b) **lo nuevo se crea antes de que lo
viejo se destruya**; (c) en una rama los hijos van antes que el padre. **El orden entre hermanos no es uno solo**
(inverso en la rama, directo en el `ForEach`), así que el motor **no promete** un orden entre hermanos: lo decide
quien invalida, que puede invalidar los hermanos uno a uno en el orden que quiera. Lo ya medido de E7/E8/E19 se mantiene:
al volver a una rama el estado vuelve al inicial; el estado de una fila sigue a su id; reordenar filas sin estado no ejecuta ninguna.

## 3. API propuesta

```swift
extension Graph {
    /// A child of `parent` (default: the current subgraph).
    public func makeSubgraph(parent: Subgraph? = nil) -> Subgraph          // M0: makeSubgraph() sin padre
    /// Frees the subgraph and its descendants; during a rule it happens when the outermost update ends.
    public func invalidate(_ subgraph: Subgraph)                           // ya existe: gana la jerarquía y el diferido
    /// Called once, when the subgraph and its descendants are about to be freed, still readable.
    @discardableResult
    public func observe(_ subgraph: Subgraph, onInvalidate: @escaping () -> Void) -> SubgraphObservationToken
    public var liveSubgraphCount: Int { get }                              // pruebas de vida
}
```

- **Padre por omisión:** el subgrafo actual (como `Subgraph(graph:)` en AttributeGraph). El raíz es el padre de lo que se
  crea fuera de todo. El raíz sigue sin poder invalidarse.
- **Subgrafo actual dentro de una regla:** el del propietario de la regla. `run(node)` lo instala y lo restaura al salir
  (`withCurrent` lo sustituye mientras dure). No es observable en SwiftUI: es una decisión de diseño; el efecto es que
  lo que crea un `body` muere con el `body`.
- **Sin API de colección por id** (`ForEach`): el motor da subgrafos; quien los asigna a ids es la capa de vistas, que
  guarda `[ID: Subgraph]`, reutiliza el de un id que sigue y deja intacto lo que no cambia (E8, E19). Se prueba con un
  modelo así en los tests; si la capa de vistas lo repite mucho, se promoverá a API.

## 4. Semántica

**Invalidar `S`** (fuera de una regla): el conjunto es `S` y sus descendientes. Con pila explícita se recoge el
conjunto; **primero** se llama a los avisos, de hijos a padres, con todo aún vivo y legible (el aviso puede leer; si
invalida otro subgrafo, queda en cola); **después** se desprenden las aristas hacia fuera (como M0, pero «fuera» ahora
es «fuera del conjunto»: las lecturas entre miembros del conjunto no marcan nada) y se liberan nodos y subgrafos
(sube la generación, los IDs viejos no resuelven). Los lectores de fuera que leían atributos liberados quedan sucios y
con `pending`, como en M0. Coste lineal en nodos más aristas del conjunto.

**Invalidar `S` dentro de una regla** (`evaluatingNode != noNode`): `S` y sus descendientes pasan a **«cayendo»**:
no se puede crear en ellos (`withCurrent`, `makeSubgraph(parent:)`, `make*` → `precondition`), pero **sus atributos
siguen siendo legibles** hasta el final de la actualización más externa, así la actualización en curso termina de forma
coherente (lo que ya leyó la regla sigue siendo válido). Al terminar la actualización **más externa** (`update` con
`base == 0`) se hace la invalidación completa de arriba. Invalidar dos veces algo ya cayendo no hace nada; algo ya
liberado → `precondition` (como en M0). Si la regla que invalida lee después un atributo del subgrafo cayendo, lo lee
bien; en su siguiente ejecución, al haber perdido la arista, correrá de nuevo y ya no debe leerlo.

**Un propietario que se invalida a sí mismo:** si `S` contiene a la regla en ejecución, no se libera hasta que acabe;
queda sucia y sin valor útil, y nadie podrá leerla después (el ID ya no resuelve).

**Avisos (`observe(_:onInvalidate:)`):** una vez por subgrafo, al invalidar (antes de liberar), de hijos a padres; entre
hermanos, **en orden de creación** (no se promete otro: §2). Si la invalidación estaba diferida, los avisos corren al
final de la actualización más externa, no dentro de ella. Cancelar el token antes evita la llamada. Las observaciones de
atributos de M0 siguen igual.

**Atributos y subgrafos nuevos:** un atributo nace en el subgrafo actual; un subgrafo hijo se desprende de su padre en O(1)
(enlaces de hermano en arreglos, sin arreglos por subgrafo para los hijos).

## 5. Cambios en el motor

1. `SubgraphTable` gana `parents`, `firstChild`, `nextSibling`, `prevSibling` (UInt32, `noSubgraph`) y un indicador
   `dying`/«cayendo». `allocate(parent:)` y `unlink` en O(1).
2. `Graph.invalidate`: recogida del conjunto con pila explícita, avisos, desprendimiento de aristas con «fuera del
   conjunto» según la pertenencia al conjunto que se libera (no la igualdad de propietario ni el indicador global de
   «cayendo», que también incluye otras invalidaciones pendientes), liberación. La cola `deferredInvalidations` se vacía al
   final de la actualización más externa (`update`, y en `read` si no hubo actualización).
3. `run(node)` instala el subgrafo del propietario como actual y lo restaura. Si el propietario está cayendo, instala
   su ancestro vivo incluso si el subgrafo actual ya coincide con el propietario (una lectura anidada del mismo dueño).
4. `observe(_ subgraph:)` y su token, separados de los de atributo.
5. Introspección interna: `parent(of:)`, `children(of:)`, `liveSubgraphCount`.

## 6. Tests (primero; deben fallar antes de implementar)

**Paridad (ronda 7):** cambio de rama: lo nuevo se crea antes de invalidar lo viejo; avisos antes de liberar; hijos
antes que padre; estado de la rama vieja se libera, el de la nueva nace con valor inicial (E7); filas por id con un
`[ID: Subgraph]`: reordenar no crea ni libera nada y no ejecuta reglas, quitar una libera solo la suya, añadir crea una
(E8, E19).
**Unidad:** jerarquía (padre por omisión, explícito, raíz); invalidar el padre invalida a los hijos; invalidar un hijo
no toca al padre ni a los hermanos y lo desprende; lecturas entre miembros del conjunto no ensucian; lectores de fuera
quedan sucios y con `pending`; los IDs viejos de subgrafo no resuelven tras reutilizar la ranura; avisos: una vez,
orden hijos antes que padre, cancelación, lectura permitida dentro del aviso; invalidar dentro de una regla: los
atributos siguen legibles hasta el final, no se puede crear en el subgrafo cayendo, se libera al terminar la
actualización, dos invalidaciones seguidas son una; una regla que crea atributos y subgrafos hijos los crea en su
subgrafo; `withCurrent` dentro de una regla gana; errores de programación con `precondition` (invalidar el raíz, ya
liberado, crear en uno liberado o cayendo).
**Profundidad (principio 1):** 20.000 subgrafos anidados invalidados desde la raíz del árbol; 20.000 hermanos; sin recursión.
**Vida (principio 2):** `nodeCount` y `liveSubgraphCount` vuelven a la base tras rondas de ramas y filas, también si se
invalida dentro de una regla; las ranuras de subgrafo no crecen con altas y bajas continuas.
**Oráculo:** árboles aleatorios (semillas fijas) con crear, invalidar (dentro y fuera de reglas) y leer; un modelo
simple cuenta nodos y subgrafos vivos y qué lectores quedan sucios.
**Rendimiento (release):** los de M0 sin empeorar más de ≈ 10 % (2.000 subgrafos × 5 atributos: 5,9 ms; 500 escrituras:
1,23 ms; actualizar una cadena de 20.000: 5,1 ms); nuevos: invalidar un árbol de 100.000 subgrafos con un atributo cada
uno, y el coste de crear/invalidar 1.000 filas de un `ForEach` por rondas.

## 7. Orden de trabajo

1. Tests rojos (§6). 2. `SubgraphTable` con jerarquía y `makeSubgraph(parent:)`. 3. `invalidate` por conjuntos, avisos y
liberación. 4. Subgrafo actual en `run` y diferido. 5. Verde en depuración y release; medidas; `PLAN-MOTOR.md` (§9). 6. Commit.

## 8. Supuestos, límites y riesgos

- **Medido solo en una versión de macOS (15.7.9).** El orden de `onDisappear` y la liberación son comportamiento de
  SwiftUI, no del motor; el motor ofrece las piezas (aviso antes de liberar, hijos antes que padre) y la capa de vistas
  decide el resto (p. ej. crear lo nuevo antes de invalidar lo viejo).
- **No se promete orden entre hermanos** (medido inverso en una rama y directo en un `ForEach`).
- **Subgrafo actual = el del propietario dentro de una regla:** no medido en SwiftUI; es una decisión de diseño.
- **Atributos de un subgrafo cayendo siguen legibles hasta el final de la actualización:** decisión de diseño; la
  alternativa (`precondition` al leerlos) es más estricta y rompería una regla que ya los había leído.
- **Diferido en el nivel más externo:** una rama puede quedar viva durante toda una actualización larga. Es lo que
  pide la coherencia de la actualización; se anota si la medida del caso real muestra un problema.
- **No cubre** subgrafos compartidos por varios padres, mover un subgrafo de padre, ni invalidar desde otro hilo (principio 6).
- Una lectura nueva dentro de una regla sigue usando la pila nativa (M4).

## 9. Preguntas para el dueño

1. ¿El padre por omisión es el subgrafo actual (propuesto) o ninguno?
2. ¿Aceptas el diferido «legible hasta el final de la actualización más externa» (§4)?
3. ¿Los avisos de invalidación van **antes** de liberar (propuesto, como `onDisappear` antes de liberar el estado) y de
   hijos a padres, sin prometer orden entre hermanos?
4. ¿El subgrafo actual dentro de una regla es el de su propietario?
5. ¿Dejamos la colección por id fuera del motor (propuesto) y la probamos solo con un modelo en los tests?
