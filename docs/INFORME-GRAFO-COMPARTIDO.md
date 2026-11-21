# Informe: `AGGraphCreateShared` (`Graph(shared:)`)

Estado: medido en nativo (macOS 15.8.3). Sin implementar en el motor. Todas las afirmaciones corresponden a medidas de sondas nativas (`NativeProbe`), desensamblado en `lldb` o mediciones sobre aplicaciones SwiftUI instrumentadas.

---

## 1. Qué es

- **Estado**: Firme.
- **Referencia**: `native.txt`, `handle-count.txt`, `hypotheses-round2.txt` (Control A y C), `hypotheses-round4.txt`.
- **Descripción**:
  - `AGGraphCreateShared` devuelve un nuevo handle de CoreFoundation (`CFGetTypeID` coincide exactamente con `AGGraphGetTypeID`).
  - La referencia en Swift (`AttributeGraph.Graph`) ocupa 8 bytes en memoria: es el puntero directo al objeto handle.
  - El handle encapsula un contexto local propio (`handle + 0x10`) que apunta al estado compartido único del grafo subyacente (`AG::Graph*`).
  - No copia estructuras ni datos del grafo; opera como un handle de acceso concurrente sobre el mismo motor reactivo.

---

## 2. Qué comparte y qué no

- **Estado**: Firme.
- **Referencia**: `native.txt`, `lifetime.txt` (casos 1, 3a, 3b), `hypotheses.txt` (Hipótesis 1 y 4).
- **Qué comparte**:
  - **Estado del grafo (`AG::Graph*`)**: Todos los handles apuntan al mismo puntero de estado en `handle + 0x10`.
  - **Nodos y dependencias**: Hereda la totalidad de los nodos y enlaces en ambos sentidos (los creados antes o después de la creación del handle compartido, y desde cualquiera de las referencias).
  - **Recuento de nodos**: Ambos handles observan exactamente el mismo `nodeCount` (`nodesFirst=2|nodesShared=2`).
  - **Lectura reactiva y mutaciones**: Lee valores y observa mutaciones escritas desde el primer handle (`readFromShared=7`, `afterWriteInFirst=9`).
  - **Contador de referencias del estado (`state + 0x1a4`)**: Gestionado conjuntamente por todos los contextos vinculados; sube con cada nuevo handle y baja con cada invalidación/destrucción.
- **Qué no comparte**:
  - **Identidad del handle**: Son objetos y punteros distintos (`sameReferenceBits=false`).
  - **Identificador de contexto (`handle + 0x20`)**: Cada handle recibe su propio ID monótono generado por `AGMakeUniqueID` (`idG1=2`, `idS1=3`, `idS2=4`).
  - **Contexto de usuario (`AGGraphSetUserContext`)**: Es privado de cada handle; fijar el contexto de usuario en una referencia mantiene a la otra en `nil` (`ctx|c2UserContextAfterSettingC1=nil`).
  - **Contexto de evaluación (`AG::Graph::Context`)**: Cada handle tiene su propio struct `Context` en memoria (`handle + 0x10`).

---

## 3. Reglas de espacio de nombres

