# MiniUIApp

Mini aplicación de demostración en macOS (`AppKit` + `SwiftUI` + `SwiftAttributeGraph`) que muestra en tiempo real:

- Evaluación perezosa y corte por versión (`makeMap` + `parityRuns`).
- Redirección dinámica de `IndirectAttribute` (`setSource`).
- Ciclo de vida de un `Subgraph` montado/desmontado leído con `WeakAttribute`.
- Métricas en vivo del motor (`nodeCount`, `edgeCount`, `liveSubgraphCount`, `recalculationCount`).

![MiniUIApp preview](miniui-preview.png)

## Cómo ejecutarla

```bash
# Abrir la ventana interactiva en macOS:
swift run --package-path Examples/MiniUIApp

# Ejecutar la suite automatizada (verifica contadores, teardown intermedio y final, batches, paridad y estrés):
swift test --package-path Examples/MiniUIApp

# Verificar el flujo completo por línea de comandos (debug o release):
swift run --package-path Examples/MiniUIApp MiniUIApp --verify

# Medir latencia del motor + puente en release (mediana, mín y máx de 9 rondas x 1000 ops):
swift run -c release --package-path Examples/MiniUIApp MiniUIApp --bench

# Comparar ejecuciones reales de `body` en SwiftUI (`@Observable` ingenuo vs `@Observable` bien escrito vs `SwiftAttributeGraph`):
swift run -c release --package-path Examples/MiniUIApp MiniUIApp --parity

# Estresar 2.000 subgrafos, 1.000 escrituras multi-fuente (9 rondas) y una `LazyVStack` real en SwiftUI:
swift run -c release --package-path Examples/MiniUIApp MiniUIApp --stress

# Renderizar una captura PNG fuera de pantalla:
swift run --package-path Examples/MiniUIApp MiniUIApp --snapshot /tmp/miniui-preview.png
```

## Qué mide cada prueba (motor/puente vs SwiftUI real)

### 1. Medido en el motor y el puente (sin layout ni render de SwiftUI)
- `--bench` (9 rondas × 1.000 interacciones mixtas en release): **mediana `0.0090 ms/op`** (mín `0.0087 ms`, máx `0.0128 ms`), con ratio `1.00 publishes/interaction` y `1.00 dirtyNotifications/interaction`. **Esta cifra mide únicamente el motor y `EngineBridge.flushUI()`, no el coste completo de un frame ni el layout de SwiftUI.**
- `--stress` (9 rondas en release):
  - `2.000` subgrafos (`peak`: `4.000` nodos, `2.000` aristas, `2.001` subgrafos; tras desmontar las `1.000` filas pares: `2.000` nodos, `1.000` aristas, `1.001` subgrafos; tras desmontar todo: `0` nodos, `0` aristas, `1` subgrafo raíz): **mediana `5.86 ms`** (mín `5.12 ms`, máx `9.02 ms`).
  - `1.000` escrituras multi-fuente en `250` lotes `withBatch`: `250` notificaciones `dirty` y `251` ejecuciones combinadas, **mediana `0.45 ms`** (mín `0.40 ms`, máx `0.67 ms`).

### 2. Medido con SwiftUI real (`NSHostingView` + `NSWindow`)
- `--parity` (secuencia de 7 pasos):
  - `@Observable` ingenuo (`parityText` calculado): `counter=4, alt=2, parity=4, indirect=4, detail=3` (**total `17`** `body` runs).
  - `@Observable` bien escrito (`parityText` almacenado y asignado solo al cambiar): `counter=4, alt=2, parity=2, indirect=4, detail=3` (**total `15`** `body` runs).
  - `SwiftAttributeGraph` (`AttributeBox` + `makeMap`): `counter=4, alt=2, parity=2, indirect=4, detail=3` (**total `15`** `body` runs).
  - La diferencia en `parity` (`4` vs `2`) depende de cómo se escriba el modelo en `@Observable`; `SwiftAttributeGraph` aplica ese corte por igualdad automáticamente en nodos derivados sin asignaciones manuales.
- `--stress` (`LazyVStack` de `2.000` filas): al montar corren `14` `body` de fila visibles (motor `3.00 ms`, SwiftUI `28.97 ms` incluyendo `RunLoop` de bombeo); al mutar `5` filas solo re-ejecutan sus `body` esas `5` filas (motor `0.112 ms`, SwiftUI `21.89 ms`); al desmontar la lista el grafo vuelve a `0` nodos y `0` aristas (motor `2.09 ms`, SwiftUI `21.40 ms`).
