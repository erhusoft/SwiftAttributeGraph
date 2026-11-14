# Diseño M2: políticas de comparación por atributo (versión 2, pendiente de aprobación)

Fecha: 2026-11-14. Sustituye a la versión 1 de esta nota (commit `1f89f95`), que se basaba en las rondas 1–4 de
`parity/ANALISIS.md`. **Estado: propuesta. No se implementa nada hasta que el dueño la apruebe.**

## 0. Qué cambió y por qué

La sonda comparativa `parity/Compare` (local, no versionada; resultados en `parity/Compare/resultados-macos-15.7.9-compare2.txt`
y `-compare3.txt`, resumen en `parity/Compare/HALLAZGOS.md`) ejecuta los mismos 29 escenarios en SwiftUI real y en el
motor, tres veces cada uno en el mismo proceso. Resultado, **medido en macOS 15.7.9 (M1)**:

1. **La primera comparación de un tipo en un proceso («frío») da otro resultado que las siguientes («caliente»).**
   No es una cuestión de tiempo (igual con 1,5 s de espera inicial). Las rondas 1–4 se midieron en procesos nuevos,
   así que midieron sobre todo el caso frío. Mi propia sonda reprodujo la discrepancia con la sonda original (R3-2:
   `0.0 → -0.0` en `@State` ejecuta en un proceso nuevo y salta cuando el tipo ya se había comparado antes).
2. **En caliente, la comparación no es «solo bits».** Las vistas comparan con `==` los campos `Equatable` no triviales
   (`String`, `[Int]`, `String?`, structs `Equatable`), y por bytes los tipos triviales (`Double`, `Int`, structs sin
   referencias, aunque tengan un `==` propio).
3. Con la regla H2 de §2 las **87 combinaciones** (29 escenarios × 3 sitios) coinciden con SwiftUI en caliente. Con
   `Comparison.bits` actual el motor discrepa en 5 (todas de «propiedad de vista» con `String`, `[Int]`, `String?`,
   enum con `String` y struct `Equatable` con clase: SwiftUI salta, el motor ejecuta).

Límite que hay que decir claro: **H2 se ajustó después de ver los datos**; explica, no ha predicho. §5 propone los
casos nuevos que pueden refutarla.

## 1. Datos medidos (caliente; cada celda: ¿ejecuta el observador?)

| Caso | viewValue | environment | stateWrite |
|---|---|---|---|
| `Int` 1→1 / 1→2 | salta / ejecuta | salta / ejecuta | salta / ejecuta |
| `Double` 1.0→1.0 | salta | salta | salta |
| `Double` 0.0→-0.0 | **ejecuta** | salta | **salta** |
| `Double` nan→nan (mismos bits) | salta | salta | **ejecuta** |
| `String` largo, mismo buffer / otro buffer / contenido distinto | salta / **salta** / ejecuta | salta / salta / ejecuta | salta / salta / ejecuta |
| `String` corto igual / distinto | salta / ejecuta | salta / ejecuta | salta / ejecuta |
| clase: mismo objeto / otro igual (no Equatable) | salta / ejecuta | salta / ejecuta | salta / ejecuta |
| `[Int]` mismo buffer / reconstruido igual | salta / **salta** | salta / salta | salta / salta |
| `Int?` 1→1; `String?` nil→nil, corto igual, largo mismo buffer | salta | salta | salta |
| `String?` largo otro buffer | **salta** | salta | salta |
| enum con `String` (no Equatable): corto igual / largo otro buffer | salta / **salta** | salta / salta | salta / salta |
| tupla `(Int, Int)` igual | salta | salta | salta |
| struct trivial con relleno, campos iguales | salta | salta | salta |
| struct trivial, `==` ignora `b`, `b` cambia | **ejecuta** | salta | salta |
| struct trivial, `==` siempre verdadero, bytes distintos | **ejecuta** | salta | salta |
| struct trivial, `==` siempre falso, bytes iguales | salta | salta | **ejecuta** |
| struct `Equatable` con clase: mismo objeto / otro con `==` verdadero | salta / **salta** | salta / salta | salta / salta |

Negrita = lo que contradice la tabla del encargo o las rondas 1–4 (en esos casos las rondas midieron el caso frío).

