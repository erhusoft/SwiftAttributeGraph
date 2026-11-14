# Perfil y optimización del prototipo de M4

Fecha: 2026-11-14. Mac M1, macOS 15.7.9, Swift 6.2.4. Solo se trabaja en Mac; Windows se aplaza hasta completar el
motor en Mac. Esto no cambia la API del paquete principal ni completa M4.

## Medición inicial y método

Se repitió el caso de 50 ciclos × 1.000 reglas con estado, dos entradas, sin creación ni precalentamiento dentro del
intervalo medido. Base de esta sesión: **111,99 ms** para el prototipo y **33,32 ms** para el motor actual, medianas
de siete muestras. Es compatible con los 109,66 / 33,26 ms de la primera versión; no es una comparación con SwiftUI.

Se añadió un ejecutable que reproduce esa carga con reglas definidas fuera del módulo del motor, y se recogieron
dos trazas de CPU con Instruments Time Profiler, limitadas a ese proceso. La traza base se limitó a ocho segundos;
la optimizada terminó la carga antes del límite. Los porcentajes siguientes se calculan solo sobre muestras cuyas
pilas contienen `PrototypeGraph.update`: 6.543 muestras en la base y 6.098 en la segunda traza.

| Símbolo o camino | Base | Tras los cambios |
|---|---:|---:|
| `swift_beginAccess`, inclusivo | 21,11 % | 29,37 % |
| `swift_weakLoadStrong`, propio | 5,32 % | 7,28 % |
| `_swift_getGenericMetadata`, inclusivo | 13,20 % | 10,02 % |
| `Evaluation.__allocating_init`, inclusivo | 6,13 % | Ya no se crea una evaluación por ejecución caliente |
| Reserva de buffer de `Array`, inclusivo | 7,72 % | Se conservan y alternan los buffers de lecturas |

Los porcentajes inclusivos **se solapan y no se suman**. Una fracción relativa mayor en la traza optimizada no
demuestra que esa operación tarde más: se ha eliminado trabajo de otras partes y las grabaciones no contienen el
mismo número de evaluaciones completas. Las muestras orientan; los tiempos se obtienen del benchmark sin Instruments.
`SwiftTLSContext::get` aparece bajo la exclusividad del runtime: no debe confundirse con el contexto por hilo del motor.

## Cambios medidos por separado

| Estado acumulado | Prototipo | Motor actual en esa ejecución |
|---|---:|---:|
| Base de la sesión | 111,99 ms | 33,32 ms |
| Reutilizar la evaluación propiedad de cada regla | 103,07 ms | 33,44 ms |
| Conservar diccionario de cambios y alternar buffers de dependencias | 86,81 ms | 33,42 ms |
| Una sola resolución de atributo en `poll` y pequeñas ayudas de inlining | 85,34 ms | 33,27 ms |
| Verificar entradas con un cursor local y guardar el marco solo al suspender | 82,97 ms | 33,23 ms |
| Permitir especialización de las operaciones del contexto entre módulos | 76,48 ms | 33,30 ms |
| Batería final de rendimiento, ejecutada sola | **76,17 ms** | **33,20 ms** |

Cada fila es una mediana de siete muestras; las diferencias pequeñas pueden ser ruido. El resultado final reduce el
caso caliente aproximadamente un **32 %** respecto a la base de esta sesión, pero sigue costando **2,29×** el motor actual.

- **Evaluación reutilizada:** el token no se reinicia entre evaluaciones. El valor propuesto se vacía al terminar;
  el objeto de control permanece en el nodo y se libera con su dueño. Una prueba pasó de 50 reservas a una.
- **Buffers:** el posprocesado intercambia el arreglo de entradas y el de lecturas en vez de descartar uno. El
  diccionario de cambios se rellena reutilizando su capacidad, sin arreglo intermedio ni diccionario nuevo cada vez.
- **Verificación:** las entradas limpias se recorren con variables locales. Al apilar una fuente sucia se guardan
  cursor y cambio acumulado; el oráculo y la regresión de M3 comprueban que no se pierda un cambio previo.
- **Límite de módulo:** `@inlinable` y los auxiliares `@usableFromInline` permiten especializar el código genérico
  usado por la regla cliente. Los tipos siguen siendo internos al experimento; no hay una nueva API pública del motor.
