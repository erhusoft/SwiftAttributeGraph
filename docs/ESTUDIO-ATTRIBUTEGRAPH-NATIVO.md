# Primera comparación directa con AttributeGraph nativo

Fecha: 2026-11-14. Mac M1 arm64, macOS 15.7.9 (24G830), Swift 6.2.4 de Xcode; SDK macOS 26.2.

## Corrección del criterio de validación

Las rondas de body, State y Binding observaban SwiftUI y, en algunos casos, nuestro prototipo de ShellUI. Sus resultados
son observaciones de UI: **no constituyen pruebas directas del comportamiento interno del grafo de Apple**. Los apartados
19–22 de PLAN-MOTOR.md quedan clasificados como registro de ese trabajo, sin contarlos como validación del núcleo.
El dueño ha indicado aparcar ShellUI como cascarón de API. Esta pieza no modifica sus fuentes.

Este experimento llama directamente a **AttributeGraph**, sin importar SwiftUI ni ShellUI. El programa define reglas
numéricas propias y ejecuta el motor nativo y nuestro motor desde procesos separados. No usa recuentos de body como
sustituto de ejecuciones de reglas del grafo.

## Acceso y procedencia

La prueba de acceso inicial creó un Graph y un Subgraph nativos, creó un atributo Int, leyó 3, escribió 4 y verificó la
invalidación del subgrafo. El contador nativo de nodos volvió a cero.

