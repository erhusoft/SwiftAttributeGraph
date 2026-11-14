# Preguntas antes de diseñar M0

Fecha: 2026-11-14. Este documento va **antes** de `DISENO-M0.md`. Explica cómo se construye un motor de grafo de
atributos, con un ejemplo, y lista las preguntas que hay que cerrar antes de escribir código. Marca siempre qué es
**sabido** (medido o leído en una fuente) y qué es **supuesto**.

## 1. Cómo funciona un motor de grafo, con un ejemplo

Imagina una hoja de cálculo:

```
A = 2            (entrada: un número que escribe alguien)
B = 3            (entrada)
C = A + B        (regla: una fórmula)
D = C * 10       (regla)
```

El **grafo** son las flechas: C lee A y B; D lee C. El motor hace cuatro cosas.

**1. Descubrir las flechas al leer.** Nadie declara «C depende de A y B». Cuando se ejecuta la fórmula de C y esta
lee A, el motor apunta «C leyó A». Por eso una fórmula con un `if` (`C = flag ? A : B`) depende de A *o* de B según
el caso, y el motor se entera solo. Para saber «quién está leyendo ahora» necesita una variable que diga «estoy
dentro de la fórmula de C» (el *contexto de rastreo*).

**2. Marcar sin calcular (empuje).** Si alguien cambia A a 5, el motor **no recalcula** nada todavía. Solo marca
«posiblemente sucio» C y, por la flecha siguiente, D. Marcar es barato: es recorrer flechas hacia delante.

**3. Calcular solo al pedir (tirón).** Cuando alguien lee D y D está marcado, el motor mira qué lee D (C), ve que C
también está marcado, mira qué lee C (A y B), y recalcula de abajo arriba: primero C, luego D. Si nadie lee D, nunca
se calcula. Esto es la **evaluación perezosa**.

**4. Cortar cuando nada cambió de verdad.** Si C salía 5 y tras recalcular vuelve a salir 5, D no necesita
recalcularse. «Marcado» solo significa «puede haber cambiado»; «cambió de verdad» se comprueba comparando. Una forma
simple: cada nodo tiene un número de **versión** que sube solo si su valor cambió; cada flecha recuerda qué versión
vio el lector. Si todas las versiones coinciden, no se recalcula. Este corte es lo que más trabajo ahorra.

Y una quinta cosa, que no está en la hoja de cálculo:

**5. Dueños.** En una UI, cada vista crea sus atributos y, cuando la vista desaparece, todos deben desaparecer. El
motor agrupa los nodos en **subgrafos**: al destruir un subgrafo se libera todo lo suyo de golpe.

### Las piezas, de abajo arriba

| Pieza | Qué es | Detalle que importa |
|---|---|---|
| Identidad | Un número que nombra un nodo | Índice + generación: si el nodo muere y su hueco se reutiliza, el número viejo ya no vale |
| Tabla de nodos | Un arreglo de huecos con lista de huecos libres | Más rápido que un diccionario (medido: G1) |
| Nodo | Valor o regla + estado (bits) + flechas | Separar la parte común de la parte con tipo (medido: G2/G3, 3,8×) |
| Flechas | Entrantes (con versión vista) y salientes | Entrantes **en orden de lectura**, para parar en la primera que cambió |
| Propagación | Recorrer salientes marcando sucio | Con pila propia, no recursiva |
| Actualización | Recalcular al leer | Con pila propia; se reanuda donde se dejó |
| Rastreo | Saber quién lee ahora | Variable por hilo (medido: G5, 18×) |
| Subgrafos | Dueños jerárquicos | Liberar en bloque; diferido si hay una actualización en curso |

**¿Por qué «sin recursión»?** Una cadena de 20.000 nodos, si se recorre con funciones que se llaman a sí mismas,
desborda la pila del sistema y el programa se cae. Con una lista propia en el montón no hay límite de ese tipo.

## 2. Lo que sabemos y lo que no

