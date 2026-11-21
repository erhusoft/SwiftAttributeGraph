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
