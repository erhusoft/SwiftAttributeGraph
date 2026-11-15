# Sonda directa del AttributeGraph de Apple

Banco aislado del motor, sin SwiftUI ni ShellUI. El mismo archivo de escenarios se compila dos veces:

- Con `NATIVE_ATTRIBUTE_GRAPH`: importa AttributeGraph y llama al framework privado instalado en macOS.
- Sin esa bandera: usa el paquete SwiftAttributeGraph de la carpeta padre.

Los adaptadores solo traducen creación, lectura, escritura e invalidación. La evaluación, comparación e invalidación
las ejecuta cada motor. Las reglas de prueba son nuestras; no se copia una implementación de grafo.

## Repetir en Mac arm64

Desde la raíz del repositorio:

```bash
python3 NativeProbe/run.py --output /private/tmp/sag-native-results
```

Requiere Xcode con Swift 6.2 y macOS 15 o posterior. Por defecto usa `/Applications/Xcode.app/Contents/Developer`;
se puede elegir otro Xcode con `DEVELOPER_DIR`. La compatibilidad comprobada está limitada al entorno de Results.
El script descarga declaraciones de investigación, fijadas a una revisión, si no están en la caché de `/private/tmp`.
Necesita red en esa preparación inicial; el SDK y el framework nativo proceden de la máquina.

El script compila debug y release, verifica el enlace al framework del sistema y compara tres pares de procesos por
configuración. Cada proceso comprueba sus valores y contadores mediante precondiciones; cualquier fallo de compilación,
proceso, enlace o comparación termina la ejecución con error. No se omite el caso nativo si no está disponible.

## Acceso al framework

El SDK de esta máquina solo ofrece el stub de enlace: no trae un módulo Swift importable de AttributeGraph. Se usan las
interfaces de investigación de [DarwinPrivateFrameworks](https://github.com/OpenSwiftUIProject/DarwinPrivateFrameworks/tree/511cc728141f57dc325753f23898568ccd49c339/AG/2024),
revisión `511cc728141f57dc325753f23898568ccd49c339`. Solo se descargan headers, modulemap y la interfaz Swift arm64,
**fuera del repositorio**, en la caché de la sonda. El stub se copia del SDK local a esa caché.

No se descarga ni se enlaza una biblioteca de implementación de terceros. El binario ejecutado es
`/System/Library/PrivateFrameworks/AttributeGraph.framework/Versions/A/AttributeGraph`. El paquete raíz no recibe
productos, targets ni dependencias nuevos; este banco es un paquete independiente de investigación.

## Cobertura y límites

Cuatro secuencias: dependencias dinámicas con cambio de rama, corte por igualdad en una cadena de dos reglas,
100 escrituras antes de leer y vida de un objeto en un subgrafo. Se verifican también escrituras iguales y una secuencia
que cambia un dato y lo restaura antes de leer. Se comprueba que ambos motores vuelven a cero nodos vivos.
El nativo además comprueba que el atributo débil deja de resolver y que el subgrafo ya no es válido.

Los perfiles se fijaron tras la primera observación directa y se verificaron en procesos independientes de debug y
release; no todos sus campos son predicciones nuevas. No hay tiempos ni afirmaciones de rendimiento equivalente.
Las declaraciones privadas pueden diferir del ABI real en otra versión; compilar no demuestra compatibilidad universal.
Los casos no cubren reglas con estado, ciclos, profundidad extrema, todos los tipos de comparación ni invalidación
reentrante. Windows queda fuera. [Resultados e interpretación](../docs/ESTUDIO-ATTRIBUTEGRAPH-NATIVO.md).
