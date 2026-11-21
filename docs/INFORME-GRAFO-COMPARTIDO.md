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
- **Referencia**: `rules.txt` (escenarios R1, R2, R3), `fault.txt`, `lifetime.txt` (caso 2), `hypotheses-round2.txt` (Tarea 1: desensamblado `AG::Graph::input_value_ref_slow`), `node-zero-scrub-evidence.txt`.
- **Descripción**:
  - **Grafos normales independientes (R2)**: Dos grafos creados independientemente mediante `AGGraphCreate` constituyen espacios de nombres completamente aislados. Intentar leer un atributo de un grafo desde el otro aborta con código 134 (`SIGABRT`):
    `accessing attribute in a different namespace: 536`.
  - **Grafos compartidos activos (R1)**: Un handle obtenido con `AGGraphCreateShared` pertenece al mismo espacio de nombres del grafo original; puede leer y enlazar atributos creados desde el otro handle sin error.
  - **Acceso tras liberación o invalidación de la referencia creadora (R3 / Casos E1 c5, c6, c9, c10)**:
    - Si el nodo se evaluó al menos una vez antes de liberar la referencia creadora en un contexto donde el nodo mantiene su subgrafo vivo, el enlace queda materializado y el handle compartido lee el valor sin problemas (`evaluatedBefore=42|readAfter=42`).
    - Si la referencia creadora se destruye o se invalida (`AGGraphInvalidate`) y su subgrafo es invalidado/destruido (`AG::Subgraph::invalidate_now`), el nodo es retornado al heap (`free`). La subsiguiente lectura diferida desde el handle compartido intenta resolver el nodo mediante `input_value_ref_slow`, encontrando que su memoria ha sido puesta a 0 (`[node + 0x28] = 0x0`) por el allocator, provocando la discrepancia de espacio de nombres (`0x0 != contexto_lector`) y abortando con código 134 (`accessing attribute in a different namespace: 536`).
  - **Causa a nivel de ensamblador**:
    En `AG::Graph::input_value_ref_slow` (dirección base `0x1c2c2ae54`, UUID `B8871E2F-044F-31C5-944E-9655E0979E9A`):
    ```asm
    0x1c2c2aed0 <+124>: and    x8, x27, #0xfffffe00
    0x1c2c2aed4 <+128>: ldr    x9, [x21]               ; AG::data::_shared_table_bytes
    0x1c2c2aed8 <+132>: ldr    x8, [x9, x8]            ; x8 = puntero al objeto del slot
    0x1c2c2aedc <+136>: cbz    x8, 0x1c2c2b210
    0x1c2c2aee0 <+140>: ldr    x8, [x8, #0x28]         ; Carga el contexto dueño del nodo [node + 0x28]
    0x1c2c2aee4 <+144>: cmp    x8, x24                 ; Compara contra x24 (contexto actual del lector)
    0x1c2c2aee8 <+148>: b.ne   0x1c2c2b210             ; Discrepancia -> bifurcación al aborto
    0x1c2c2b210 <+956>: str    x27, [sp]
    0x1c2c2b214 <+960>: adrp   x0, "accessing attribute in a different namespace: %u"
    0x1c2c2b21c <+968>: bl     AG::precondition_failure
    ```
    Al destruirse o invalidarse la referencia creadora, su subgrafo se destruye y el nodo se libera; el allocator pone a 0 el bloque de memoria, por lo que `[node + 0x28]` vale `0x0`. Como `0x0 != x24`, la instrucción `b.ne` bifurca al aborto determinista.

- **Conciliación de la aparente contradicción entre `fault.txt` y `native.txt`**:
  - En `fault.txt` (`read-after-first-freed`), una regla `reader` en `S` leía un `input` creado en `G`, pero la lectura se produjo tras liberar `G` (`d = nil`). Como el reader no se evaluó mientras `G` estaba vivo, al liberarse `G` se destruyó su contexto, desencadenando el aborto 134.
  - En `native.txt` (`readAfterLast=11`), el grafo `G` (`d`) **permaneció vivo** durante toda la secuencia de invalidaciones y escrituras (`d.write(10, ...)`, `d.write(11, ...)`). Además, `reader.value` ya había sido evaluado repetidas veces antes de registrar `readAfterLast`. Por tanto, no hubo liberación de `G` ni use-after-free, completándose la lectura limpiamente.

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
  - **Caso de control de fallo de liberación**: Un `CFRelease` manual adicional ejecutado tras `a = nil` sin un `CFRetain` previo produce una doble liberación fatal en CoreFoundation, confirmando que ARC posee y libera exactamente una referencia.
