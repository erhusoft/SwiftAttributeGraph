# Diseño M1: corte por versiones (resto y atajos)

Fecha: 2026-11-14. Parte de [PLAN-MOTOR.md](PLAN-MOTOR.md) §3 (M1), derivado de los estudios previos ([ESTUDIO-SALSA.md](../SwiftGraph/docs/ESTUDIO-SALSA.md), [ESTUDIO-SIGNALS.md](../SwiftGraph/docs/ESTUDIO-SIGNALS.md)) y de las decisiones de [DISENO-M0.md](DISENO-M0.md) §1.

## 1. Qué es y qué falta

En **M0** se implementó el corte por versiones básico:
- Cada atributo tiene un número de versión (`table.versions[n]`).
- Cada arista de entrada guarda la versión que vio al ejecutarse (`InputEdge.seenVersion`).
- Cuando una regla se evalúa, si el nuevo valor es igual al anterior según su comparador (`isEqual`), la versión del atributo **no se incrementa**.
- Una regla dependiente sucia verifica sus entradas en orden de lectura: si ninguna entrada cambió de versión respecto a `seenVersion`, la regla dependiente **no se ejecuta** y simplemente se desmarca como limpia (`table.state[n] &= ~dirty`).

**Qué queda para M1 según el criterio de terminado de [PLAN-MOTOR.md](PLAN-MOTOR.md) §3:**
1. **Versión global del grafo (`globalVersion: UInt32`)**:
   Un contador monótono en `Graph` que sube únicamente cuando un valor cambia de verdad en el grafo (en `setValue` o cuando una regla termina con un valor diferente).
2. **Registro de última verificación (`lastVerified`)**:
   Cada ranura guarda la época de `globalVersion` en la que el nodo fue confirmado como limpio y actualizado.
3. **Atajos de corte y verificación rápida**:
   - Si una entrada no está sucia y su `lastVerified == globalVersion`, el lector sabe que dicha entrada ya fue verificada en la época global actual y no requiere comprobaciones redundantes.
   - En dependientes monádicos (una sola entrada) o cuando una regla no incrementa su versión, se acelera la confirmación de limpieza de los lectores sin trabajo redundante en la pila de actualización.
4. **Batería de tests de especificación y medida de rendimiento**:
   - Cadenas, diamantes y abanicos donde una regla intermedia recomputa al mismo valor y ninguno de sus dependientes transitivos corre.
   - Reglas con estado y reanudables que deciden no cambiar de valor.
   - Medición en release del atajo de corte frente a la verificación exhaustiva.

---

## 2. Estructura de datos propuesta

### 2.1 En `Graph`:
```swift
/// Global epoch counter bumped every time a value in the graph changes.
public internal(set) var globalVersion: UInt32 = 1
```

- Se incrementa en `setValue` solo si el valor nuevo no es igual al viejo (`store(value) == true`).
- Se incrementa en `run` (reglas síncronas) y en `advanceResumable` (reglas reanudables) cuando `changed == true`.
- En `batch`, cada mutación efectiva sube la versión global.

### 2.2 En `NodeTable`:
```swift
/// The globalVersion epoch at which each slot was last verified to be up to date.
var lastVerified: [UInt32] = []
```
- Al reservar una ranura en `allocate`: `lastVerified.append(globalVersion)`.
- Al limpiar o completar la evaluación de un nodo `n`: `table.lastVerified[n] = globalVersion`.

---

## 3. Algoritmo y atajos de verificación

En `Graph.update`:
1. **Verificación rápida de entrada limpia**:
   Cuando un marco en la pila de actualización examina `edge.source`:
   - Si `table.state[source] & NodeState.dirty == 0`:
     - Compara `table.versions[source] != edge.seenVersion`. Si coincide y `table.lastVerified[source] == globalVersion`, la arista queda verificada de inmediato sin ninguna comprobación adicional.
2. **Propagación de limpieza en dependientes simples**:
   - Cuando una regla `R` termina su evaluación y **su versión no cambió** (`changed == false`):
     - Para aquellos dependientes directos de `R` que tengan a `R` como **única entrada** y no tengan la bandera `NodeState.pending` ni `stateful`:
       Al no haber cambiado su única entrada, es imposible que el dependiente necesite reevaluarse. Se puede desmarcar su bit `dirty` y marcar `table.lastVerified = globalVersion` inmediatamente. Esto evita apilar y desapilar marcos innecesarios en cadenas profundas cuando el corte se produce en la cabeza.

---

## 4. Criterio de terminado y tests

- **Tests unitarios (`VersionCutTests`)**:
  1. Cadena lineal de reglas: una regla intermedia produce el mismo valor $\to$ ninguna regla aguas abajo se ejecuta.
  2. Grafo en diamante: dos ramas intermedias convergen en una regla final. Las dos ramas recalculan al mismo valor $\to$ la regla final no corre.
  3. Abanico de 50 dependientes: la regla compartida recalcula al mismo valor $\to$ ninguno de los 50 dependientes corre.
  4. Reglas con estado (`StatefulRule`): una regla que no modifica `context.value` preserva su versión y corta la ejecución de sus dependientes.
  5. Reglas reanudables (`ResumableRule`): corte idéntico en el camino reanudable.
  6. Invariante de `globalVersion`: no sube en escrituras idénticas ni en reglas que devuelven el mismo valor; sube en cambios reales.
- **Rendimiento (`PerformanceTests`)**:
  - Medir el tiempo de actualización de una cadena de 20.000 reglas cuando la primera regla corta el cambio.
  - El resultado debe ser igual o mejor que el medido en M0 (18,8 ms en depuración / 0,6 ms en release).
