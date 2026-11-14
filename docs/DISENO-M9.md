# Diseño M9: especificación completa (batería final)

Fecha: 2026-11-14. Parte de [PLAN-MOTOR.md](PLAN-MOTOR.md) §3 (M9) y §1 «Motor al 100 %». **Estado: definido, pendiente de
validación en Swift 6.2.4** (Swift por omisión es 6.1.2, pero Xcode incluye 6.2.4 y se usa para validar).

## 1. Qué es M9

M9 no añade funcionalidad nueva al motor. Es la **batería final de especificación** que define «motor al 100 %» y que,
cuando pasa en verde en depuración y release, da por completo el motor antes de conectarle una UI (proyecto `SwiftGraph`).

Criterio de «al 100 %» (PLAN-MOTOR.md §1):
1. Todas las piezas M0–M8 hechas, con sus tests en verde.
2. La batería de especificación pasa: oráculos de comportamiento, profundidad ≥ 20.000 sin recursión, vuelta de
   `nodeCount` a la base, rendimiento medido.
3. Cubre lo que una capa de vistas tipo SwiftUI necesita (atributos persistentes con dueño, `body` como regla que se
   salta si nada cambió, subgrafos para ramas y colecciones, entradas y salidas como atributos).

## 2. Qué compone la batería (todos ya implementados)

| Carpeta | Suite | Qué cubre | Pieza |
|---------|-------|-----------|-------|
| `Unit/` | `IdentityTests` | IDs, generaciones, slots reutilizados | M0 |
| `Unit/` | `ValueTests` | Entradas, reglas, corte por versión | M0 |
| `Unit/` | `RuleTests` | Reglas de tipo y cierre | M0 |
| `Unit/` | `StatefulRuleTests` | Reglas con estado, `RuleContext` | M3 |
| `Unit/` | `PropagationTests` | Propagación de sucio, lotes, notificaciones | M0 |
| `Unit/` | `ObservationTests` | Observación de atributos | M0 |
| `Unit/` | `TrackingTests` | Contexto por hilo, TLS | M0 |
| `Unit/` | `SubgraphTests` | Jerarquía, invalidación diferida, avisos | M5 |
| `Unit/` | `EdgeRemovalTests` | Borrado de arista O(1), poda | M7 |
| `Unit/` | `IndirectTests` | Atributos indirectos | M6 |
| `Unit/` | `IntrospectionTests` | Contadores, dump, memoria | M8 |
| `Unit/` | `VersionCutTests` | Versión global, atajos de corte | M1 |
| `Unit/` | `ComparisonResolutionTests` | Comparador resuelto una vez | M2 |
| `Unit/` | `ResumableRuleTests` | Reglas reanudables, coexistencia síncrona/reanudable | M4 |
| `Unit/` | `ResumableStateTests` | Estado en reglas reanudables | M4 |
| `Unit/` | `ResumableThreadTests` | Afinidad de hilo en reanudables | M4 |
| `Parity/` | `ParityTests` | Paridad con SwiftUI real (E1–E19) | M0, M2 |
| `Parity/` | `ComparisonPolicyTests` | Políticas de comparación (caliente) | M2 |
| `Parity/` | `BranchParityTests` | Cambio de rama, filas por id | M5 |
| `Oracle/` | `OracleTests` | Valores y ejecuciones vs modelo de referencia | M0, M3 |
| `Oracle/` | `ResumableOracleTests` | Oráculo de reglas reanudables | M4 |
| `Oracle/` | `SubgraphOracleTests` | Oráculo de subgrafos | M5 |
| `Depth/` | `DepthTests` | ≥ 20.000 niveles sin recursión | M0, M4, M5 |
| `Lifetime/` | `LifetimeTests` | `nodeCount` vuelve a la base | M0, M5 |
| `Performance/` | `PerformanceTests` | Medidas en release | M0–M8 |
| `Performance/` | `ResumablePerformanceTests` | Medidas de reglas reanudables | M4 |

## 3. Criterios de aprobado

1. **Toda la batería en verde** en depuración y release (Swift 6.2.4, Mac M1).
2. **Profundidad ≥ 20.000** por cada recorrido: cadena, lectores, subgrafos anidados, hermanos, invalidación — sin recursión nativa.
3. **`nodeCount` vuelve a la base** tras crear e invalidar subgrafos, también invalidando desde dentro de reglas.
4. **Sin regresiones sostenidas > 10 %** en las métricas de rendimiento existentes frente a la base.
5. **Presupuesto de rendimiento** del caso objetivo (1.000 filas, 5–10 atributos por fila, un subgrafo por fila): el motor
   no debe pasar de ~10 % del frame (1,6 ms de 16 ms).

## 4. Medidas de rendimiento finales (pendiente de validar en Mac M1)

Se apuntarán en `PLAN-MOTOR.md` tras ejecutar en Swift 6.2.4:

| Caso | Objetivo | Medida (pendiente) |
|------|----------|--------------------|
| 100.000 entradas + 10 lecturas cada una | — | — |
| 500 escrituras + 1.000 dependientes sucios | ≤ 2,0 ms | — |
| 50 ciclos × 1.000 reglas con estado | ≤ 5,0 ms | — |
| Cadena de 20.000 reglas con corte | ≤ 1,0 ms | — |
| 2.000 subgrafos × 5 atributos crear + invalidar | ≤ 7,0 ms | — |

## 5. Archivos

- `docs/DISENO-M9.md` (este documento): diseño de la batería final.
- `docs/PLAN-MOTOR.md` §18: resultados de M9 (por escribir tras la validación).
- No se añade código de producción: M9 es solo especificación y tests existentes.

## 6. Límites y no verificado

- Este entorno no ejecuta `swift test` (toolchain 6.1.2, el paquete requiere 6.2). La ejecución y medición de la
  batería queda pendiente del Mac de desarrollo.
- La paridad con SwiftUI se midió en macOS 15.7.9 (M1); una versión distinta de SwiftUI puede cambiar el comportamiento.
- Windows sigue aplazado hasta completar el motor en Mac.
