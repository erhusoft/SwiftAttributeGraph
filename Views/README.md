# ShellUI: la API compatible con SwiftUI, en cascarones

Primera rebanada del plan [DISENO-API-SWIFTUI.md](../docs/DISENO-API-SWIFTUI.md): **solo la forma de la API**, escrita a mano, sin
lógica de dibujo ni de layout. Un cascarón compila, se parece a SwiftUI por fuera y **dice que no está implementado** cuando se usa
(`ShellCoverage`: un contador por símbolo; en modo estricto, el programa se detiene con el nombre del símbolo).

## Qué incluye
- **Rebanada 1:** `View`, `TupleView`, `EmptyView`, `Text` (formas de cadena), `VStack`, `ScrollView`, `padding(_:_:)` y `padding(_:)`,
  `Axis`, `Axis.Set`, `Edge`, `Edge.Set` y `HorizontalAlignment`.
- **Rebanada 2:** `HStack`, `ZStack`, `Spacer`, `Button` (con título o con etiqueta), `ForEach` (colección con `id:`, `Identifiable` y rango),
  `List` (contenido, colección `Identifiable`, con `id:` y rango; sin selección), `VerticalAlignment` y `Alignment`.
- **`ViewBuilder`:** hasta 10 hijos, `if`, `if`/`else` y `Optional` como vista.
- Los cierres de fila de `ForEach` y `List` **se guardan y no se llaman**: sin renderizador no se instancian las filas.

## Cómo se comprueba la compatibilidad
`Samples/ColumnScreen.swift` y `Samples/ListScreen.swift` son pantallas escritas como las escribiría una app. Los **mismos archivos** deben
compilar contra SwiftUI real (macOS SDK) y contra los cascarones:

```bash
Views/Scripts/check-compat.sh     # type-check contra SwiftUI real y contra ShellUI
cd Views && swift test            # cobertura y modo estricto
```

Comprobado con mutaciones: renombrar un parámetro de `ScrollView` o de `Spacer`, o cambiar el tipo de alineación de `HStack`, hace fallar la comprobación.

## Límites
- **Faltan** `LocalizedStringKey` en `Text` y `Button`, la selección de `List`, `Button(role:)`, el resto de modificadores, `State`, `Binding`, `Environment` y `@Observable`.
- **`@MainActor`:** SwiftUI aísla `body` y `Button.action` al actor principal; los cascarones no, y por ahora no lo comprobamos.
- Una firma que compila **no** garantiza el mismo comportamiento; el comportamiento sale de las medidas contra SwiftUI (`docs/`).
- No depende del motor todavía; el enlace entre las vistas y el motor es la siguiente etapa.
- Escrito a mano a partir de la API pública y de la documentación; no se copió ninguna declaración del SDK.