- **Invalidación explícita (`AGGraphInvalidate`)**:
  - Lee el byte en `handle + 0x58` (`is_invalidated`). Si vale 1, retorna inmediatamente sin efecto (operación idempotente).
  - Si vale 0, destruye el contexto invocando a `AG::Graph::Context::~Context()` y fija el byte a 1:
    ```asm
    0x1c2c4045c: tbnz w8, #0x0, 0x1c2c40488 ; Si ya invalidado, retorna
    ...
    0x1c2c40474: bl   AG::Graph::Context::~Context()
    0x1c2c40480: mov  w8, #0x1
    0x1c2c40484: strb w8, [x19, #0x58]
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

2. **Detección temprana de use-after-free sin colisión en el heap (F5)**:
   - **Estado**: Abierto / Hipótesis pendiente.
   - En T3 se demostró como hecho medido que la compuerta `cmp x8, x24` en `+144` evalúa únicamente la igualdad de puntero sin verificar generación ni validez del subgrafo. Sin embargo, no se ha medido que la reutilización accidental por un objeto ajeno sin intervención produzca lecturas silenciosas erróneas (el comportamiento observado fue `EXC_BAD_ACCESS` al acceder a metadatos no inicializados). Queda abierta la verificación de si existe algún escenario donde datos ajenos devuelvan un valor plausible sin abortar.

3. **Verificación de M3 en topologías de múltiples subgrafos**:
   - **Estado**: Abierto.
   - Con el mecanismo de M2 refutado por F1/F2 (el campo `+0x28` es un back-pointer a storage central compartido y no un sello de creador), el Modelo M3 postula que el aborto de c5/c6/c9/c10 se debe a la desasignación del descriptor de rango/subgrafo en el heap y no a un conflicto de namespace formal. Falta mapear la totalidad de subgrafos secundarios creados dentro de un mismo handle.

## 9. Puntos resueltos

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

3. **Validación del modelo de espacio de nombres y ciclo de vida (Experimentos E0, E1, F1-F5)**:
   - **Estado**: Firme.
   - **Referencia**: `Results/shared-graph-macos-15.8.3/e1-e0.txt`, `e1-e0-audit.txt`, `context-identity.txt`, `range-descriptor-identity.txt`, `scrub-controls.txt`, `reuse-hazard.txt`.
   - **Control de Storage (E0, 3 repeticiones)**:
     - Dos grafos independientes creados con `AGGraphCreate()` tienen punteros de almacenamiento central (`*(handle + 0x10)`) distintos (`different=true`) en las 3 repeticiones (100 % estable).
     - Un grafo compartido `S = AGGraphCreateShared(A)` tiene exactamente el mismo puntero de almacenamiento central que `A` (`sameAsA=true`) en las 3 repeticiones (100 % estable).
     - El modelo de almacenamiento central único compartido queda sostenido de forma concluyente.
   - **Matriz de Lectura Cruzada (E1, 3 repeticiones por celda en procesos independientes)**:
     - Auditoría formal (`e1-e0-audit.txt`): Se confirmó que en las celdas cruzadas (c2, c4, c5, c6, c9, c10), el atributo target leído (`w1`) es la regla creada en G (AttributeID 536, `owner = rawG`), y el lector caller (`w2`) es el reader creado en S (AttributeID 1048, `owner = rawS`).
     - **c1 (Evaluado + G vivo + leer por G)**: Termina con éxito limpio (`exit=0`, `value=7`).
     - **c2 (Evaluado + G vivo + leer por S)**: Termina con éxito limpio (`exit=0`, `value=7`).
     - **c3 (No evaluado + G vivo + leer por G)**: Termina con éxito limpio (`exit=0`, `value=7`).
     - **c4 (No evaluado + G vivo + leer por S)**: Termina con éxito limpio (`exit=0`, `value=7`, `hasValueBeforeShare=no`). **Modelo estático de espacio de nombres por handle (denominado "M1" en debates previos) DESCARTADO**.
     - **c5 y c6 (G liberado + leer por S)**: Abortan con `exit=134` (`precondition failure: accessing attribute in a different namespace: 536`).
     - **c9 y c10 (G invalidado-pero-retenido + leer por S)**: Abortan con `exit=134`.
     - **c7 y c8**: Clasificadas formalmente como N/A por construcción (use-after-free en el creador liberado).
   - **Veredicto de Modelo: Descarte de M1 y M2-mecanismo, Adopción del Modelo M3**:
     - **Conducta**: El grafo creador debe permanecer vivo (o sus dependencias haber sido materializadas en vivo) para que el enlace entre handles sea navegable.
     - **Mecanismo F1 y F2 (M2-mecanismo REFUTADO)**: Se midió que `$x24 == *(rawS + 0x10) == *(rawG + 0x10)` (`0x130f05c70`) es el puntero al STORAGE central compartido, y `*(uintptr_t*)(desc + 0x28)` almacena ese mismo puntero central tanto para descriptores originados en G como en S (`descS + 0x28 == descG + 0x28 == x24`). Por tanto, `+0x28` NO es un sello de creador ni discrimina entre handles compartidos.
     - **Dependencia granular de Subgrafo (Prueba de Aislamiento Subgraph-Rule)**:
       - **Referencia**: `Results/shared-graph-macos-15.8.3/subgraph-rule-dependency.txt` (10 repeticiones por celda en procesos aislados, 100 % estables).
       - **Hipótesis comprobada**: Una regla depende del subgrafo que la contiene.
       - **Medición**:
         - `c1` (Invalidar `SG1` con `sg1.invalidate()`, leer `R1` desde `S`): Aborta con `exit=134` (`precondition failure: accessing attribute in a different namespace: 536`) en 10/10 repeticiones (`sg1Valid=false`, `sg2Valid=true`).
         - `c2` (Invalidar `SG1` con `sg1.invalidate()`, leer `R2` en `SG2` desde `S`): Termina con éxito limpio `exit=0` (`value=12`) en 10/10 repeticiones (`sg1Valid=false`, `sg2Valid=true`).
         - `c3` (Control sin invalidar, leer `R1` desde `S`): Éxito limpio `exit=0` (`value=11`) en 10/10 repeticiones (`sg1Valid=true`, `sg2Valid=true`).
       - **Caso aparte (c4 — lectura desde el creador tras invalidación de subgrafo)**:
         - Leer desde el creador `G` una regla (`R1`) cuyo subgrafo (`SG1`) fue invalidado da `exit=139` (`SIGSEGV`), no un aborto controlado (`exit=134`).
         - En las 10 repeticiones el fallo fue `EXC_BAD_ACCESS` y el puntero leído es `[0x0 + 0x1e0]` tras invalidar.
       - **Conclusión de mecanismo**: Invalidar un subgrafo afecta a sus reglas (provocando aborto controlado en lecturas cruzadas desde el compartido en c1, y SIGSEGV en lecturas locales en c4); las reglas de otros subgrafos del mismo creador siguen leyéndose limpiamente desde el compartido (`c2`, `exit=0`, `value=12`).
     - **Modelo M3 (Storage-Paging / Subgraph Lifetime)**: Los atributos se agrupan en descriptores de rango ("páginas") de 512 IDs indexados en la tabla compartida `_shared_table_bytes`. Cuando un handle es invalidado (`AGGraphInvalidate`), sus subgrafos son destruidos y los descriptores liberados al heap; el allocator de macOS pone a cero su memoria. La compuerta `cmp x8, x24` en `+144` evalúa `0x0 != x24` y aborta porque el descriptor está muerto en el heap, no por un choque entre identidades de handles vivos.
     - **Identidad de Creador (F2)**: La verdadera identidad de pertenencia reportada por `AGGraphGetAttributeGraph` reside en un mapa hash central en `storage + 0x90`, indexado por el `context_id` monótono guardado en `desc + 0x30`.
   - **Granularidad de Rango y Radio de Impacto (F3)**:
     - Tres atributos creados en el mismo tramo de 512 IDs (p. ej. IDs 536, 584, 632) comparten exactamente la misma dirección de descriptor de 0x70 bytes en la ranura de la tabla.
     - Si los lectores dependientes fueron evaluados vivos, los tres sobreviven a la invalidación del creador; si no fueron evaluados vivos, los tres abortan simultáneamente al ser liberado su descriptor común. El radio de impacto es el rango/subgrafo completo.
   - **Riesgo Operativo Experimental (F5)**:
     - (i) La compuerta `cmp x8, x24` en `+144` valida únicamente igualdad del puntero de storage: HECHO MEDIDO (se demostró que reasignando la memoria viva y estampando el puntero se elude la guarda).
     - (ii) Que una reutilización accidental por un objeto ajeno produzca lecturas silenciosas erróneas queda como NO REPRODUCIDO (en las pruebas sin restaurar metadata la ejecución falló con `EXC_BAD_ACCESS` en metadatos de Swift).

---

## Función de diseño (hipótesis)

> [!NOTE]
> Esta sección analiza las razones de diseño por las cuales Apple diseñó `AGGraphCreateShared` para usar múltiples entradas a un único grafo central en lugar de un grafo independiente por anfitrión (`Host`). Distingue explícitamente entre indicios estáticos de nombres, hipótesis de diseño y hechos medidos en runtime.

1. **Indicios en símbolos y llamadores (SwiftUI / SwiftUICore)**:
   - **Instancia raíz única (`AGGraphCreate`)**: En SwiftUI existe un único punto de creación del grafo base por proceso, inicializado de forma perezosa y única en `closure #1 in variable initialization expression of static SwiftUI.GraphHost.(sharedGraph in _F9F204BD2F8DB167A76F17F3FB1B3335) : __C.AGGraphRef` (`0x1e767bf4c`). *[INDICIO]*: Sugiere centralización de la memoria reactiva a nivel de aplicación.
   - **Múltiples entradas compartidas (`AGGraphCreateShared`)**: Invocado directamente en `SwiftUI.GraphHost.Data.init() -> SwiftUI.GraphHost.Data` (`0x1e7679388`), que obtiene un handle compartido de `GraphHost.sharedGraph` y crea inmediatamente su propio `_AGSubgraphCreate` (`rootSubgraph`). *[INDICIO]*: Cada subsistema (`ViewGraph`, `GestureGraph`, `CAHostingLayer`) opera como un host con su propia jerarquía de subgrafos locales montada sobre la misma base.
   - **Menciones a reciclaje y control de hosts**: Símbolos como `isHiddenForReuse` (`SwiftUI.GraphHost.isHiddenForReuseDidChange()`), `blockedGraphHosts` (`SwiftUI.(blockedGraphHosts in _F9F204BD2F8DB167A76F17F3FB1B3335)`) y `setNeedsUpdate(mayDeferUpdate:values:)`. *[INDICIO]*: Sugieren mecanismos de reciclaje de anfitriones y coordinación centralizada de transacciones.

