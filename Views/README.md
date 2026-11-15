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
- **Faltan** `LocalizedStringKey` en `Text` y `Button`, la selección de `List`, `Button(role:)`, el resto de modificadores, `Environment` y `@Observable` (State/Binding básicos experimentales: ver abajo).
- **`@MainActor`:** SwiftUI aísla `body` y `Button.action` al actor principal; los cascarones no, y por ahora no lo comprobamos.
- Una firma que compila **no** garantiza el mismo comportamiento; el comportamiento sale de las medidas contra SwiftUI (`docs/`).
- Depende del motor para el banco semántico experimental descrito abajo.
- Escrito a mano a partir de la API pública y de la documentación; no se copió ninguna declaración del SDK.

## Conexión experimental al motor

`State` y `Binding` básicos ya se prueban con el motor mediante `ViewGraphScope`, un banco interno de montaje explícito.
`StateScreen.swift` también pasa la comprobación de firmas contra SwiftUI. No hay instalación automática de propiedades
ni renderizador; los ejemplos de pantallas siguen sin montarse por sí solos. `Button` permite invocar su acción desde
el banco, sin implementar entrada de plataforma.

La [prueba vertical](../docs/PRUEBA-VERTICAL-VISTAS.md) registra vida de ramas, poda, profundidad, rendimiento y el contraste
con SwiftUI real. Hay **una discrepancia conocida de recuento de body** al escribir un Binding anteriormente leído.

El [contrato mínimo de Binding](../docs/CONTRATO-BINDING.md) distingue el constructor público con lectura anticipada
mediante get de la proyección `$state`, que no lee al crearse. La actualización dinámica de propiedades y la
reconciliación de hijos continúan pendientes; esta adaptación no completa la paridad de los recuentos de body.