| Tema | Estado | Fuente |
|---|---|---|
| Separar «sucio» de «cambió de verdad» y cortar | **Sabido**: las cuatro fuentes coinciden | Compute, Salsa, Signals |
| Arreglos de enteros y tabla indexada | **Medido** en SwiftGraph: 3,8× en propagación | G1–G3 |
| Contexto de rastreo por hilo nativo | **Medido**: 18× | G5 |
| Pila de actualización explícita | **Leído** en Compute; sin medir | `ESTUDIO-COMPUTE.md` |
| Cómo es AttributeGraph de Apple por dentro | **No verificado**: todo es reconstrucción | No se pudo leer a Saagar Jha ni a Rens Breur |
| Qué le pide a un motor una UI tipo SwiftUI | **Leído** en OpenSwiftUI, parcial | `ESTUDIO-OPENSWIFTUI-VISTAS.md` |
| Si Swift es el mejor lenguaje para el núcleo | **Supuesto**: solo se midió que cambiar estructuras ayuda | — |
| Si nuestra UI aprovechará el corte | **Sin decidir**: G4 se descartó porque la UI reconstruye por frame | `DISENO-G4-CORTE.md`, `DECISION-ARQUITECTURA-VISTAS.md` |

## 3. Preguntas, de más a menos importante

Cada una dice **cómo se cierra**, para que no queden en el aire.

| # | Pregunta | Por qué importa | Cómo se cierra |
|---|---|---|---|
| Q1 | **¿La UI va a aprovechar un motor completo?** Si reconstruye el árbol cada frame (como React), el corte, los subgrafos y las versiones se usan poco. Si es de grano fino (como SwiftUI), son el corazón | Decide si el proyecto entero tiene la forma correcta | Leer `DECISION-ARQUITECTURA-VISTAS.md` y decidir entre O1, O2 y O3, o fijar que el motor se construye para O2/O3 |
| Q2 | **¿Cuál es el contrato exacto con la UI?** Qué crea la UI, cuándo lee, cuándo escribe, cómo se entera de que repintar | Sin contrato, el motor es abstracto y puede no encajar | Escribir una página: «la UI hace estas 10 llamadas», sacada de `ESTUDIO-OPENSWIFTUI-VISTAS.md` |
| Q3 | **¿Qué grano y qué escala?** ¿Un atributo por propiedad, por vista, por struct? ¿Cuántos nodos por frame y cuántos ms hay? | Sin números, «medir» no tiene referencia | Fijar un caso objetivo (por ejemplo 1.000 filas, 10.000 nodos, 16 ms) |
| Q4 | **¿Quién crea los atributos y cuándo mueren?** (subgrafos desde M0 o desde M5) | Define la API pública, que es lo más caro de cambiar | Decidir tras Q1 y Q2 |
| Q5 | **¿Cómo se entera la UI de que algo cambió?** Aviso al ensuciar, o pregunta por frame | Define `observe`, el orden de los avisos y qué se permite dentro | Decidir tras Q2 |
| Q6 | **¿La lectura copia o presta el valor?** Con arrays grandes, copiar en cada lectura tira las ganancias | Define `value(of:)` y `Rule` | Prototipo medido con valores grandes |
| Q7 | **¿Qué se permite escribir durante una actualización?** Reglas que escriben, avisos que escriben | Define las garantías de consistencia | Decidir y fijar por escrito |
| Q8 | **¿Es Swift el lenguaje correcto para el núcleo?** Alternativa: núcleo sin tipos en otro lenguaje con cáscara Swift | Es la decisión menos reversible | Prototipo pequeño de las dos formas de guardar valores (P4) antes de fijar la arquitectura |
| Q9 | **¿Las versiones entran ya en la disposición de datos?** Si la flecha lleva «versión vista» desde M0, no hay que reescribir en M1 | Puede obligar a diseñar M0 y M1 juntos | Decidir al escribir `DISENO-M0.md` |
| Q10 | **¿Qué es «correcto»?** El oráculo recalcula todo, pero ¿mira solo valores o también cuántas veces corrió cada regla? | Define qué comprueban los tests | Decidir antes de escribir los tests |

## 4. Orden para cerrarlas

1. **Q1, Q2 y Q3** primero: son sobre el consumidor y la escala, no sobre el motor. Se resuelven leyendo lo que ya
   hay en SwiftGraph y decidiendo con el dueño.
