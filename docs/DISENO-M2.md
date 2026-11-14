# Diseño M2: políticas de comparación por atributo (versión 3, pendiente de aprobación)

Fecha: 2026-11-14. Sustituye a las versiones 1 y 2 (commits `1f89f95`, `9d0d5f3`); parte de las rondas 1–4 de
`parity/ANALISIS.md`. **Estado: propuesta. No se implementa nada hasta que el dueño la apruebe.**

## 0. Qué cambió y por qué (versión 3)

La sonda comparativa `parity/Compare` (local, no versionada) ejecuta los mismos escenarios en SwiftUI real y en el
motor. Resultados en `parity/Compare/resultados-macos-15.7.9-compare{2..6}*.txt`, resumen en `HALLAZGOS.md`. Todo
**medido en macOS 15.7.9 (M1)**, tres ejecuciones por caso en un mismo proceso y, aparte, una por proceso nuevo.

1. **Frío frente a caliente.** La primera comparación de un tipo en un proceso («frío») se comporta como «solo
   bytes»; las siguientes («caliente»), no (§3). Las rondas 1–4 midieron sobre todo el caso frío.
2. **Ronda 5 (17 escenarios nuevos): H2 de la versión 2 se refutó en 10 casos** (caliente). Se corrigió a **H3** (§2),
   que explica **134 de 138** casos calientes (46 escenarios × 3 sitios). Los 4 restantes son casos de bytes sin
   especificar (relleno y existenciales), tratados en §6. H3 se ajustó después de ver los datos: explica, no ha
   predicho; §5 propone una ronda 6 con casos nuevos.
3. Con `Comparison.bits` (el de M0) el motor discrepa de SwiftUI en caliente en **11 casos**, todos de «propiedad
   de vista»: `String`, `[Int]`, `String?`, enum con `String`, struct `Equatable` con clase, structs y tuplas mixtos
   con `String` (SwiftUI salta, el motor ejecuta) y `Any`/`any Equatable` (§6).

## 1. Datos medidos (caliente; ¿ejecuta el observador?)

Datos de la versión 2 (29 escenarios) sin cambios; ver `compare5-h3.txt`. Datos nuevos de la ronda 5:

| Caso | viewValue | environment | stateWrite |
|---|---|---|---|
| `Mixed{d: Double, s: String}` no Equatable, `d` 0.0→-0.0 | **ejecuta** | salta | salta |
| ídem, `d` nan→nan | salta | salta | **ejecuta** |
| ídem, `s` largo en otro buffer | **salta** | salta | salta |
| struct anidado `Outer{Mixed, Int}`: `inner.d` -0.0 / `inner.s` otro buffer | ejecuta / salta | salta / salta | salta / salta |
| struct trivial no Equatable `{Double, Int}`: -0.0 / nan→nan | ejecuta / salta | salta / salta | **salta / ejecuta** |
| struct Equatable `{Double, String}`: `d` -0.0 | salta | salta | salta |
| `Double?`: -0.0 / nan→nan | ejecuta / salta | salta / salta | salta / ejecuta |
| enum con carga `Double` (no Equatable): -0.0 | ejecuta | salta | salta |
| tupla `(Double, String)`: -0.0 / `s` otro buffer | ejecuta / salta | salta / salta | salta / salta |
| struct con closure sin captura / con captura que cambia | salta / ejecuta | salta / ejecuta | salta / ejecuta |
| `Any` con `Int` 1→1; `any Equatable` con `Int` 1→1 | salta | salta | salta |

## 2. Hipótesis H3 (caliente)

Sea `T` el tipo del valor del atributo. *Campo a campo(T)* recorre structs, tuplas y enums; en cada hoja decide la
regla de la columna; una referencia a clase se compara por identidad; una hoja sin otra regla (closure) por bytes.

| Sitio | Regla |
|---|---|
| `stateWrite` | *Campo a campo* con **`==` en toda hoja `Equatable`**, también las triviales (`Double`, `Int`): `0.0→-0.0` salta, `nan→nan` ejecuta. Un struct trivial no Equatable se comporta igual: sus `Double` van por `==` |
| `environment` | Bytes iguales **o** `stateWrite` dice igual |
| `viewValue` | `T` trivial → bytes (un `==` propio se ignora). Si no, `T: Equatable` → `==`. Si no, *campo a campo* con hoja trivial por **bytes** y hoja `Equatable` no trivial por `==` |

La diferencia clave entre la versión 2 y esta: en una vista, un `Double` va por bytes **aunque esté dentro de un struct
con un `String`**, y el `String` va por `==`; en `@State` y entorno, también el `Double` va por `==`.

**Sin probar y puede romper H3** (§5): existenciales con otros tipos dinámicos; enums con carga mixta
(`Double` y `String`); `Equatable` de tipos de otros módulos; propiedades `@Binding` y `@Bindable` dentro de la vista.

## 3. El estado frío: decisión del dueño

Medido (una ejecución por proceso, orden viewValue → environment → stateWrite): el **frío es «solo bytes»** en
`viewValue`; `stateWrite` ya sale como en caliente cuando una ventana anterior de otro sitio vio el tipo (si el
primer contacto del proceso con el tipo es la escritura de `@State`, es «solo bytes»: `0.0→-0.0` ejecuta); `environment`
en frío ejecuta una vez con valores **iguales** en muchos tipos (`Int?`, tupla, `String` corto, struct con closure…),
pero no con `Int` en una prueba aislada: **no lo entiendo**. Frío = caliente en 77 de 138 casos; frío = «solo bytes»
en 111.

No sé cuál es el comportamiento «correcto» para paridad. Opciones:

| Opción | Qué significa | Coste |
|---|---|---|
| **A (propuesta)** | El motor reproduce el caso **caliente** (el estacionario). El frío se anota como diferencia conocida | Una sola función por política. El primer fotograma de cada tipo puede ejecutar de más o de menos respecto a SwiftUI |
| B | El motor imita también el frío (primera comparación de cada tipo = solo bits, luego H3) | Estado por tipo y por proceso; reproduce un detalle de implementación de SwiftUI que quizá cambie entre versiones |

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
3. Para *campo a campo*: un **plan de hojas** calculado con `_forEachField(of:)` (también interno): lista de
   `(offset, tamaño, clase de comparación)`, con clase = bytes / `==` (puntero a función por tipo de hoja) /
   identidad. La clase de una hoja depende del sitio (§2): en `viewValue` una hoja trivial va por bytes aunque sea
   `Equatable`; en `stateWrite`/`environment`, por `==`. Los tipos triviales sin plan especial colapsan a un solo
   rango de bytes (el camino actual, sin coste extra). Tipos sin campos accesibles: bytes (se ejecuta de más, no de menos).

**Qué no cubre el plan de hojas (límites declarados):**
- Enums con carga: `_forEachField` no recorre casos de enum. SwiftUI salta el enum con `String` en otro buffer y con
  `Double` -0.0 (por hoja); el motor solo lo reproduciría con un recorrido por metadatos. Se comparan por bytes
  (ejecutan de más con `String`).
- **Existenciales (`Any`, `any P`):** medido que `Any` con `Int` 1→1 hace que `Comparison.bits` dé «cambió» el **100 %
  de las veces** (2.000 de 2.000 escrituras): el contenedor tiene palabras sin inicializar. SwiftUI salta. Hay que
  abrir el existencial y comparar el valor dinámico (hipótesis: con las reglas de §2 sobre su tipo dinámico; sin
  probar con otros tipos dinámicos).
- Closures: bytes (puntero de función + contexto), como mide E2/E18 y la ronda 5. Tipos de otros módulos con campos
  privados.

## 5. Ronda 6 (casos que pueden refutar H3; antes de cualquier código del motor)

| Caso | Pregunta |
|---|---|
| `Any` con `String` largo en otro buffer; con `Int` 1→2; con `Int` y luego `Double` | ¿Se abre el existencial? ¿Cuenta el tipo dinámico? |
| enum con carga mixta `case a(Double), b(String)`: `a(-0.0)` frente a `a(0.0)`; `b` en otro buffer | ¿Hoja a hoja también en enums? |
| `@Binding<Double>` y `@Bindable` dentro de la vista con un `Double` -0.0 | ¿Se comparan como una hoja más? |
| struct con `Double` y `Array<Int>` reconstruido; struct con `Double` y clase (otro objeto) | Otras combinaciones de hojas mixtas |
| tipo de otro módulo (p. ej. `CGPoint`, `CGSize`) con -0.0 | Triviales de la biblioteca: ¿bytes en vista, `==` en `@State`? |
| `Optional<String>` dentro de un struct con `Double` | Anidamiento de `Equatable` no triviales |

Si H3 falla, se actualiza esta nota **antes** de escribir código y se te avisa.

## 6. Relleno entre campos y bytes sin inicializar (paso 4 del encargo)

**Medido en el motor** (`Comparison.bits`, 2.000 escrituras de un valor igual, `parity/Compare`, `swift run Compare padding`):

| Tipo | «Cambió» falso (depuración / release) |
|---|---|
| `Padded{Bool, Int}` (7 bytes de relleno), mismo relleno | 0 / 1 de 2.000 |
| `Padded`, relleno alternando 0x00/0xFF | 0 / 1 de 2.000 |
| tupla `(Bool, Int)` | 0 / 2 de 2.000 |
| `Mixed{Double, String}`, `Int?`, enums con carga | 0 / 0 |
| **`Any` con `Int`, `any Equatable` con `Int`** | **2.000 / 2.000** |

Lectura: el relleno casi nunca llega distinto (los valores pasan por registros) pero **no es nunca**; el existencial
sí falla siempre. En SwiftUI, `Padded` con relleno igual o distinto **salta** (frío y caliente, una ejecución cada
uno); no pude forzar basura en el relleno del valor de la vista, así que **no sé si lo ignora o si no le llegó**.
Decisión propuesta: el plan de hojas de §4 ya compara solo los bytes de cada campo, así que **ignora el relleno por
construcción** y no hace falta una máscara aparte; los tipos sin plan (triviales colapsados) se comparan con un
rango de bytes que excluye el relleno cuando el plan lo conoce.

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

1. (hecho) Ronda 5 en la sonda con el frío por proceso.
2. Ronda 6 (§5). Actualizar esta nota (versión 4 si H3 cambia) y pedir aprobación.
3. Tests rojos (paridad y unidad).
4. `ValueComparator` y las políticas de §2; plan de hojas para *campo a campo*; existenciales.
5. Medidas, `PLAN-MOTOR.md` (hecho, no verificado, límites) y `swift test -c release -Xswiftc -enable-testing`.

## 9. Preguntas para el dueño

1. **Frío o caliente (§3):** ¿propones A (caliente) como especificación?
2. ¿Se aceptan `_isPOD` y `_forEachField` (símbolos internos) aislados en un archivo y con prueba?
3. ¿`.bits` se mantiene como caso público (suelo seguro, sin mirar tipos) y `.viewValue` pasa a ser el valor por
   defecto? Es un **cambio de comportamiento por defecto** respecto a M0 (el motor deja de ejecutar de más con `String` y deja de dar «cambió» siempre con `Any`).
4. ¿Los enums con carga no `Equatable` son un límite aceptable en M2 (comparación por bytes: ejecuta de más)?