- **Estado**: Firme.
- **Referencia**: `rules.txt` (escenarios R1, R2, R3), `fault.txt`, `lifetime.txt` (caso 2), `hypotheses-round2.txt` (Tarea 1: desensamblado `AG::Graph::input_value_ref_slow`).
- **Descripción**:
  - **Grafos normales independientes (R2)**: Dos grafos creados independientemente mediante `AGGraphCreate` constituyen espacios de nombres completamente aislados. Intentar leer un atributo de un grafo desde el otro aborta con código 134 (`SIGABRT`):
    `accessing attribute in a different namespace: 536`.
  - **Grafos compartidos activos (R1)**: Un handle obtenido con `AGGraphCreateShared` pertenece al mismo espacio de nombres del grafo original; puede leer y enlazar atributos creados desde el otro handle sin error.
  - **Acceso tras liberación de la referencia creadora (R3 / Caso 2)**:
    - Si el nodo se evaluó al menos una vez antes de liberar la referencia creadora, el enlace queda materializado y el handle compartido sobrevive leyendo el valor sin problemas (`evaluatedBefore=42|readAfter=42`).
    - Si el nodo **no** fue evaluado antes de liberar la referencia creadora, la lectura diferida desde el handle compartido aborta con código 134 (`accessing attribute in a different namespace: 536`).
  - **Causa a nivel de ensamblador**:
    En `AG::Graph::input_value_ref_slow` (dirección base 0x1c2c2ae54):
    ```asm
    0x1c2c2aee0: ldr  x8, [x8, #0x28]  ; Carga el contexto dueño del nodo [node + 0x28]
    0x1c2c2aee4: cmp  x8, x24          ; Compara contra x24 (contexto actual de la lectura)
    0x1c2c2aee8: b.ne 0x1c2c2b210      ; Discrepancia -> bifurcación al aborto
    0x1c2c2b210: str  x27, [sp]
    0x1c2c2b214: adrp x0, "accessing attribute in a different namespace: %u"
    0x1c2c2b21c: bl   AG::precondition_failure
    ```
    Al destruirse la primera referencia sin evaluar el nodo, el contexto registrado en el nodo (`[node + 0x28]`) deja de ser válido o no coincide con el contexto activo `x24` del lector, disparando la trampa `b.ne`.

---

## 4. Uso en SwiftUI

- **Estado**: Firme (medido en runtime con apps SwiftUI de prueba instrumentadas).
- **Referencia**: Trazas de runtime SwiftUI en macOS 15.8.3 (análisis de arranque, ventanas y sheets).
- **Descripción**:
  - **Un único grafo base por proceso**: Al arrancar la aplicación se produce exactamente una llamada a `AGGraphCreate` (dentro de un `dispatch_once` que inicializa el `sharedGraph` global del proceso).
  - **Un handle compartido por cada host**: Cada elemento de presentación UI (menús del sistema, ventanas principales, inspectores, sheets modales) recibe un handle creado con `AGGraphCreateShared`.
  - **Métricas observadas**:
    - Con 1 ventana abierta: 9 handles compartidos activos (6 para la jerarquía de menús, 1 para la ventana principal, 1 para la infraestructura de `sharedGraph` y auxiliares).
    - Con 2 ventanas abiertas: 10 handles compartidos activos (+1 por la nueva ventana).
    - Apertura de un modal/sheet: suma exactamente +1 handle compartido.
    - Todos los handles observados en el proceso comparten el mismo puntero al estado central `AG::Graph` (p. ej. `0x3f606700` idéntico en los 9 handles).
  - **Propagación en jerarquía**: Un sheet que consume un `Binding` del padre se actualiza exactamente 1 vez por cada mutación (5 evaluaciones para 5 emisiones de valor).

---

## 5. Coste

- **Estado**: Firme.
- **Referencia**: Pruebas de microbenchmarking y estrés de la sonda nativa (`NativeProbe`).
- **Descripción**:
  - **Latencia de creación**:
    - Crear un grafo independiente (`AGGraphCreate`): ~0,70 µs.
    - Crear un handle compartido (`AGGraphCreateShared`): ~0,14 µs (~5 veces más rápido, al reutilizar el estado existente).
  - **Estrés volumétrico y profundidad**:
    - Creación de 1.000.000 de handles compartidos sobre el mismo grafo: 248 ms en total sin fallos de memoria.
    - Cadena de profundidad de 200.000 handles compartidos derivados en cascada (compartido de compartido): 19 ms en total sin desbordamiento de pila ni errores.

---

## 6. Liberación y propiedad