2. **Q4, Q5, Q7**: con el contrato delante, son decisiones cortas.
3. **Q6 y Q8**: se resuelven con un prototipo medido, no discutiendo.
4. **Q9 y Q10**: se cierran al reescribir `DISENO-M0.md`, que se rehace con todas las respuestas.

`DISENO-M0.md` queda como borrador hasta entonces.

> **Corrección del dueño (2026-11-14):** el proyecto empieza **desde cero** (P9: sin compatibilidad con `GraphNode`;
> la UI se adaptará una vez). Por tanto la sección 5 de abajo **parte de un ancla equivocada**: usa el estado actual
> de SwiftGraph (O1/O2/O3, el frame de 1.000 filas, H4) para decidir cómo debe ser el motor. Eso condiciona el
> diseño con límites que no tiene por qué heredar. **Q1 y Q3 quedan reabiertas** y deben responderse desde lo que el
> motor debe ser por sí mismo (§1 y la checklist A), no desde lo que la UI actual aprovecha. Lo que sí se conserva:
> Q2 como lista de lo que pide una capa de vistas de fondo fino (viene de OpenSwiftUI, no de SwiftGraph), y las cifras
> medidas de G1–G5 como **referencias de rendimiento**, no como requisitos.

> **Respuesta del dueño a Q1 (2026-11-14):** el motor se usará para **aplicaciones de escritorio en Swift, con la
> sintaxis de SwiftUI y con paridad** de comportamiento con SwiftUI. Consecuencias:
> - El modelo de **grano fino** (construir una vez, actualizar por atributos) deja de ser opcional: sin él no hay
>   paridad (cuándo corre un `body`, entorno por subárbol, vida por rama). M1, M2, M3 y M5 son núcleo, no mejoras.
> - Q4 queda decidida: **los subgrafos forman parte del diseño desde M0** (los atributos nacen en el subgrafo actual).
> - El criterio de «correcto» (Q10) pasa a ser **paridad observable**: qué ejecuta SwiftUI y cuándo. Hay un problema
>   nuevo, Q11: no tenemos el binario de Apple verificado (ver §2), así que hay que decidir **contra qué se mide la
>   paridad**.
> - Q3 (escala) sigue abierta, ahora para aplicaciones de escritorio y no para el frame actual de SwiftGraph.

## 5. Respuestas a Q1, Q2 y Q3 (2026-11-14, tras leer `DECISION-ARQUITECTURA-VISTAS.md`, `ESTUDIO-OPENSWIFTUI-VISTAS.md` y `DISENO-G4-CORTE.md`) — REABIERTAS, ver aviso

### Q1 · ¿La UI aprovechará un motor completo?

**Lo que dicen los documentos de SwiftGraph:**
- Hoy la UI **reconstruye todo el árbol en cada frame** y suelta el grafo de layout al final (H4). Con eso, el corte
  por igualdad no ahorra nada: no hay nodos calculados que vivan entre frames (`DISENO-G4-CORTE.md` §2).
- Las mejoras G1–G3 aceleraron 3,8× un test sintético, pero **el frame de 1.000 filas no cambió** (6,23 → 6,28 ms).
  Las mejoras grandes que quedan están en la resolución de vistas y el layout, no en el grafo (§5 de ese documento).
- Existen tres opciones para la UI: **O1** seguir igual, **O2** híbrido (cada vista propia reutiliza su resultado si
  nada cambió), **O3** como SwiftUI (vistas, layout y display list como atributos persistentes).

**Lectura para este proyecto:** este motor solo tiene sentido si la UI va hacia **O2 u O3**. Con O1 sería un
ejercicio que no cambia el frame. Con O3 es el corazón: `body` como regla que se salta si nada cambió, subgrafos por
rama y por elemento de lista, entorno por subárbol. El motor se está construyendo, por tanto, **para O3**, y eso fija
la importancia de las piezas:

| Pieza | Con O1 | Con O2/O3 |
|---|---|---|
| M1 corte por versiones | Casi sin uso | **Central**: es lo que salta el `body` |
| M5 subgrafos | Dueños simples | **Central**: una rama o un elemento = un subgrafo |
| M3 reglas con estado | Poco | `DynamicBody` necesita «qué propiedades cambiaron» |
| M2 comparador por tipo | Escrituras | **Crítico**: la incógnita principal de OpenSwiftUI §5 es *comparar el valor de una vista*, que puede llevar cierres |
| M7 aristas eficientes | Poco | Importante: el nodo de frame o una lista tienen miles de padres |

