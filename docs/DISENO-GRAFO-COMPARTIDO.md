# Diseño: grafo compartido (`AGGraphCreateShared`, `Graph(shared:)`)

Estado: diseño, sin implementar. Responde a la entrada `AGGraphCreateShared` de `NativeProbe` y a la tabla de nombres
(`docs/TABLA-NOMBRES.md` en SwiftUICore).

## 1. Qué medimos en Apple (sonda nativa, macOS 15.8, 2026-11-20)

- Una regla de un grafo compartido lee una entrada creada en el primer grafo: devuelve 7. **Los atributos se leen entre
  grafos compartidos.**
- La referencia que devuelve `AGGraphCreateShared` **no es el mismo puntero** que la original (`sameGraphPointer=false`).
  **Comparten estado, no identidad.**
- El contexto actual (`AGSubgraphGetCurrentGraphContext`) es `nil` dentro de la regla. Por tanto este diseño no depende de
  ese valor.

## 2. Estado actual

`Graph` es una clase con unas sesenta propiedades mutables (tablas de nodos y subgrafos, pila de actualización, contadores,
observadores, caches). Un atributo lleva el `graphTag` de su grafo, y `GraphRegistry` resuelve tag → `Graph`. Hoy hay una
identidad por grafo, y el tag se libera en `deinit`.

## 3. Decisión propuesta: separar estado e identidad

Tres piezas:

1. **`GraphStorage`** (interna, `final class`): contiene todo el estado mutable y el `graphTag`. Es el único dueño de las
   tablas. Libera el tag en su `deinit`, no en el de la referencia pública.
2. **`Graph`** (pública): una referencia ligera a un `GraphStorage`. `Graph()` crea un storage nuevo. `Graph(shared:)`
   crea otra referencia al **mismo** storage. Dos referencias son distintas (como en Apple), pero comparten estado.
3. **Estado de evaluación compartido**: `frames`, `evaluatingNode`, `currentSubgraph` y la pila de actualización viven en
   el storage, no en la referencia. Así una regla de la referencia B que lee un atributo de la referencia A se registra
   en la misma pila, como en Apple (la pila de actualización es por hilo, no por referencia).

Consecuencias:
- `GraphRegistry` mapea tag → storage (no → referencia). `Graph.graph(of:)` devuelve una referencia (la primera que se
  creó para ese storage, guardada como referencia débil).
- `ThreadLocalGraph` guarda la referencia activa; el trabajo real pasa por el storage.
- El tag se reutiliza solo cuando muere el último `GraphStorage`, nunca mientras viva una referencia.

## 4. Riesgos y coste

- **Rendimiento del camino caliente.** Hoy `table` es una propiedad directa de `Graph`. Con el storage habría un
  indirecto más en cada lectura de atributo. Mitigación: que las extensiones internas sigan usando `table` a través de
  propiedades calculadas con `_modify`, y **medir** antes y después con las pruebas de rendimiento en release (regla 4
  de AGENTS.md). Si la pérdida supera el umbral, se usa `unowned(unsafe)` o se copia el puntero de tabla en la referencia.
- **Un solo hilo por storage** (principio 6). Dos referencias del mismo storage deben usarse desde el mismo hilo; se
  comprueba con `assertOwnThread()`, como ya se hace.
- **Vida.** Un storage vive mientras vivan sus referencias. La destrucción de subgrafos y atributos no cambia.

## 5. Fases (cada una con TDD y oráculo)

1. **Medir el coste**: añadir un test de rendimiento de lectura caliente (release) y apuntar la línea base.

   **Línea base (fase 1, release, mediana de 7, tres pasadas):** lecturas de entrada 103,4 ms por 10 M (10,3 ns cada una); lecturas de regla ya calculada 108,0 ms por 10 M (10,8 ns cada una). Variación entre pasadas menor del 0,5 %. Prueba: `HotReadPerformanceTests`.
2. **Separar el storage** sin cambiar la API: `Graph` pasa a referencia sobre `GraphStorage`, con propiedades calculadas
   que delegan. Todas las pruebas existentes deben pasar. Medir de nuevo: si la pérdida es mayor del 5 %, revisar el paso 3.
3. **`Graph(shared:)`**: segunda referencia al mismo storage. Tests: lectura de un atributo entre referencias (valor 7 en
   el oráculo), `===` distinto, y liberación del tag solo con la última referencia.
4. **Oráculo**: escenario `graph-shared-read` (lectura entre referencias, identidad distinta). El contexto actual se mide
   aparte y no entra en este paso.

## 6. Qué queda fuera

- Hilos: un storage sigue siendo de un solo hilo.
- `currentGraphContext`: nil en todas las medidas; se decide cuando haya un caso con valor.
- Trazas de las referencias compartidas: fuera de la v1.

## 7. Preguntas abiertas

- ¿La referencia que devuelve `graph.graph(of:)` debe ser siempre la original, o la última usada? Propuesta: la original.
- ¿Hace falta `GraphStorage` público? Propuesta: no; solo `Graph` es pública.