- **Estado**: Firme.
- **Referencia**: `lifetime.txt` (casos 1, 3a, 3b, 4, 5), `hypotheses-round4.txt`, `hypotheses-round5.txt`, desensamblado lldb de `AGGraphInvalidate` y `AG::Graph::Context::~Context`.
- **Propiedad y ARC (Ronda 4 y Ronda 5)**:
  - Cada handle devuelto por `AGGraphCreateShared` nace con un retain count de CoreFoundation igual a 1 (`rcInitial = 1`).
  - La variable envoltorio de Swift (`AttributeGraph.Graph`) asume la posesión de esa referencia única.
  - Al ejecutar `a = nil`, Swift ARC libera exactamente **una** referencia de CoreFoundation (1 $\rightarrow$ 0):
    - *Comprobación en vivo*: Si se incrementa con `CFRetain(rawA)` a 2, tras `a = nil` el retain count pasa limpiamente a 1 (`rcAfterARCDrop = 1`), y un `CFRelease` posterior completa la destrucción limpia (código de salida 0).
  - **Reproducción del fallo de `CFRelease` manual (Ronda 5, 3 repeticiones)**:
    - **Caso A (Control de fallo)**: Crear handle con `AGGraphCreateShared`, ejecutar `a = nil` (sin retain previo) y después llamar a `CFRelease(rawA)`.
      - Repeticiones 1, 2 y 3: **Falla 100 % de forma estable con exit=139** (`SIGSEGV` en `CF_IS_OBJC` / `objc_release`).
    - **Caso B (Contraste sin ARC)**: Crear handle con `AGGraphCreateShared` y llamar a `CFRelease(rawA)` directamente sin `a = nil`.
      - Repeticiones 1, 2 y 3: **Termina 100 % limpio con exit=0**. Demuestra que el handle de `AGGraphCreateShared` soporta `CFRelease` como cualquier objeto CoreFoundation válido.
    - **Caso C (Contraste balanceado con retain)**: Crear handle, `CFRetain`, `a = nil`, y `CFRelease`.
      - Repeticiones 1, 2 y 3: **Termina 100 % limpio con exit=0**.
    - *Conclusión*: El fallo fatal al invocar `CFRelease` tras soltar la variable Swift es inequívocamente un **segundo release sobre un objeto ya destruido (Double Free)**.
- **Mecanismo de invalidación (`AGGraphInvalidate`)**:
  - Desensamblado en `lldb`:
    1. Lee la marca de 1 byte en `handle + 0x58`. Si no es cero, retorna inmediatamente (`tbnz w8, #0x0`).
    2. Si es 0, invoca `AG::Graph::Context::~Context()` pasando el puntero al contexto en `handle + 0x10`:
       ```asm
       add x0, x0, #0x10
       bl  AG::Graph::Context::~Context()
       ```
    3. Al volver del destructor, escribe `1` en `handle + 0x58`:
       ```asm
       mov  w8, #0x1
       strb w8, [x19, #0x58]
       ```
- **Destrucción del contexto (`AG::Graph::Context::~Context()`)**:
  - Obtiene el puntero `AG::Graph*` en `[handle + 0x10]` y decrementa atómicamente el contador en `state + 0x1a4`:
    ```asm
    ldr  x0, [x19]
    ldr  w8, [x0, #0x1a4]
    subs w8, w8, #0x1
    str  w8, [x0, #0x1a4]
    ```
  - Si el contador llega a cero (`b.ne` no salta), destruye el grafo central y libera su memoria:
    ```asm
    bl  AG::Graph::~Graph()
    bl  operator delete
    ```

---

## 7. Identificador `+0x20`

- **Estado**: Firme.
- **Referencia**: `lifetime.txt` (caso 4: `idG1=2|idS1=3|idS2=4`), `hypotheses.txt` (Hipótesis 1: desensamblado de `AGGraphCreateShared`, `AG::Graph::Context::Context` y `AGMakeUniqueID`).
- **Descripción**:
  - El campo en `handle + 0x20` **no** es un recuento de referencias decreciente ni un contador de handles activos. Es un **identificador secuencial único y monótono**.
  - **Prueba en ensamblador (`lldb`)**:
    1. En `AGGraphCreateShared` (0x1c2c403bc), pasa `handle + 0x10` al constructor de contexto `AG::Graph::Context::Context(AG::Graph&)`.
    2. En `AG::Graph::Context::Context` (0x1c2c26f64):
       ```asm
       0x1c2c26f74: mov  x19, x0          ; x19 = handle + 0x10
       0x1c2c26f7c: bl   AGMakeUniqueID   ; Obtiene nuevo ID único
       0x1c2c26f84: str  x0, [x19, #0x10] ; Escribe en (handle + 0x10) + 0x10 = handle + 0x20
       ```
    3. En `AGMakeUniqueID` (0x1c2c26470):
       ```asm
       0x1c2c26470: adrp x8, AGMakeUniqueID::counter
       0x1c2c26478: mov  w9, #0x1
       0x1c2c2647c: ldadd x9, x0, [x8]   ; Incremento atómico global (ldadd)
       0x1c2c26480: ret
       ```
  - Cada contexto nuevo que se crea en el proceso adquiere el siguiente número entero global. Al liberar o invalidar el handle, `+0x20` permanece inmutable (`idS1AfterS2Drop=3`).

