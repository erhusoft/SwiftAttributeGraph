# Diseño M2: políticas de comparación por atributo (borrador, pendiente de aprobación)

Fecha: 2026-11-14. Parte de [DISENO-M0.md](DISENO-M0.md) §5 y de `parity/ANALISIS.md` §6–§7 (SwiftUI real, macOS
15.7.9). **Estado: propuesta. No se implementa nada hasta que el dueño la apruebe.** Lo que aquí se afirma de SwiftUI
son datos medidos o, si se dice «hipótesis», una regla que explica los datos pero no está probada.

## 1. Qué hay hoy y qué falta

`Comparison` es un `enum` con dos casos (`bits`, `alwaysDifferent`). `NodeTable.comparisons` guarda un `Comparison`
por nodo y `TypedNode.store` llama a `comparison.isEqual(old, new)`, que hace un `switch` y, para `bits`, un `memcmp`
manual de 8 en 8 bytes. Faltan: las políticas `environment` y `stateWrite`, resolver el tipo una vez, y decidir qué
hacer con el relleno entre campos.

## 2. Datos que fijan la especificación (todos medidos, ver la tabla del encargo y `ANALISIS.md` §7)

Sin contradicciones entre el encargo y los resultados guardados en `parity/`. Lo único no medido es lo que lista §5.

| Política | Regla (hipótesis, consistente con todos los datos) |
|---|---|
| `viewValue` | Iguales si todos los bytes son iguales (referencias por identidad). Ignora `==` |
| `environment` | Iguales si los bytes son iguales **o** `==` es verdadero (si el tipo es `Equatable`) |
| `stateWrite` | Tipo trivial: bytes iguales **y** `==` (si es `Equatable`); `Equatable` no trivial: `==`; resto: bytes iguales |

## 3. API y resolución por tipo

```swift
public enum Comparison: Sendable {
    case viewValue          // por defecto; `.bits` queda como alias
    case environment
    case stateWrite
    case alwaysDifferent
}
```

- `Comparison` sigue siendo el selector público y lo que guarda `NodeTable.comparisons` (1 byte por nodo).
- **Resolución una vez, al crear el atributo.** `makeInput`/`makeRule` (genéricos en `Value`) construyen un
  `ValueComparator<Value>`: una estructura con un puntero a función `(borrowing Value, borrowing Value) -> Bool`
  elegido según `(política, ¿Equatable?, ¿trivial?)`. Se guarda en la caja tipada (`TypedNode<Value>`), así el camino
  caliente (`store`) es una llamada indirecta y **no hay `switch` ni cast dinámico**.
- **Cómo saber si `Value` es `Equatable` sin `as? any Equatable` en el camino caliente.** Solo se hace en la creación:
  `Value.self as? any Equatable.Type`, con el existencial abierto en una función genérica auxiliar para construir el
  comparador tipado. Coste: un cast por *atributo creado*, no por escritura. Se mide con «crear 100.000 entradas».
  Se añaden además sobrecargas `Value: Equatable` que evitan incluso ese cast cuando el tipo se conoce en el sitio de
  la llamada (el compilador elige la sobrecarga más específica). **Riesgo:** si el cast de creación pesa, solo las
  sobrecargas estáticas lo evitan; se decide con la medida.
- **Trivial:** `_isPOD(Value.self)` (función de la biblioteca estándar, no pública; se aísla en un archivo y se
  documenta). Es el único detalle que usa un símbolo con guion bajo. Alternativa si Apple lo quita: `Value.self is
  BitwiseCopyable.Type` (más estricto: BitwiseCopyable excluye cosas que `_isPOD` acepta). Se anota en la nota de
  límites.
- **Dónde cuesta cada política (en el camino caliente):**
  - `viewValue` y `stateWrite` sobre no `Equatable`: igual que hoy (comparación de bytes).
  - `environment`/`stateWrite` con `Equatable`: bytes primero (salida rápida si son iguales), `==` después. Para
    `stateWrite` trivial se invierte: `==` solo se llama si los bytes ya son iguales.