- **Comprobaciones conservadas:** hilo original, identidad de grafo, ID vivo, tipo, ciclo y vigencia del contexto.
  No se usan `-Ounchecked`, exclusividad desactivada ni referencias `unowned(unsafe)`.

El benchmark final comprueba **cero reservas de objetos `Evaluation` y cero suspensiones** durante los ciclos
calientes. No significa que no haya ninguna reserva del asignador: esos contadores no cuentan buffers, tablas ni
objetos del runtime. Tampoco permiten atribuir el factor 2,29× al acto de suspender: en esa carga no ocurre.

## Experimentos descartados y coste de memoria

- Unir temporalmente cliente y motor en una compilación produjo una diferencia grande en una prueba exploratoria
  de un millón de evaluaciones (0,84 s frente a 1,66 s, una muestra). No es un resultado adoptado ni un benchmark
  comparable con el paquete: sirvió para investigar especialización entre módulos.
- Separar el control de vigencia en una clase no genérica y mover el valor propuesto a la caja tipada dio
  **79,13 ms**, frente a 76,48 ms antes del experimento. No justificó el cambio; se restauró el diseño anterior.
- Reutilizar reduce altas y bajas a cambio de retener un objeto de evaluación por regla ejecutada y capacidad de
  buffers hasta que muere su dueño. El contexto conserva el grafo débilmente; los tokens antiguos siguen inválidos.
  La nueva prueba de vida comprueba que el almacenamiento reutilizado se libera al invalidar su dueño.
- No se ha medido la memoria total retenida. Los datos de capacidad de marcos siguen excluyendo nodos, valores,
  buffers, diccionarios, evaluaciones, metadatos y sobrecoste del asignador. No se presentan como consumo total.

## Validación final

**24 pruebas** de depuración; release dividido en **21 funcionales y 3 de rendimiento**, todo en verde. Incluyen
profundidad de 100.000 en pila pequeña, 20.000 reglas con estado, oráculo, poda, valores opcionales, token de paso,
token de evaluaciones anteriores, propuesta conservada y liberación con el dueño.

TDD de la reutilización: antes de cambiar el almacenamiento, su prueba falló con 50 reservas frente a una esperada;
después pasa. Las pruebas de contextos escapados siguen activas en release. No se ha modificado el motor principal.

Medidas finales adicionales, medianas de cinco muestras: 20.000 reglas frías, **30,36 ms**; 100.000, **152,73 ms**;
un millón de lecturas limpias, **118,81 ms**. La medición fría excluye creación y destrucción del dueño; ahora el
objeto de evaluación se conserva hasta esa destrucción, por lo que parte del trabajo de liberación sale del intervalo.

## Cómo reproducir el perfil

Se necesita Xcode con Instruments y Swift 6.2. Para este ejecutable interno se requiere `-enable-testing` incluso al
compilar release. Desde la raíz, usando la selección de Swift de Xcode para cada orden:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift build --package-path Prototypes/ResumableGraph -c release -Xswiftc -enable-testing --product ResumableGraphProfile
```

El ejecutable estará en el directorio de binarios que devuelve `swift build --show-bin-path` con los mismos
parámetros de paquete y configuración. Pasar `5000` ejecuta 5.000 ciclos de 1.000 reglas. Usar una ruta nueva para
cada traza y la ruta absoluta del ejecutable:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun xctrace record --template 'Time Profiler' --time-limit 8s --output /tmp/m4-profile.trace --launch -- /ruta/absoluta/ResumableGraphProfile 5000
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun xctrace export --input /tmp/m4-profile.trace --xpath '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]' --output /tmp/m4-profile.xml
python3 Prototypes/ResumableGraph/Tools/summarize_profile.py /tmp/m4-profile.xml
```

El script solo usa la biblioteca estándar de Python y resume símbolos, no mide reservas. No es una dependencia del
motor. Las trazas completas se dejaron fuera del repositorio. El ejecutable de perfil requiere macOS 13 o posterior.

## Lo que sigue pendiente

La exclusividad y los accesos comprobados todavía pesan en esta representación de clases. Antes de integrar hay
que contrastar el camino reanudable con el almacén real y mantener las mismas garantías de seguridad y vida. Siguen
pendientes M2 completo, M5 completo, migración de reglas síncronas, memoria total, percentiles y cargas de UI. Windows
se validará después de completar el motor en Mac; no forma parte de esta etapa ni bloquea el cierre de M4 en Mac.