2. **Evaluación de hipótesis frente a medidas directas**:
   - **Hipótesis A (Aislamiento — un host no ve los cambios de otro)**:
     - **Estado**: *Descartada / refutada a nivel de datos*.
     - **Fundamento**: Las mediciones directas (E1/c4 y F1/F2) demostraron que los atributos creados en un handle son legibles y evaluables desde otro handle compartido a través del mismo storage central. No existe aislamiento estático de namespace; el aislamiento observable es únicamente estructural a nivel de subgrafos (`rootSubgraph`).
   - **Hipótesis B (Coordinación — los hosts comparten el ciclo de actualización)**:
     - **Estado**: *No se observa propagación eager con el patrón medido (coordinación abierta / delegada)*.
     - **Referencias**: `Results/shared-graph-macos-15.8.3/memory-slope-and-coordination.txt` (escritura simple desde G y S) y `Results/shared-graph-macos-15.8.3/coordination-update-paths.txt` (caminos de actualización U1–U4, 10 repeticiones por caso en procesos aislados).
     - **Medición con contador de evaluaciones en caminos de actualización**:
       * **Caso U1 (`AGGraphSetNeedsUpdate` sobre G tras escribir)**: Tras escribir e invocar `SetNeedsUpdate(G)`, `evalCount` permanece en 1; asciende a 2 solo al leer explícitamente desde S.
       * **Caso U2 (`AGGraphSetUpdateCallback` registrado en G)**: Tras escribir y tras `SetNeedsUpdate(G)`, `evalCount` permanece en 1 y el callback no se dispara (0 disparos); asciende a 2 solo al leer.
       * **Caso U3 (Escritura en regla con mutación en evaluación)**: Tras la ejecución de la regla escritora en G, `evalCount` de la regla lectora R en S permanece en 1; asciende a 2 solo al leer explícitamente.
       * **Caso U4 (`AGSubgraphUpdate` sobre el subgrafo lector en S)**: Tras escribir e invocar `AGSubgraphUpdate`, `evalCount` permanece en 1; asciende a 2 solo al leer.
     - **Conclusión de lo medido**: En todos los caminos medidos (escritura directa y casos U1–U4), la propagación en AttributeGraph es estrictamente bajo demanda (pull / lazy); no se observa propagación eager automática entre handles a nivel del grafo.
     - **[INFERENCIA (no medida directamente en AttributeGraph)]**: La coordinación del ciclo de renderizado y transacciones entre múltiples hosts vive por encima, en la capa de `SwiftUI` (mediante `ViewRendererHost`, `CAHostingLayer`, transacciones de runloop y `ObservableObject`), y no como un mecanismo intrínseco de despacho eager dentro de `AttributeGraph`.
   - **Hipótesis C (Reutilización de memoria — los hosts reducen el coste de memoria por host)**:
     - **Estado**: *Apoyada y cuantificada mediante pendiente de regresión lineal*.
     - **Referencia**: `Results/shared-graph-macos-15.8.3/memory-slope-and-coordination.txt` (10 repeticiones por escala con N = 1.000, 10.000 y 100.000 instancias en procesos aislados).
     - **Medida (Pendiente OLS de RSS)**:
       - Grafos independientes (`AGGraphCreate`): pendiente de **9.068,47 ± 1,19 bytes / grafo** ($R^2 = 1,000000$).
       - Handles compartidos (`AGGraphCreateShared`): pendiente de **144,02 ± 0,76 bytes / handle** ($R^2 = 0,999987$).
     - **Conclusión**: El coste incremental real de un handle compartido es de solo ~144 bytes frente a ~9,07 KB por grafo independiente (**98,41 % de ahorro marginal de memoria**, una reducción de ~63x). Esto confirma que el propósito primario del diseño es permitir la creación masiva de puntos de entrada ligeros compartiendo el almacenamiento reactivo central (`_shared_table_bytes`, hash tables y buffers de ejecución).

