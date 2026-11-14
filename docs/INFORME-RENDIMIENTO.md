# Informe de Rendimiento y Auditoría de Alto Rendimiento

Fecha: 2026-11-14  
Plataforma: Mac M1, macOS 15.7.9, Apple Swift 6.2.4 (Xcode)  
Entorno: Binarios optimizados en configuración Release (`-c release`)

---

## 1. Resumen Ejecutivo

Este informe consolida las mediciones y la verificación experimental de **SwiftAttributeGraph** bajo condiciones de carga real de interfaz de usuario declarativa (tipo SwiftUI) y estrés extremo.

El motor ha sido auditado contra los principios no negociables de arquitectura de grafos reactivos:
1. **Presupuesto de Frame UI ($\le 1,6\text{ ms}$)**: Cumplido con **p99 de $1,253\text{ ms}$** y media de **$0,513\text{ ms}$** bajo 500 mutaciones por frame sobre 10.000 componentes.
2. **Cero recursión en datos**: Cadenas de hasta 100.000 niveles evaluadas en frío en hilos con pila reducida (512 KB) sin desbordamiento.
3. **Borrado de aristas $O(1)$**: 50.000 desconexiones sobre un nodo común resueltas en **174,08 ms** lineales mediante swap-with-last con posición guardada.
4. **Ausencia total de fugas de memoria**: Tras crear y destruir 10.000 subgrafos (30.000 atributos), el contador de nodos regresa exactamente a la línea base (**0 nodos residuales**).
5. **Corte por versiones**: Aceleración de **$8,1\times$** ($0,72\text{ ms}$ vs $5,85\text{ ms}$) al podar la propagación en una cadena de 20.000 reglas cuando la primera regla corta el cambio.

---

## 2. Auditoría de Latencia de Frame (60 Frames Consecutivos @ 60 fps)

Simulación interactiva con 10.000 componentes montados en subgrafos independientes (`StressBenchmark`). Cada frame introduce 500 mutaciones directas (5% de la superficie de estado) y evalúa los dependientes observados:

| Métrica | Medida | Presupuesto Objetivo | Estado |
|---|---|---|---|
| **Montaje del árbol (10.000 componentes)** | **6,73 ms** | Inicial | — |
| **Frame 0 (render en frío)** | **10,70 ms** | Arranque | — |
| **Latencia media por frame** | **0,513 ms** | $\le 1,6\text{ ms}$ | ✅ CUMPLE |
| **Percentil 50 (Mediana)** | **0,477 ms** | $\le 1,6\text{ ms}$ | ✅ CUMPLE |
| **Percentil 95** | **0,648 ms** | $\le 1,6\text{ ms}$ | ✅ CUMPLE |
| **Percentil 99 (p99)** | **1,253 ms** | $\le 1,6\text{ ms}$ | ✅ CUMPLE |
| **Latencia máxima observada** | **1,253 ms** | $\le 2,5\text{ ms}$ | ✅ CUMPLE |
| **Vistas actualizadas por frame** | **500** | — | — |

---

## 3. Auditoría de Fan-Out Masivo (50.000 Lectores Directos)

Simulación de una variable global de entorno (`@Environment` / tema) leída por 50.000 reglas:

- **Tiempo de propagación dirty**: **0,506 ms** (marca iterativa de suciedad sin duplicados ni recursión).
- **Recálculo perezoso de los 50.000 lectores**: **17,169 ms** (~$0,34\ \mu\text{s}$ por regla evaluada).

---

## 4. Auditoría de Churn de Navegación y Ciclo de Vida

Simulación de entrada y salida de pantallas complejas:

- **Creación de 10.000 subgrafos (30.000 atributos)**: **7,11 ms**.
- **Liberación e invalidación de 10.000 subgrafos**: **8,38 ms**.
- **Fugas de memoria / Nodos residuales**: **0**.

---

## 5. Tabla Comparativa de Exigencias de Motores de Grafos

| Exigencia | Estándar de Referencia | SwiftAttributeGraph | Resultado |
|---|---|---|---|
| **Pila de actualización** | Pila explícita (`UpdateStack` de Compute) | Pila iterativa en heap con índice de reanudación | ✅ Verificado |
| **Identidad de atributo** | Índice 32 bits + Generación 32 bits (Salsa) | `AttributeID(index: UInt32, generation: UInt32)` | ✅ Verificado |
| **Almacenamiento por ranuras** | Arrays paralelos indexados por ranura | `NodeTable` plana sin punteros indirectos | ✅ Verificado |
| **Corte por versiones** | Época global y versión por nodo | `Graph.globalVersion` + `InputEdge.seenVersion` | ✅ Verificado |
| **Poda de dependencias** | Poda por cursor de lectura | `pruneEdges` dinámico en cada ejecución | ✅ Verificado |
| **Subgrafos y vida** | Destrucción jerárquica con invalidación diferida | `SubgraphTable` con árbol O(1) y posorden | ✅ Verificado |
| **Comparación en caliente** | Comparación de bytes para tipos triviales | `ValueComparator` con caché de `ComparisonPlan` | ✅ Verificado |
| **Reglas con estado** | Soporte de acumuladores y cambios diferenciales | `StatefulRule` y `RuleContext` | ✅ Verificado |
| **Redirecciones indirectas** | Alias y proyecciones sin nodo extra | `IndirectNode` con resolución iterativa | ✅ Verificado |
| **Batería de especificación** | Oráculos aleatorios y profundidad | M9 completo: 202 pruebas funcionales en verde | ✅ Verificado |