- `alwaysDifferent` no cambia.

## 4. Relleno entre campos (paso 4 del encargo)

Problema: un tipo con relleno (`Bool` seguido de `Int`) puede tener bytes de relleno distintos con los mismos campos,
y la comparación de bytes diría «cambió» (se ejecuta de más, nunca de menos). R3-5 no pudo forzar basura en el
relleno de SwiftUI, así que **no se sabe qué hace SwiftUI**.

Plan, en este orden:
1. **Medir en SwiftUI.** Una vista con campos `Bool` + `Int` (y otro con `Int8`, `Int`) cuyo valor se construye leyendo
   de una zona de memoria prerrellena con `0xFF` o `0x00` (`bindMemory(...).pointee`), de modo que los campos sean
   iguales y el relleno distinto. ¿Se salta el `body`? Se comprueba primero, en una prueba aparte, que de verdad el
   relleno llega distinto a la copia (si Swift copia solo los campos, no hay forma de forzar basura y se anota).
2. **Medir con qué frecuencia ocurre en el motor**: lo mismo con el valor guardado por `store` (que copia el valor en
   `Value?`). Si el relleno nunca llega distinto en la práctica, el problema es teórico.
3. **Solo si SwiftUI lo ignora y el motor lo ve:** comparación por campos con una **máscara de bytes** calculada una
   vez al crear el atributo (rangos de bytes que pertenecen a campos, p. ej. con `_forEachField(of:)`, también interno
   de la biblioteca estándar). Tipos sin relleno: máscara completa = el camino actual, sin coste. Si no se puede
   calcular la máscara (tipo opaco, enum con carga), se usa el comparador completo, que es el fallo seguro.

No se construye la máscara sin la medida de 1 y 2.

## 5. Experimentos en SwiftUI real (paso 2) y qué decidirán

Para cada tipo y cada sitio (propiedad de vista, entorno, escritura de `@State`): ¿se salta? Se añade la predicción
de la hipótesis; una discrepancia afina la regla.

| Tipo | viewValue | environment | stateWrite | Qué separa |
|---|---|---|---|---|
| Struct trivial con relleno, bytes de relleno iguales; `==` verdadero | salta | salta | salta | línea base |
| Struct trivial, `==` personalizado que ignora un campo, ese campo cambia | ejecuta | salta | ejecuta (`bytes y ==` falla en bytes) | «bytes y ==» frente a «bytes o ==» con un tipo no flotante |
| Mismo struct pero `==` siempre falso, bytes iguales | salta | salta | ejecuta | si `stateWrite` trivial exige `==` |
| `String` corto en línea (≤ 15 bytes, Swift 6.2/arm64) igual | salta | salta | salta | bytes iguales del literal |
| `String` largo en otro buffer | ejecuta | salta | salta | (ya medido) |
| Struct `Equatable` con una referencia (clase) dentro, mismo objeto / otro objeto igual | salta / ejecuta | salta / salta (`==` lo dice) | salta / ¿?* | si «trivial» es `_isPOD` o «sin referencias» |
| `Optional<String>` (nil→nil, "a" corto→"a", largo en otro buffer) | salta / salta / ejecuta | salta | salta | `Optional` no trivial |
| Enum con carga `String` (igual / otro buffer) | salta / ejecuta | salta | salta | ídem |
| `Array<Int>`: mismo buffer / reconstruido igual | salta / ejecuta | salta / salta (Array es Equatable) | salta / salta | Equatable no trivial vs. identidad |

\* La hipótesis dice «Equatable no trivial: decide `==`», por lo que un struct `Equatable` con una clase dentro y
otro objeto con `==` verdadero **saltaría** en `stateWrite`. Es una de las predicciones que más puede romper.

Cada celda dependerá del tipo de dato elegido; el criterio de aceptación es: la predicción coincide o se anota la
regla nueva con el resultado exacto. Una celda sin dato no se rellena por suposición.

## 6. La sonda comparativa `parity/Compare` (paso 1; local, no versionada)