El SDK instalado tiene el stub de enlace, pero no un módulo Swift de AttributeGraph directamente importable. Se preparó
un módulo externo mediante headers e interfaz Swift de investigación de
[DarwinPrivateFrameworks, revisión fijada](https://github.com/OpenSwiftUIProject/DarwinPrivateFrameworks/tree/511cc728141f57dc325753f23898568ccd49c339/AG/2024).
Las declaraciones se guardan solo en `/private/tmp`, no se incorporan al motor. No se copia código de OpenAttributeGraph
ni se descarga una implementación de terceros. La sonda utiliza las funciones y los protocolos del framework de Apple;
la lógica de nuestros cuatro escenarios es propia.

`otool -L` comprueba que el ejecutable nativo enlaza a:

```
/System/Library/PrivateFrameworks/AttributeGraph.framework/Versions/A/AttributeGraph
```

El identificador de versión que muestra el enlace es 7.0.80. No aparece SwiftUI en los enlaces del ejecutable ni en sus
imports. Las trazas de enlace y el entorno se conservan con los resultados. Se distingue el SDK 26.2 usado para compilar
del runtime macOS 15.7.9 donde se ejecuta.

## Método

`NativeProbe/Sources/Probe/main.swift` es la fuente común. Un adaptador mínimo por backend traduce Graph, Subgraph,
Attribute, Rule, lectura, escritura y cierre. El adaptador nativo no implementa seguimiento de dependencias, evaluación,
corte ni invalidación: esas operaciones las hace AttributeGraph. El adaptador propio usa el paquete raíz.

Las reglas nativas se definen como tipos conformes a Rule y llaman a un cierre de escenario; las propias usan la API
de reglas con cierre. Se cuentan ejecuciones dentro de los mismos cálculos. Esta diferencia de envoltorio no se usa
para comparar tiempos. No hay UI, run loop, ventanas, State ni Binding.

Los valores se comprobaron desde la primera sonda; los perfiles completos de contadores se fijaron después de observar
el nativo. El corredor los valida mediante precondiciones además de comparar ambas salidas. Después se verificaron tres
pares de procesos en debug y tres en release: **12 procesos, cuatro escenarios cada uno, 48 ejecuciones de escenarios**.
Son repeticiones de cuatro escenarios, no 48 casos independientes. Cualquier diferencia o proceso fallido hace fallar
el corredor; no se admite ausencia silenciosa del nativo.

## Resultados

Los seis pares de procesos producen exactamente las mismas trazas.

### Dependencias dinámicas

Entradas primero=0, segundo=100, selector=0. La regla lee únicamente la entrada seleccionada.

| Paso | Valor de la regla | Ejecuciones acumuladas |
|---|---:|---:|
| Primera lectura | 0 | 1 |
| Primero=1 | 1 | 2 |
| Primero=1 otra vez | 1 | 2 |
| Seleccionar segundo | 100 | 3 |
| Primero=2, ahora inactivo | 100 | **3** |
| Segundo=101 | 101 | 4 |
| Volver a primero | 2 | 5 |
| Segundo=102, ahora inactivo | 2 | **5** |
| Primero=3 | 3 | 6 |

En este caso directo, AttributeGraph **no ejecuta la regla por escrituras en la entrada retirada**. Coincide con la poda
de nuestro núcleo. Esto no permite explicar todas las capas de SwiftUI; sí impide atribuir automáticamente al núcleo
la reevaluación histórica observada en aquellas sondas de UI. La regla no corre antes de pedir su primer valor.

### Corte por igualdad aguas abajo

Cadena `entrada → entrada % 2 → resultado + 10`. Tras la lectura inicial, se escribe `[2,2,3,5,6]` y se lee la salida.

- Valores de salida: `[10,10,10,11,11,10]`.
- Ejecuciones acumuladas de la regla intermedia: `[1,2,2,3,4,5]`.
- Ejecuciones acumuladas de la regla final: `[1,1,1,2,2,3]`.

La intermedia puede recalcular y conservar el mismo valor; en ese caso la regla final se omite. Escribir el mismo Int
no vuelve a ejecutar ninguna de las dos. Los dos motores coinciden.

### Escrituras acumuladas y restauración antes de leer

Tras la lectura inicial (una ejecución), se hacen 100 escrituras sin leer: sigue habiendo una sola ejecución. Pedir
el valor devuelve 100 y ejecuta una vez más (dos en total). Luego se escribe 101 y 100 antes de leer otra vez: la regla
se ejecuta de nuevo (tres en total), aunque su resultado final sea igual al anterior. Ambos motores coinciden en esa
secuencia; no se atribuye el resultado a una política universal de transacciones.

### Vida del dueño

Un objeto con valor 7 vive en una entrada; una regla lee su campo. Tras invalidar al dueño:

- La referencia débil al objeto queda en nil en ambos motores.
- Los nodos vivos vuelven a cero (contador nativo y nodeCount propio).
- El nativo informa que el subgrafo no es válido y su WeakAttribute deja de resolver.
- En el propio también se comprueban cero aristas y solo el subgrafo raíz.

No se leen identificadores muertos ni se intenta convertir un fallo de ABI en un resultado válido.

## Reproducción y archivos

```bash
python3 NativeProbe/run.py --output /private/tmp/sag-native-results
```

El bootstrap descarga solo declaraciones fijadas a la revisión, fuera del repositorio; requiere red la primera vez.
Después usa el Xcode seleccionado mediante DEVELOPER_DIR, el stub del SDK y el framework del sistema. Este banco es
un paquete independiente; Package.swift del motor no cambia y no adquiere dependencias externas.

Los archivos originales están en `NativeProbe/Results/macos-15.7.9/`: entorno, enlaces, compilación y las doce salidas.
El runner compara las trazas y falla por código de salida, enlace inesperado, número de líneas o contenido diferente.

## Alcance de la conclusión

**Hay coincidencia directa del núcleo en estos cuatro escenarios, no paridad general demostrada.** No se mide rendimiento,
profundidad extrema, ciclos, todos los tipos de comparación, reglas con estado, grafos grandes o invalidación durante una
regla. Las declaraciones son reconstrucciones externas del ABI y pueden no ser compatibles con otro runtime. Los
resultados comprueban los caminos ejecutados, no todas las declaraciones del módulo.

No se modifica el núcleo ni se desarrolla ShellUI o Windows. El siguiente bloque de pruebas debe ampliar este mismo
banco directo con reglas con estado, diamantes y cambios de dependencias con varias entradas modificadas antes de leer.

Se comprobó además el bootstrap desde una caché vacía: descargó las declaraciones fijadas y pasó un par de procesos
por configuración. Esa comprobación adicional se conserva en `bootstrap-verification.txt`; no se suma como casos nuevos.
No se volvió a ejecutar la batería completa del paquete raíz en esta pieza, porque sus fuentes no cambiaron: se
compiló el motor en debug y release y se ejecutaron los oráculos directos descritos aquí.