3. **Medición de enrutamiento e interoperabilidad (Soporte a las hipótesis de diseño)**:
   - **Referencia**: `Results/shared-graph-macos-15.8.3/routing-and-interop.txt` (10 repeticiones por caso en procesos aislados, 100 % estables).
   - **Cadena de enrutamiento medida (`AGGraphGetAttributeGraph` $\rightarrow$ `AGGraphGetContext`)**:
     - En el desensamblado de `SwiftUI.GraphHost.graphInvalidation(from:)` (`0x1e767b934`) se observó la secuencia de llamadas `_AGGraphGetAttributeGraph` (`+0x1c`), `_AGGraphGetContext` (`+0x2c`) y `_AGGraphGetValue` (`+0x98`).
     - **Hecho medido en runtime**: Asignando punteros de contexto distintos con `AGGraphSetContext` (`0xdead1111` en `G` y `0xbeef2222` en `S`), en 10/10 repeticiones (`exit=0`):
       * Para la entrada creada en `G` (`ID 536`), `AGGraphGetAttributeGraph` devuelve `rawG` y `AGGraphGetContext` devuelve `0xdead1111` (tanto dentro de la regla lectora, como fuera y en el callback `onInvalidation`).
       * Para la regla `R` creada en `S` (`ID 1048`), `AGGraphGetAttributeGraph` devuelve `rawS` y `AGGraphGetContext` devuelve `0xbeef2222` (tanto antes como después de invalidar).
     - Esto confirma que cada atributo conserva su vínculo con el handle específico que lo creó y permite recuperar sin ambigüedad el contexto de usuario asociado a ese handle.
   - **Enrutamiento de extremo a extremo de la invalidación (`AGGraphSetInvalidationCallback`, `cntG` vs `cntS`)**:
     - **Referencia**: `Results/shared-graph-macos-15.8.3/invalidation-routing.txt` (10 repeticiones por caso en procesos aislados, `exit=0`).
     - **Topología simple de una sola regla hoja sin salidas (`input -> R`)**: Escribiendo en `input` tanto desde `G` como desde `S`, ningún contador sube ni antes ni después de leer (`cntG=0, cntS=0` en 10/10 repeticiones). En nativo, un nodo terminal sin aristas de salida (`outputs` vacío) no dispara el callback de invalidación. En este caso puntual el enrutamiento no se activa.
     - **Topología con arista de salida en `S` (`input -> R -> R2`)**: Escribiendo en `input` tanto desde `G` (10/10) como desde `S` (10/10), **`cntS` sube a `1` inmediatamente tras la escritura (sin leer `R`) y `cntG` permanece en `0`**; tras la lectura posterior desde `S`, los contadores se mantienen en `cntS=1, cntG=0`. **Enrutamiento confirmado**: cuando el atributo en el handle consumidor tiene salidas dependientes, el aviso de invalidación se entrega de forma inmediata y exclusiva al callback del handle `S` que contiene la regla lectora, sin disparar el de `G`.
   - **Interoperabilidad medida entre hosts (`I1` vs `I2`)**:
     - **Caso I1 (Dos handles compartidos `S1` y `S2` sobre el mismo storage de `G`)**: Una regla en `S2` lee entradas de `G` y `S1` (`v1=30`), se modifican las entradas y se relee (`v2=300`), terminando con `exit=0` en 10/10 repeticiones.
     - **Caso I2 (Control con dos grafos independientes `G1` y `G2`)**: Una regla en `G2` intenta leer una entrada de `G1` y aborta en las 10 repeticiones (10/10) con código de salida `134` (`SIGABRT`) y mensaje `precondition failure: accessing attribute in a different namespace: 536` (confirmado fila a fila en `Results/shared-graph-macos-15.8.3/routing-and-interop.txt` y `Results/shared-graph-macos-15.8.3/i2-check.txt`), validando la comparación controlada entre `I1` e `I2`.
     - **Delimitación metodológica**: Lo medido apoya empíricamente que compartir el storage evita el aborto de espacio de nombres al cruzar lecturas entre handles. No obstante, que el motivo de diseño de Apple para `AGGraphCreateShared` sea permitir que varios hosts (AppKit, ventanas, gestos) lean el mismo namespace sin abortar se mantiene como **hipótesis de diseño**, no como hecho demostrado.
   - **Hipótesis sobre fuentes externas (AppKit y OpenSwiftUI)**:
     - La hipótesis sobre el choque de espacios de nombres entre AppKit y OpenSwiftUI por usar instancias separadas de `GraphHost.sharedGraph` queda registrada como **no verificada, pendiente de lectura de la fuente**.

---

## Conclusiones para la arquitectura del motor

- **Modelo idéntico al de SwiftUI**: SwiftUI mantiene un único estado central `AG::Graph` por proceso y entrega handles ligeros (`AGGraphCreateShared`) a cada consumidor de UI.
- **Implementación en SwiftAttributeGraph**: Cualquier soporte futuro de grafos compartidos en el motor debe seguir este patrón: un grafo central poseedor de los atributos, y handles de contexto que incrementan/decrementan el recuento del grafo central (`+0x1a4`), manteniendo IDs secuenciales independientes (`+0x20`) y liberando limpiamente sus recursos mediante ARC/CFRelease sin incurrir en dobles liberaciones.
