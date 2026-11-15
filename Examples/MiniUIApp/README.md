# MiniUIApp

Mini aplicación de demostración en macOS (`AppKit` + `SwiftUI` + `SwiftAttributeGraph`) que muestra en tiempo real:

- Evaluación perezosa y corte por versión (`Map` + `parityRuns`).
- Redirección dinámica de `IndirectAttribute` (`setSource`).
- Ciclo de vida de un `Subgraph` montado/desmontado leído con `WeakAttribute`.
- Métricas en vivo del motor (`nodeCount`, `edgeCount`, `liveSubgraphCount`, `recalculationCount`).

![MiniUIApp preview](miniui-preview.png)

## Cómo ejecutarla

```bash
# Abrir la ventana interactiva en macOS:
swift run --package-path Examples/MiniUIApp

# Verificar el flujo completo por línea de comandos:
swift run --package-path Examples/MiniUIApp MiniUIApp --verify

# Renderizar una captura PNG fuera de pantalla:
swift run --package-path Examples/MiniUIApp MiniUIApp --snapshot /tmp/miniui-preview.png
```