**Frío frente a caliente** (primera comparación del tipo en un proceso nuevo, medida aparte con 5 repeticiones seguidas):
`@State` con `0.0 → -0.0`, `==` que ignora un campo, `==` siempre verdadero y `String` largo otro buffer: **ejecuta
en frío, salta en caliente**; `==` siempre falso con bytes iguales: **salta en frío, ejecuta en caliente**. En frío
todo se comporta como «solo bits». Propiedad de vista en frío: `String`/`[Int]`/`String?`/enum/struct con clase, otro
buffer: ejecuta, luego salta. Entorno en frío: algunos casos con valores iguales ejecutan una vez (p. ej. `Int?`
1→1, tupla, struct con relleno), pero `Int` 1→1 no: **causa sin explicar**.

## 2. Hipótesis H2 (la regla que explica los 87 casos en caliente)

Sea `T` el tipo del valor del atributo.

| Sitio | Regla |
|---|---|
| `stateWrite` | `T: Equatable` → `==`. Si no: *estructural(T)* |
| `environment` | `T: Equatable` → bytes iguales **o** `==`. Si no: *estructural(T)* |
| `viewValue` | `T` trivial (POD) → bytes. Si no, `T: Equatable` → `==`. Si no: *estructural(T)* |
| *estructural(T)* | hoja `Equatable` → `==`; hoja trivial → bytes; referencia a clase → identidad; struct, tupla o enum → campo por campo |

Lectura: en una vista, el valor es un struct de campos; si todo el struct es trivial se comparan sus bytes (por eso
`Double` por bits y un struct trivial ignora su `==`); si no lo es, cada campo `Equatable` se compara con `==`.
Eso explica a la vez `String` en otro buffer (salta) y `Double` por bits (ejecuta con -0.0).

**Lo que no sabemos y puede romper H2** (§5): un struct *mixto* (no trivial, con un `Double` y un `String`: ¿el
`Double` va por bytes o por `==`?); structs anidados; closures y existenciales; enums con carga `Double`; si el
`Equatable` de un campo se ve solo cuando el struct entero no es trivial.

## 3. El estado frío: decisión del dueño

No sé cuál es el comportamiento «correcto» para paridad. Opciones:

| Opción | Qué significa | Coste |
|---|---|---|
| **A (propuesta)** | El motor reproduce el caso **caliente** (el estacionario). El frío se anota como diferencia conocida | Una sola función por política. El primer fotograma de cada tipo puede ejecutar de más o de menos respecto a SwiftUI |
| B | El motor imita también el frío (primera comparación de cada tipo = solo bits, luego H2) | Estado por tipo y por proceso; reproduce un detalle de implementación de SwiftUI que quizá cambie entre versiones |

La propuesta es A, y que la sonda registre el frío por separado (columna aparte) para detectar si cambia en otra
versión de macOS. Los tests de paridad del motor usarán el valor caliente.

## 4. Diseño en el motor

**API.** `Comparison` queda como selector público:

```swift
public enum Comparison: Sendable {
    case viewValue          // por defecto; `.bits` queda como alias deprecado
    case environment
    case stateWrite
    case alwaysDifferent
    case bits               // solo bytes, sin mirar el tipo (lo que había en M0); útil para pruebas y como suelo seguro
}
```

**Resolución una vez, al crear el atributo.** `makeInput`/`makeRule` construyen un `ValueComparator<Value>`: un
puntero a función `(borrowing Value, borrowing Value) -> Bool` guardado en la caja tipada (`TypedNode<Value>`). El
camino caliente (`store`) hace una llamada indirecta: ni `switch` ni cast. Al crear (no al escribir) se calcula un
**plan** a partir de `Value`:

1. `_isPOD(Value.self)` (símbolo interno de la biblioteca estándar; se aísla en un archivo y lleva una prueba que
   falla si cambia su comportamiento).
2. `Value.self as? any Equatable.Type` y existencial abierto en una función genérica auxiliar, solo en la creación.
   Sobrecargas estáticas `Value: Equatable` evitan incluso ese cast cuando el tipo se conoce en la llamada.
3. Para *estructural*: un **plan de hojas** calculado con `_forEachField(of:)` (también interno): lista de
   `(offset, tamaño, clase de comparación)`, con clase = bytes / `==` (puntero a función por tipo de hoja) /
   identidad. Tipos sin campos accesibles se comparan por bytes (el fallo seguro: se ejecuta de más, no de menos).
   Los tipos triviales colapsan a un solo rango (el camino actual, sin coste extra).

**Qué no cubre el plan de hojas (límites declarados, se miden y se anotan):** enums con carga (`_forEachField` no
recorre casos de enum; el enum con `String` de §1 salta en SwiftUI y el motor solo lo reproduciría si es `Equatable`
o si se escribe un recorrido por metadatos), existenciales, closures (bytes: puntero de función + contexto, como
mide E2/E18) y tipos de otros módulos con campos privados.

