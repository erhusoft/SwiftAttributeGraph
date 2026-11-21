# Encabezados Nativos de AttributeGraph no Consumidos por Frameworks de UI

Fecha: 2026-11-20.

Este documento registra los encabezados y APIs de `AttributeGraph` de Apple que **no** forman parte del runtime de UI (`SwiftUICore`, `SwiftUI`, `AppKit`, `UIKit`) y detalla quién los consume realmente en el ecosistema de desarrollo de Apple y cómo se verifica.

---

## 1. Inventario de encabezados fuera del runtime de UI

De los 33 encabezados del framework nativo `AttributeGraph` (revisión `511cc728141f57dc325753f23898568ccd49c339`), los siguientes no son invocados por la ejecución normal de una app ni por sus frameworks de UI:

| Encabezado | Símbolos principales | Propósito |
|---|---|---|
| **`AGDebugServer.h`** | `AGDebugServerStart`, `AGDebugServerStop`, `AGDebugServerRun`, `AGDebugServerCopyURL` | Servidor HTTP/WebSocket local embebido en el proceso para inspección e introspección remota del grafo. |
| **`AGGraphDescription.h`** | `AGGraphArchiveJSON`, `AGGraphArchiveJSON2`, `AGGraphDescription` | Serialización completa de la topología del grafo a formato JSON y generación de volcados en texto plano. |
| **`AGGraphTracing.h` / `AGTrace.h`** | `AGGraphStartTracing`, `AGGraphStartTracing2`, `AGGraphStopTracing`, `AGGraphAddTrace`, `AGGraphAddTraceEvent` | Motor de trazas de eventos del grafo (integrado con `kdebug`, `os_signpost` y buffers circulares). |
| **`AGTupleType.h`** | `AGNewTupleType`, `AGTupleGetElement`, `AGTupleSetElement`, `AGTupleElementOffset`, `AGTupleElementSize`, `AGTupleSize`, `AGTupleDestroy` | Gestor de memoria dinámica de bajo nivel para tuplas heterogéneas tipo C/C++. |
| **`AGClosure.h`** | `AGClosure`, wrappers de invocación de bloques indirectos | Primitivos C de bajo nivel para invocación de cierres sin metadatos de Swift. |

*(Nota: Los encabezados de metadatos de tipo de atributos `AGAttributeInfo.h`, `AGAttributeType.h` y `AGAttributeTypeFlags.h` corresponden al registro interno de tipos de atributos de vistas, planificado en `C12`).*

---

## 2. Consumidores reales en el ecosistema de Apple

Estas llamadas no existen para que las use una app en producción, sino para alimentar la infraestructura de desarrollo y diagnóstico de Apple:

### A. Xcode View Debugger y Previews
- **`AGDebugServer`** y **`AGGraphArchiveJSON`**: Al pulsar *"Debug View Hierarchy"* en Xcode o al usar el lienzo interactivo de SwiftUI Previews, las herramientas de depuración inyectan comandos o abren un canal con el proceso para invocar `AGGraphArchiveJSON`. Esto genera el árbol estructurado de nodos, valores, dependencias y estados de mutación que Xcode renderiza en el inspector visual 3D.
- **`AGSubgraphBeginTreeElement` / `AGSubgraphSetShouldRecordTree`**: Se activan cuando Xcode o Previews están conectados para registrar la correlación exacta entre los nodos del grafo y las líneas del código fuente del usuario (*source locations*).

### B. Instruments y Profiling del Sistema
- **`AGGraphTracing.h` / `AGTrace.h`**: Son los hooks de telemetría utilizados por los templates de profiling de SwiftUI en **Instruments** (*SwiftUI View Body*, *AttributeGraph Updates*). Emiten eventos de microsegundos sobre cuándo una regla entra en evaluación, qué entradas leyó, cuánto tardó el cálculo y si hubo cortes por igualdad (`cut`).

### C. Scripts de diagnóstico LLDB
- Xcode incluye extensiones de Python para LLDB (diagnóstico interno de salud de runtime) que invocan `AGDebugServer` y `AGGraphDescription` para volcar el estado del grafo cuando el proceso se detiene en un crash o punto de interrupción.

---

## 3. Métodos empíricos de verificación

Para verificar qué binarios llaman a estos símbolos o cómo se disparan:

1. **Vía LLDB dinámico con Xcode**:
   - Poner un breakpoint en cualquier app SwiftUI corriendo desde Xcode:
     ```lldb
     (lldb) b AGDebugServerStart
     (lldb) b AGGraphArchiveJSON
     ```
   - Al activar el inspector de jerarquía de vistas (*Debug View Hierarchy*), el depurador interceptará la ejecución en `AGGraphArchiveJSON` y el backtrace mostrará las librerías inyectadas por Xcode (`libViewDebuggerSupport.dylib` / `DebuggerKit`).

2. **Vía variables de entorno del motor nativo**:
   - Al arrancar una app de prueba en terminal con:
     ```bash
     AG_GRAPH_DEBUG_SERVER=1 ./MiApp
     ```
     o `AG_TRACE=1`, `AttributeGraph` inicia automáticamente el servidor `AGDebugServer` e imprime en consola el puerto de conexión local.

3. **Caché compartida del sistema (`dyld_shared_cache`)**:
   - En macOS, los frameworks del sistema residen consolidados en la dyld shared cache. Las referencias estáticas se constatan en los encabezados `.tbd` del SDK (`MacOSX.sdk/System/Library/PrivateFrameworks/AttributeGraph.framework/AttributeGraph.tbd`), donde los símbolos están exportados públicamente para ser consumidos por los dylibs de soporte de Xcode.