---

## 8. Lo que sigue abierto

1. **Dependencia cruzada entre ventanas a nivel directo de grafo**:
   - **Estado**: Abierto.
   - Las pruebas multicelular de SwiftUI con dos ventanas emplearon `ObservableObject` para la sincronización entre vistas (capa de binding de SwiftUI). Falta verificar y medir cómo reacciona un nodo de grafo puro dependiente conectado directamente a través de dos handles en distintos hilos de UI sin la intermediación de `Combine` / `ObservableObject`.

---

## 9. Puntos abiertos resueltos

1. **Significado y ruta de error de la marca `+0x58`**:
   - **Estado**: Firme.
   - **Referencia**: `Results/shared-graph-macos-15.8.3/e1-e0.txt` (`probe-58`, desensamblado LLDB).
   - **Significado**: Es el campo booleano `is_invalidated` (1 byte) del handle `AGGraphStorage`.
   - **Ciclo de vida medido**:
     - Creado en `AGGraphCreateShared`: inicializado a `0` (`0x1c2c403f4: strb wzr, [x19, #0x58]`).
     - Al invalidar (`AGGraphInvalidate`): pasa a `1` (`0x1c2c40480: strb w8, [x19, #0x58]`).
     - En subsiguientes llamadas a `AGGraphInvalidate`: guardia de idempotencia (`0x1c2c4045c: tbnz w8, #0x0`), retorna de inmediato sin destruir el contexto de nuevo.
   - **Guardia de finalización**: El finalizador CoreFoundation de la clase (`klass->finalize`, `0x1c2c42eac`) comprueba `ldrb w8, [x0, #0x58]`. Si es `1` (ya invalidado), retorna inmediatamente sin destruir el contexto; si es `0`, ejecuta `AG::Graph::Context::~Context()`. Esto previene dobles destrucciones de contexto entre `AGGraphInvalidate` y `CFRelease`.
   - **Rutas de error**: Si `handle + 0x58 == 1`, las siguientes funciones saltan a su bloque frío y abortan el proceso con `AG::precondition_failure("invalidated graph")`:
     - `AGGraphCreateShared` (`0x1c2c40378`)
     - `AGGraphSetNeedsUpdate` (`0x1c2c406fc`)
     - `AGGraphStopTracing` (`0x1c2c42d14`)
     - `AGGraphSyncTracing` (`0x1c2c42d58`)
     - `AGGraphCopyTracePath` (`0x1c2c42d9c`)
     - `AGGraphDescription` (`0x1c2c42e00`)

2. **Causa raíz del fallo en la prueba de dos hosts con dos grafos independientes**:
   - **Estado**: Firme.
   - **Referencia**: `Results/shared-graph-macos-15.8.3/rules.txt` (`two-hosts`, `two-hosts-cross`).
   - **Causa raíz**: Error en el código de la sonda, **no** un bug de AttributeGraph ni un fallo por tener múltiples grafos en el proceso.
   - **Mecanismo**: La sonda original evaluó `AttributeGraph.Subgraph(graph: s1).apply { ... }` sin retener la instancia de `Subgraph` en una variable local viva. Al terminar la sentencia, ARC destruyó el `Subgraph` (`AG::Subgraph::clear_object()`), disociando el contexto del nodo (`[node + 0x28] = 0`). Al leer `.value`, `AGGraphGetValue` pasó un contexto nulo `0x0` a `AG::Graph::value_ref`, intentando desreferenciar `[0x0 + 0x1e0]` (`SIGSEGV` / exit code 139).
   - **Verificación**: Reteniendo el `Subgraph` en una variable (`let root1 = AttributeGraph.Subgraph(graph: s1)`), `two-hosts` ejecuta 100 % limpio (exit code 0):
     `two-hosts|s1ReadsG1=10|s2ReadsG2=20|nodesS1=2|nodesS2=2|nodesG1=2|nodesG2=2`
     Y el caso de lectura cruzada no permitida entre grafos (`two-hosts-cross`) dispara el aborto de seguridad esperado de espacio de nombres (exit code 134).