## 8. Resultado del primer intento de la fase 2 (2026-11-20)

Se movieron a un objeto interno los contadores y banderas que no tienen trampas (transacciones, actualizaciones, cambios, nodos creados, observadores, lote, vaciado), con propiedades calculadas `_read`/`_modify`. Medido en release: lecturas de entrada 114,3 ms (+10,5 %) y de regla 117,4 ms (+8,7 %), frente a la línea base de 103,4 y 108,0 ms. Supera el límite del 5 %, así que se revirtió. Conclusión: el camino de lectura toca estos campos, y el indirecto cuesta más de lo previsto. La fase 2 necesita otra forma: por ejemplo, que el camino caliente siga con las tablas en el propio grafo y solo se mueva lo que no se toca al leer, o un diseño con la referencia al objeto interno copiada en campos locales.

## 9. Propuesta revisada (tras la sección 8): handle reenviador

Restricción medida: el camino de lectura no puede pagar un indirecto (límite del 5 %, sección 8).

Propuesta: `Graph(shared:)` devuelve una referencia **distinta** que guarda la referencia al grafo original y reenvía sus
llamadas públicas a él. El grafo original no cambia: sus propiedades siguen dentro, y su camino de lectura queda igual. Solo
la referencia compartida paga el reenvío.

- Identidad: distinta (como mide Apple), estado: el del original.
- Lectura entre referencias: funciona, porque el grafo activo durante la evaluación es el original.
- Coste: cero para el grafo original; una llamada de reenvío para la referencia compartida.
- Riesgo principal: hay que reenviar **cada** método público. Un método olvidado no falla al compilar, y operaría sobre un
  estado vacío. Mitigación: una prueba que llame a cada método público por la referencia compartida y compare con el original.
- Fase 4 (oráculo `graph-shared-read`): se mantiene.

Pendiente de decisión del dueño del proyecto: aceptar esta forma (handle reenviador) frente a mover el estado completo
(sección 8, que supera el límite de rendimiento).

## 10. Quién llama a `AGGraphCreateShared` (corrección)

- El análisis guardado en `ag_callsites.json` decía que `SwiftUI.GraphHost.Data.init` la llama. **No se confirma**: en el
  desensamblado completo del binario de SwiftUI no hay ninguna llamada a `AGGraphCreateShared`, y el símbolo
  `GraphHost.Data.init` no aparece en él.
- SwiftUICore: ninguna llamada directa en su desensamblado.
- AttributeGraph: solo su definición (desensamblado leído en la sección 9 de la sesión).

Conclusión: no hay un uso confirmado de `AGGraphCreateShared` en SwiftUI ni en SwiftUICore. La propuesta del handle
reenviador no depende de ese uso, pero tampoco queda justificada por él. Antes de implementarla hay que encontrar un
llamador real, o decidir la forma sin ese dato.

## 11. Búsqueda de referencias (2026-11-20)

- **Importaciones de SwiftUI**: el binario importa 73 símbolos de AttributeGraph. `AGGraphCreateShared` **no** está entre
  ellos (la búsqueda sí encuentra otros de creación, como `AGGraphCreateIndirectAttribute`). SwiftUI no puede llamarla
  directamente.
- **Desensamblado de SwiftUI y de SwiftUICore**: ninguna referencia por nombre C, nombre Swift ni nombre mangled.
- **AttributeGraph**: solo su definición.

Conclusión: en los binarios que tenemos, nadie llama a `AGGraphCreateShared`. El grafo compartido, por tanto, no es
necesario para SwiftUI en macOS 15.8. Recomendación: **aplazar las fases 2 a 4** (el handle reenviador incluido) y
dejarlas documentadas, en lugar de implementarlas sin un uso real que las justifique.

## 12. Clientes de AttributeGraph en la caché de macOS 15.8 (2026-11-20)

Lista de `ipsw dyld imports` (imágenes que cargan AttributeGraph) y su importación de `AGGraphCreateShared`:

| Cliente | Símbolos AG importados | `AGGraphCreateShared` |
|---|---|---|
| SwiftUI | 73 | no |
| SwiftUICore | (sin binario extraído; desensamblado sin llamadas) | no |
| AXCoreUtilities | 3 | no |
| Charts | 27 | no |
| _MapKit_SwiftUI | 29 | no |
| _SwiftData_SwiftUI | 1 | no |
| PhotosSwiftUICore | 2 | no |
| WorkflowUICore | 9 | no |
| NotificationCenter (app) | no extraíble de la caché | pendiente |

La cadena `AGGraphCreateShared` sí aparece en la tabla de símbolos de la caché (atribuida a Virtualization y libobjc), pero
Virtualization no importa ningún símbolo de AttributeGraph, así que esa atribución es solo un nombre global de la caché.

Conclusión: ningún cliente del sistema que hemos podido comprobar importa `AGGraphCreateShared`. Puede ser parte de la API
exportada para otros clientes (de terceros o herramientas internas), o un uso por búsqueda dinámica (`dlsym`) que no se ve
en las importaciones. No está resuelto, y el handle reenviador sigue aplazado.
