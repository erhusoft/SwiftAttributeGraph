# Diamantes contra AttributeGraph nativo

Fecha: 2026-11-14. Predicciones escritas antes de ejecutar esta ronda. Solo núcleo, sin SwiftUI ni ShellUI.

## Predicciones

D1: una fuente x alimenta A=x+1 y B=x*2; C lee A y B y devuelve su suma. Se prueban los dos órdenes de lectura en C.
La primera lectura de C debe ejecutar A, B y C una vez. Escribir x=2 y x=3 antes de leer debe ejecutar cada regla una
sola vez adicional y producir 10; escribir x=3 otra vez no debe ejecutar ninguna. Con x=4 se pide primero A: B y C
siguen sin ejecutarse hasta pedir C. Esa lectura debe producir 13 sin repetir A. Con x=0 se obtiene 1. Escribir x=1 y
restaurar x=0 antes de leer vuelve a comprobar A y B, cuyos resultados no cambian; C debe omitirse.

Valores observados al pedir C: [4,10,10,13,1,1,1]. Contadores acumulados A/B: [1,2,2,3,4,5,5]; C: [1,2,2,3,4,4,4].
Los pares que C llega a consumir deben ser exactamente [(2,2),(4,6),(5,8),(1,0)], sin mezclar versiones de ramas.

D2: A=x+y, B=x-y, C=A+B, D=C*10, con x=2,y=10. Se cambian varias entradas antes de leer: x=3,y=20,x=4. Debe producir
80 ejecutando una vez adicional cada regla. Cambiar solo y=21 cambia ambas ramas, pero C conserva 8 y D debe omitirse.
Cambiar y=22 y restaurar y=21 antes de leer comprueba ambas ramas, pero ni C ni D deben ejecutarse. Con x=5,y=30 se
obtiene 100; repetir esas escrituras iguales no debe ejecutar reglas. Se prueban ambos órdenes de lectura en C.

Salidas D: [40,80,80,80,100,100]. A/B: [1,2,3,4,5,5]; C: [1,2,3,3,4,4]; D: [1,2,2,2,3,3].

Las escrituras deben ser perezosas y cerrar cada escenario debe devolver nodos vivos a cero en ambos motores.
Estos son cuatro escenarios nuevos (dos formas, dos órdenes), no pruebas de todos los grafos posibles. Si la predicción
falla en el nativo, se conserva el fallo y se investiga; no se cambia el oráculo silenciosamente para hacerlos coincidir.
No se mide rendimiento porque no se introduce código de producción ni algoritmos nuevos.

## Resultados

Mac M1 arm64, macOS 15.7.9 (24G830), Swift 6.2.4. **Todas las predicciones anteriores pasan** en el AttributeGraph
instalado y en nuestro motor, en debug y release. No fue necesario corregir el núcleo ni ajustar los perfiles esperados.

D1, en ambos órdenes:

| Lectura de C tras la acción | Valor | A acumuladas | B acumuladas | C acumuladas |
|---|---:|---:|---:|---:|
| Montaje, x=1 | 4 | 1 | 1 | 1 |
| x=2 y x=3 antes de leer | 10 | 2 | 2 | 2 |
| x=3 otra vez | 10 | 2 | 2 | 2 |
| x=4; pedir A antes de C | 13 | 3 | 3 | 3 |
| x=0 | 1 | 4 | 4 | 4 |
| x=1 y restaurar x=0 antes de leer | 1 | 5 | 5 | **4** |
| Lectura limpia repetida | 1 | 5 | 5 | 4 |

La lectura anticipada de A comprueba además el estado intermedio de contadores: A=3, B=2, C=2. Pedir C no repite A.
Los pares que C consume son exactamente (2,2), (4,6), (5,8), (1,0). No se observa una combinación de rama vieja y nueva
en esas ejecuciones; esto no demuestra atomicidad para cualquier forma de acceso.

D2, en ambos órdenes:

| Lectura de D tras la acción | Valor | A/B acumuladas | C acumuladas | D acumuladas |
|---|---:|---:|---:|---:|
| Montaje, x=2,y=10 | 40 | 1 | 1 | 1 |
| x=3,y=20,x=4 antes de leer | 80 | 2 | 2 | 2 |
| y=21: ambas ramas cambian, suma igual | 80 | 3 | 3 | **2** |
| y=22 y restaurar y=21 antes de leer | 80 | 4 | **3** | **2** |
| x=5,y=30 antes de leer | 100 | 5 | 4 | 3 |
| x=5,y=30 otra vez | 100 | 5 | 4 | 3 |

Todos los pasos de escritura verifican que no ejecutan ninguna regla por adelantado. Al cerrar cada escenario, el
adaptador nativo comprueba Subgraph.isValid=false y cero nodos vivos; el propio comprueba cero nodos y aristas y solo
el subgrafo raíz. Se mantienen los cuatro escenarios anteriores en la misma batería.

## Validación del banco

El runner compila ahora todos los archivos de escenarios compartidos y comprueba los nombres y el orden exacto de las
ocho trazas, además de su contenido. No basta con que ambos procesos impriman el mismo número arbitrario de líneas.
Se ejecutaron tres pares de procesos por configuración: 12 procesos, ocho escenarios por proceso, **96 ejecuciones de
escenarios**, de las cuales 48 corresponden a los cuatro nuevos. No son 96 pruebas diferentes.

Una copia de la sonda bajo `/private/tmp` alteró deliberadamente el contador de C para sumar 2 por evaluación, sin cambiar
el cálculo numérico. El proceso nativo fue rechazado por una precondición de contadores (código -5). Esto comprueba que
el banco detecta un contador incorrecto aun conservando los cálculos; no se interpreta como un fallo real del nativo.
La fuente del repositorio no se modificó para esa mutación. El resumen está en `mutation.json`.

No se implementaron algoritmos nuevos: es una ampliación de oráculos. No se volvió a ejecutar la batería funcional raíz;
se compiló su motor en debug y release y se ejecutaron los ocho escenarios directos. Tampoco se mide un nuevo coste
ni se hace una afirmación sobre rendimiento equivalente. No hay un recorrido nuevo del motor que requiera profundidad.

## Reproducción y límites

```bash
python3 NativeProbe/run.py --output /private/tmp/sag-diamond-results
```

Fuentes nuevas: `NativeProbe/Sources/Probe/DiamondScenarios.swift`. Salidas originales:
`NativeProbe/Results/diamonds-macos-15.7.9/`. Se conserva el entorno y el enlace directo al framework del sistema,
sin SwiftUI ni ShellUI. Las declaraciones de investigación siguen fijadas a la misma revisión del primer estudio.

La coincidencia queda limitada a estos grafos pequeños, reglas Int y este runtime. No demuestra orden universal de
actualización, concurrencia, ciclos, profundidad extrema, reglas con estado ni destrucción durante una regla. Cambiar
el orden de lectura en C es una variación de la forma del diamante, no una prueba independiente de toda la planificación.
Windows y ShellUI siguen aparcados. La siguiente pieza puede contrastar reglas con estado o cambios de selector y varias
entradas sobre este mismo banco, fijando de nuevo las predicciones antes de medir.