3. **Validación del modelo de espacio de nombres y ciclo de vida (Experimentos E0 y E1 con repetición)**:
   - **Estado**: Firme.
   - **Referencia**: `Results/shared-graph-macos-15.8.3/e1-e0.txt` y `Results/shared-graph-macos-15.8.3/e1-e0-repeats.txt`.
   - **Control de Storage (E0, 3 repeticiones)**:
     - Dos grafos independientes creados con `AGGraphCreate()` tienen punteros de almacenamiento central (`handle + 0x10`) distintos (`different=true`) en las 3 repeticiones (100 % estable).
     - Un grafo compartido `S = AGGraphCreateShared(A)` tiene exactamente el mismo puntero de almacenamiento central que `A` (`sameAsA=true`) en las 3 repeticiones (100 % estable).
     - El modelo de almacenamiento central único compartido queda **sostenido con repetición**.
   - **Matriz de Lectura Cruzada (E1, 3 repeticiones por celda en procesos aislados)**:
     - Se evaluó una regla (`rule`) no evaluada antes de compartir (`hasValueBeforeShare=no`) y evaluada antes de compartir (`hasValueBeforeShare=yes`, verificado mediante `AGGraphHasValue`).
     - **c4 (No evaluado + G vivo + leer por S)**: En las 3 repeticiones termina con éxito limpio (`exit=0`, `value=7`, `hasValueBeforeShare=no`). Esto **descarta el modelo M1 con repetición** (el espacio de nombres no está restringido de forma estática al handle que lee).
     - **c2 (Evaluado + G vivo + leer por S)**: En las 3 repeticiones termina con éxito limpio (`exit=0`, `value=7`, `hasValueBeforeShare=yes`).
     - **c5 y c6 (G liberado + leer por S)**: En las 3 repeticiones abortan con `exit=134` (`precondition failure: accessing attribute in a different namespace: 536`).
     - **c9 y c10 (G invalidado-pero-retenido + leer por S)**: Con el objeto CF de G retenido en memoria (`CFRetain`) pero su contexto destruido vía `AGGraphInvalidate` (`gAlive=invalidated-retained` en la telemetría), en las 3 repeticiones abortan con `exit=134`.
   - **Conclusión de Modelo**:
     - Queda **respaldado con repetición el modelo M2** (sello y ciclo de vida ligado al `Context` del creador).
     - La estabilidad es del 100 % (3 de 3 repeticiones idénticas en todas las celdas).
     - No es la liberación del bloque de memoria de CoreFoundation lo que invalida el enlace entre grafos, sino la destrucción del `Context` (`AG::Graph::Context`) del handle creador. Mientras dicho contexto permanezca vivo, cualquier handle compartido derivado del mismo almacenamiento puede leer o evaluar perezosamente sus atributos.

---

## Conclusiones para la arquitectura del motor

- **Modelo idéntico al de SwiftUI**: SwiftUI mantiene un único estado central `AG::Graph` por proceso y entrega handles ligeros (`AGGraphCreateShared`) a cada consumidor de UI.
- **Implementación en SwiftAttributeGraph**: Cualquier soporte futuro de grafos compartidos en el motor debe seguir este patrón: un grafo central poseedor de los atributos, y handles de contexto que incrementan/decrementan el recuento del grafo central (`+0x1a4`), manteniendo IDs secuenciales independientes (`+0x20`) y liberando limpiamente sus recursos mediante ARC/CFRelease sin incurrir en dobles liberaciones.