**Decisión del dueño que falta:** confirmar que el motor se hace **pensando en O3** (O2 como paso intermedio). Si la
respuesta fuera O1, habría que replantear si vale la pena el proyecto.

**Consecuencia ya segura:** M2 sube de importancia. Es el único punto donde la UI no tiene solución todavía.

### Q2 · Contrato con la UI (borrador, sacado de OpenSwiftUI; inferencia, no verificado contra Apple)

Lo que una capa de vistas tipo SwiftUI le pide al motor:

1. **Crear un subgrafo** y fijarlo como actual; los atributos nacen en el subgrafo actual.
2. **Crear atributos** de entrada (`@State`, el valor de la vista) y de regla (`body`, layout, display list).
3. **Reglas con entradas dinámicas**: el `body` lee lo que necesita y el motor descubre las dependencias.
4. **Saltar el `body`** si el valor de la vista no cambió y ninguna propiedad dinámica que leyó cambió. Pide una
   comparación del valor de la vista (M2) y «qué entradas cambiaron» (M3).
5. **Entradas y salidas como atributos**: entorno, transacción, tamaño, posición bajan; display list y preferencias
   suben. Un modificador crea un atributo nuevo para los hijos (entorno **por subárbol**).
6. **Cambiar de rama**: crear un subgrafo hijo para la rama nueva e invalidar el viejo (`ConditionalContent`,
   `ForEach`). Invalidar libera todo lo suyo, **y debe poder hacerse durante una actualización** (diferido).
7. **Escribir un `@State`** desde un manejador de evento, agrupado en un lote.
8. **Observar** el nodo de frame: aviso cuando algo que renderiza queda sucio.
9. **Actualizar**: un `updateOutputs` por frame que lee la salida raíz (display list) y arrastra lo necesario.
10. **Leer sin crear dependencia** (por ejemplo, desde un evento) y **atributos indirectos** (leer un campo de otro
    atributo, M6).

Esto no es una API cerrada: es la lista que `DISENO-M0.md` debe poder cubrir sin rehacerse.

### Q3 · Grano y escala (propuesta, hay que confirmarla)

**Datos medidos (SwiftGraph):** frame de 1.000 filas: 6,2 ms con medida de texto falsa y **14–31 ms** con DirectWrite
real. Presupuesto de frame: 16 ms.

**Supuestos que hay que confirmar** (marcados como tales):
- Grano: **unos 5–10 atributos por vista** (valor, `body`, entorno, layout, geometría, display list), no uno por
  propiedad. *Supuesto*, tomado de la estructura de OpenSwiftUI.
- Caso objetivo: **lista de 1.000 filas** → del orden de **5.000–10.000 nodos vivos**, y un subgrafo por fila.
- Operaciones que importan, en este orden:
  1. Una escritura de `@State` en una fila: debe tocar solo lo de esa fila (unos pocos nodos), en microsegundos.
  2. Cambiar de rama o de lista: crear y destruir cientos de subgrafos en un frame.
  3. Crear la escena inicial: decenas de miles de nodos una vez.
  4. Recorridos profundos: árboles de ≥ 20.000 niveles sin desbordar.
- Presupuesto del **motor** dentro del frame: aún sin fijar. Propuesta: el motor no debe superar **~10 %** de los
  16 ms (1,6 ms) en el caso objetivo, para dejar sitio a layout, texto y dibujo.

**Cómo se cierra:** el dueño confirma o corrige estos números. Con ellos, `PLAN-MOTOR.md` pasa a tener referencias de
rendimiento propias del caso real, no solo las del test sintético.

## 6. Estado de las preguntas

| # | Estado |
|---|---|
| Q1 | **Respondida, falta confirmación del dueño**: motor para O3 (O2 como paso) |
| Q2 | Borrador listo (10 llamadas); falta revisarlo con el dueño |
| Q3 | Propuesta con supuestos marcados; falta confirmación |
| Q4–Q10 | Abiertas; Q4 queda casi decidida por Q1 (subgrafos desde M0) |