- Paquete aparte, `.package(path: "../..")` (el motor) y reutiliza el montaje de `SwiftUIProbe` (`NSHostingView` en
  una ventana fuera de pantalla, contadores de `body`).
- Un escenario es un valor `(nombre, sitio, T, T')` con `T: Equatable?`. El mismo escenario se ejecuta:
  - **SwiftUI:** `viewValue` = padre reevalúa y construye `Child(value: T')`; `environment` = valor de entorno que
    pasa de `T` a `T'`; `stateWrite` = `@State var x = T` escrito con `T'`. Se cuenta cuántas veces corre el `body`
    afectado.
  - **Motor:** un atributo con la política del sitio guarda `T`; una regla `body` lee su valor; se escribe `T'`, se
    lee la regla y se cuenta si corrió.
- La salida es una tabla `escenario | SwiftUI | motor | ¿igual?` y un código de salida distinto de cero si hay
  discrepancias. Cada discrepancia es un fallo de paridad.
- **Límite que se declara:** el motor y SwiftUI no ven la misma construcción de `T'` (SwiftUI la construye dentro de
  su propio `body`). Los escenarios con identidad (clases, buffers de `String` y `Array`) se montan para que las dos
  partes usen los mismos objetos guardados.

## 7. Tests (primero, deben fallar antes de implementar)

- `Parity/`: una prueba por fila de §5 y de la tabla de datos, en el sitio correspondiente, con `#expect`.
- `Unit/`: la política se resuelve una vez (contador de llamadas a un `==` personalizado con una sola escritura);
  `Equatable` con `==` mentiroso en cada política; trivial frente a no trivial; `alwaysDifferent`.
- Profundidad y vida: no cambian (no hay recorridos nuevos ni nodos nuevos), pero se vuelve a ejecutar la batería.
- `Performance`: las medidas de M0 de §6 de `PLAN-MOTOR.md`, en release, más «1 millón de escrituras de `Int`,
  `Double`, `String` corto, `String` largo y struct pequeño» por política. **Criterio:** `viewValue` e `Int` no
  empeoran más del ruido de la medida (≈ 10 %) respecto a la línea de base de este Mac (release, 7 ejecuciones):
  500 escrituras 1,27 ms; 50 ciclos 17,7 ms; 100 lotes de 32 escrituras 576 ms; 100.000 entradas 129 ms.

## 8. Orden de trabajo (un commit por pieza)

1. Sonda `parity/Compare` + experimentos de §5 y §4 (sin tocar el motor). Informe de resultados.
2. Si algo contradice las hipótesis: se actualiza esta nota **antes** de implementar y se te avisa.
3. Tests de paridad y de unidad (rojos).
4. `ValueComparator<Value>` y las cuatro políticas; migrar `TypedNode.store`; verde en depuración y release.
5. Relleno: solo si §4 lo pide.
6. Medidas, `PLAN-MOTOR.md` y `swift test -c release -Xswiftc -enable-testing`.

## 9. Riesgos y lo que no se sabe

- **Una sola versión de macOS (15.7.9)** y una ejecución por caso.
- **Símbolos internos de la biblioteca estándar** (`_isPOD`, `_forEachField`): pueden cambiar entre versiones de Swift.
  Se aíslan en un archivo, con una prueba que falla si cambia su comportamiento.
- **Las hipótesis `stateWrite` y `environment` se apoyan en pocos tipos.** §5 las prueba con tipos que las separan.
- **El `==` de un struct depende de quien lo escribe:** el motor llama a **ese** `==`, igual que SwiftUI en
  `environment` y `stateWrite`; en `viewValue` no se llama nunca.
- **Preguntas para el dueño:** (a) ¿`.bits` se mantiene como alias de `.viewValue` o se renombra y se rompe la API
  (aún no hay usuarios)? Propuesta: alias. (b) ¿Se acepta `_isPOD` (símbolo interno) para «trivial»? Propuesta: sí,
  aislado y con prueba. (c) Si el relleno se ignora en SwiftUI, ¿se acepta la máscara basada en `_forEachField`?