## 5. Siguiente paso: ronda 5 con la sonda (antes de cualquier código del motor)

Casos nuevos que **pueden refutar H2**; cada uno con la predicción de H2 (viewValue / stateWrite / environment):

| Caso | Predicción de H2 |
|---|---|
| struct mixto `{ d: Double, s: String }`, `d` 0.0→-0.0, `s` igual | viewValue: ejecuta si `d` va por bytes, salta si por `==`; **no predicho** (es la pregunta) |
| el mismo con `s` en otro buffer y `d` igual | viewValue: salta |
| struct anidado no trivial con un `Double` y un `String` | igual que el mixto |
| struct no `Equatable` con `Double` y `Int` (trivial) | viewValue bytes; stateWrite bytes (no `Equatable`: estructural: trivial → bytes) |
| `Optional<Double>`, `Double?` 0.0→-0.0 | `Equatable` no trivial: viewValue `==` (salta), stateWrite `==` |
| enum con carga `Double` (no `Equatable`), 0.0→-0.0 | estructural: trivial → bytes: ejecuta |
| tupla `(Double, String)` | como el struct mixto |
| closure sin capturas / con captura | bytes: salta / ejecuta (E2/E18) |
| existencial `any Equatable` con `Int` | no predicho |
| (frío) los casos anteriores en un proceso nuevo, uno por proceso | solo bytes en frío (para detectar si H2-frío es «bytes») |

Si H2 falla, se actualiza esta nota **antes** de escribir código y se te avisa.

## 6. Relleno entre campos (paso 4 del encargo)

Todavía **sin datos**: la sonda no puede forzar bytes de relleno distintos, porque al cargar un struct desde memoria
Swift copia los campos (por registros) y no el relleno (`bytesEq=true` en los dos casos de `Padded`). Es el mismo
límite que R3-5. Plan: (1) probar si algún camino (valor pasado por memoria, `initialize(to:)` sobre un bloque
rellenado con `0xFF`) conserva el relleno; (2) si ninguno lo hace, concluir que **el relleno no es observable en
código normal**, mantener `memcmp` y anotar el límite; (3) solo si se consigue un caso observable en SwiftUI y en el
motor, calcular la máscara con el plan de hojas de §4 (que ya excluye el relleno por construcción).

## 7. Tests y rendimiento

- `Parity/`: una prueba por fila de §1 (caliente) y por fila de §5, con el sitio y la política correspondientes. El
  frío no entra en los tests (opción A), pero se documenta.
- `Unit/`: la política se resuelve una vez (contador de llamadas a un `==` personalizado en una sola escritura); cada
  regla de §2 con un tipo que la separa de las demás; `alwaysDifferent`; `bits` conserva el comportamiento de M0.
- Profundidad y vida: no cambian; se repite la batería.
- Rendimiento: los de M0 más «1 millón de escrituras» de `Int`, `Double`, `String` corto, `String` largo y struct
  pequeño por política. **Criterio:** `Int` y tipos triviales no empeoran más del ruido (≈ 10 %) respecto a la línea de
  base de este Mac en release (500 escrituras 1,27 ms; 50 ciclos 17,7 ms; 100 lotes de 32 escrituras 576 ms;
  100.000 entradas 129 ms).

## 8. Orden de trabajo

1. Ronda 5 en la sonda (§5), con el frío medido en procesos nuevos. Informe.
2. Actualizar esta nota con lo que resulte (versión 3 si H2 cambia) y pedir aprobación.
3. Tests rojos (paridad y unidad).
4. `ValueComparator` y las políticas de §2; plan de hojas para *estructural*.
5. Medidas, `PLAN-MOTOR.md` (hecho, no verificado, límites) y `swift test -c release -Xswiftc -enable-testing`.

## 9. Preguntas para el dueño

1. **Frío o caliente (§3):** ¿propones A (caliente) como especificación?
2. ¿Se aceptan `_isPOD` y `_forEachField` (símbolos internos) aislados en un archivo y con prueba?
3. ¿`.bits` se mantiene como caso público (suelo seguro, sin mirar tipos) y `.viewValue` pasa a ser el valor por
   defecto? Es un **cambio de comportamiento por defecto** respecto a M0 (el motor deja de ejecutar de más con `String`).
4. ¿Los enums con carga no `Equatable` son un límite aceptable en M2 (comparación por bytes: ejecuta de más)?
