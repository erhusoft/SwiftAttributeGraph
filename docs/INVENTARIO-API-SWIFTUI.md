# Inventario de la API de SwiftUI (solo nombres)

Fecha: 2026-11-14. Generado en el Mac con `Tools/ApiInventory/inventory.py` a partir de las interfaces públicas del SDK instalado
(**SDK 26.2**, compilador Swift 6.2). Tabla completa: [inventario-api-swiftui.csv](inventario-api-swiftui.csv). Plan:
[DISENO-API-SWIFTUI.md](DISENO-API-SWIFTUI.md).

**Qué contiene:** nombre del símbolo, módulo, clase (struct, protocolo, enum, clase, actor o solo extensiones), un recuento **aproximado** de
miembros públicos y de bloques de extensión, y dos columnas para llevar el trabajo (`status`: todos `pendiente`; `uses_in_sample_apps`: vacía).
**Qué no contiene:** declaraciones, firmas, cuerpos ni documentación; nada copiado del SDK, solo nombres e información de recuento.

## Resumen

1398 entradas de primer nivel (un tipo que aparece en los dos módulos tiene una fila en cada uno).

| Módulo | Clase | Entradas |
|---|---|---|
| SwiftUI | class | 5 |
| SwiftUI | enum | 23 |
| SwiftUI | extension-only | 150 |
| SwiftUI | protocol | 78 |
| SwiftUI | struct | 584 |
| SwiftUICore | actor | 1 |
| SwiftUICore | class | 2 |
| SwiftUICore | enum | 38 |
| SwiftUICore | extension-only | 115 |
| SwiftUICore | protocol | 51 |
| SwiftUICore | struct | 351 |

## Primer corte propuesto (tipos y su peso)

Miembros y bloques de extensión sumados entre los dos módulos. Orientativo: sirve para estimar el tamaño de cada cascarón, no para
definir su firma.

| Tipo | Declarado en | Miembros públicos (aprox.) | Bloques de extensión |
|---|---|---|---|
| `View` | SwiftUICore (protocol) | 41 | 480 |
| `ViewBuilder` | SwiftUICore (struct) | 8 | 3 |
| `Text` | SwiftUICore (struct) | 30 | 28 |
| `VStack` | SwiftUICore (struct) | 2 | 1 |
| `HStack` | SwiftUICore (struct) | 2 | 1 |
| `ZStack` | SwiftUICore (struct) | 2 | 1 |
| `Spacer` | SwiftUICore (struct) | 3 | 0 |
| `ScrollView` | SwiftUI (struct) | 9 | 5 |
| `Button` | SwiftUI (struct) | 8 | 11 |
| `State` | SwiftUICore (struct) | 6 | 2 |
| `Binding` | SwiftUICore (struct) | 33 | 11 |
| `Environment` | SwiftUICore (struct) | 5 | 2 |
| `ForEach` | SwiftUICore (struct) | 27 | 22 |
| `List` | SwiftUI (struct) | 48 | 10 |
| `Image` | SwiftUICore (struct) | 29 | 20 |
| `TextField` | SwiftUI (struct) | 2 | 15 |
| `Toggle` | SwiftUI (struct) | 4 | 5 |
| `Group` | SwiftUICore (struct) | 20 | 13 |
| `Section` | SwiftUI (struct) | 25 | 16 |
| `NavigationStack` | SwiftUI (struct) | 5 | 1 |
| `LazyVStack` | SwiftUICore (struct) | 2 | 1 |
| `Color` | SwiftUICore (struct) | 47 | 18 |
| `Font` | SwiftUICore (struct) | 48 | 7 |
| `Animation` | SwiftUICore (struct) | 48 | 13 |

## Límites de este inventario

- **Recuentos aproximados:** se cuentan líneas públicas dentro de cada bloque; los atributos largos, las macros y los cuerpos pueden
  desviarlos. `View` reúne la mayor parte de los modificadores a través de unos 480 bloques de extensión entre los dos módulos.
- **SDK 26.2, no macOS 15.7.9:** el inventario sale del SDK de Xcode (26.2), mientras que el comportamiento de SwiftUI se midió en
  tiempo de ejecución en **macOS 15.7.9**. Puede haber símbolos en la tabla que no existan en 15.7.9 (disponibilidad por versión),
  y esa columna todavía no se extrae.
- **Falta el uso real:** `uses_in_sample_apps` se rellena cuando haya apps de ejemplo (decisión pendiente del dueño).
- **Otros módulos fuera de la tabla:** `Observation` (`@Observable`), `Combine`, `Charts`, `AppKit`, etc.
- **Regenerar:** `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 -I Tools/ApiInventory/inventory.py docs/inventario-api-swiftui.csv`
  (sobrescribe el CSV y pierde las columnas de trabajo si se editaron a mano: conviene combinarlo antes de volver a ejecutarlo).
