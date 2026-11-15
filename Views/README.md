# ShellUI: la API compatible con SwiftUI, en cascarones

Primera rebanada del plan [DISENO-API-SWIFTUI.md](../docs/DISENO-API-SWIFTUI.md): **solo la forma de la API**, escrita a mano, sin
lógica de dibujo ni de layout. Un cascarón compila, se parece a SwiftUI por fuera y **dice que no está implementado** cuando se usa
(`ShellCoverage`: un contador por símbolo; en modo estricto, el programa se detiene con el nombre del símbolo).

## Qué incluye (rebanada 1)
`View`, `ViewBuilder` (hasta 4 hijos), `TupleView`, `EmptyView`, `Text` (formas de cadena), `VStack`, `ScrollView`, `padding(_:_:)` y
`padding(_:)`, `Axis`, `Axis.Set`, `Edge`, `Edge.Set` y `HorizontalAlignment`.

## Cómo se comprueba la compatibilidad
`Samples/ColumnScreen.swift` es una pantalla escrita como la escribiría una app. El **mismo archivo** debe compilar contra SwiftUI real
(macOS SDK) y contra los cascarones:

```bash
Views/Scripts/check-compat.sh     # type-check contra SwiftUI real y contra ShellUI
cd Views && swift test            # cobertura y modo estricto
```

Comprobado con una mutación: renombrar un parámetro de `ScrollView` (`showsIndicators` → `showIndicators`) hace fallar la comprobación.

## Límites
- **Faltan** `LocalizedStringKey` en `Text`, el resto de modificadores, `HStack`, `ZStack`, `List`, `ForEach`, entorno y estado.
- Una firma que compila **no** garantiza el mismo comportamiento; el comportamiento sale de las medidas contra SwiftUI (`docs/`).
- No depende del motor todavía; el enlace entre las vistas y el motor es la siguiente etapa.
- Escrito a mano a partir de la API pública y de la documentación; no se copió ninguna declaración del SDK.
