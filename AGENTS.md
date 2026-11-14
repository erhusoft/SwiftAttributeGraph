# SwiftAttributeGraph — Instrucciones para trabajar (cualquier agente)

Léelo entero antes de tocar nada. Responde y documenta en **español**; el código, los comentarios `///` y los mensajes
de commit van en **inglés**.

## 1. Qué es

Un **motor de grafo de atributos** en Swift puro, para que un framework de UI declarativa (como SwiftUI) lo use por
debajo: nodos con valor o regla, dependencias descubiertas al leer, invalidación hacia delante, recálculo perezoso,
corte por igualdad y subgrafos con dueño.

- **Solo el motor.** No sabe nada de vistas, layout, dibujo, ventanas ni accesibilidad. Eso vive en el proyecto de UI
  (`SwiftGraph`, en `C:\Users\erhusoft\SwiftGraph`), que dependerá de este paquete cuando esté completo.
- **Se escribe desde cero** con lo aprendido en los estudios del proyecto SwiftGraph (ver §5). **No se copia código**
  de OpenAttributeGraph, Compute, Salsa ni Preact Signals; se adaptan ideas y se cita la fuente.
- Plataformas: Windows ARM64 (principal) y x64. El motor no debe usar nada específico de Windows salvo donde se
  justifique y se aísle (como el almacenamiento por hilo); así podría portarse.

| Archivo | Para qué |
|---|---|
| `AGENTS.md` (este) | Cómo trabajar |
| `docs/PLAN-MOTOR.md` | **Fuente de verdad del estado**: piezas M0–M9, criterio de terminado, decisiones abiertas |

## 2. Principios no negociables

1. **Nada recursivo que dependa de los datos.** Todo recorrido usa pila o cola explícita. Cada recorrido nuevo lleva
   un test de profundidad (≥ 20.000 niveles).
2. **Nada persistente sin dueño.** Todo nodo tiene un dueño (subgrafo) y muere con él. Los tests comprueban que
   `nodeCount` vuelve a la base.
3. **Dependencias exactas y evaluación perezosa.** Se podan las que ya no se leen; nada se calcula hasta que se pide.
4. **Medir antes de optimizar.** Cada pieza con coste tiene un test de rendimiento en release, y su resultado se
   apunta en `docs/PLAN-MOTOR.md`.
5. **Sin dependencias externas.** Solo la biblioteca estándar de Swift; Foundation únicamente si hace falta y se
   justifica.
6. **Un solo hilo por grafo.** Un grafo se usa desde un hilo; se documenta y se comprueba en depuración.

Reglas de código: un tipo principal por archivo; todo lo público con `///` (DocC); **TDD** (el test primero, verlo
fallar, implementar, `swift test` en verde). Los tests son la especificación.

## 3. Cómo se construye y se prueba

```bash
swift build
swift test
swift test -c release -Xswiftc -enable-testing --filter Performance   # rendimiento
```

## 4. Cómo trabajar una pieza

1. Lee su apartado en `docs/PLAN-MOTOR.md`.
2. Escribe los tests (fallan), implementa lo mínimo, `swift test` en verde.
3. Mide si tiene coste y apunta el resultado.
4. Actualiza `docs/PLAN-MOTOR.md` (hecho, no verificado, límites). Un commit por pieza.

### Git
- No hay identidad global configurada: **no toques la configuración global**. Haz commit con
  `git -c user.name="…" -c user.email="…" commit -F mensaje.txt`.
- Mensajes en inglés. No hagas `push` sin que el dueño lo pida.

## 5. Conocimiento previo (en el repositorio SwiftGraph)

Antes de diseñar una pieza, lee lo que ya se estudió y midió:

| Documento (en `C:\Users\erhusoft\SwiftGraph\docs`) | Qué aporta |
|---|---|
| `PLAN-ESTUDIO-GRAFO.md` (sección «Síntesis») | Respuestas a Q1–Q8 con cuatro fuentes |
| `ESTUDIO-COMPUTE.md` | Motor real: bits `Dirty`/`Pending`, bit `Changed` por arista, pila de actualización, subgrafos |
| `ESTUDIO-SALSA.md` | Revisiones, *backdate*, durabilidad, ID índice + generación |
| `ESTUDIO-SIGNALS.md` | Corte por versiones, poda por marca y barrido |
| `ESTUDIO-OPENATTRIBUTEGRAPH.md` | La API de AttributeGraph que se conoce (`Attribute`, `Rule`, `Subgraph`) |
| `ESTUDIO-OPENSWIFTUI-VISTAS.md` | Qué le pide al motor una capa de vistas tipo SwiftUI |
| `DISENO-G1-ALMACENAMIENTO.md`, `DISENO-G5-RASTREO.md` | Qué funcionó y cuánto (medido) en el motor actual |
| `CHECKLIST-MOTOR-GRAFOS.md` | Lista de lo que necesita un motor de UI sobre grafos |
