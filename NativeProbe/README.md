# Sonda directa del AttributeGraph de Apple

Banco aislado del motor, sin SwiftUI ni ShellUI. Las mismas fuentes de escenarios se compilan dos veces:

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

Quince secuencias directas:
- Cuatro básicas (`dynamic`, `cut`, `lazy`, `lifetime`) descritas en el [primer estudio directo](../docs/ESTUDIO-ATTRIBUTEGRAPH-NATIVO.md).
- Cuatro variantes de diamantes (`diamond-source-forward/reverse`, `diamond-multiple-forward/reverse`) descritas en el [estudio de diamantes](../docs/ESTUDIO-DIAMANTES-NATIVOS.md).
- Siete escenarios de la auditoría C1–C19 (`stateful-no-write-cut`, `stateful-unread-input`, `stateful-has-value-and-revert`, `selector-input-order`, `invalidate-in-rule`, `weak-attribute-in-rule`, `indirect-rule-and-redirect`) descritos en la [auditoría C1–C19](../docs/ESTUDIO-AUDITORIA-C1-C19.md).

Se comprueba en todos los escenarios que ambos motores producen las mismas salidas y contadores de ejecución en procesos independientes de debug y release (3 pares por configuración) y vuelven a cero nodos vivos al cerrar el ámbito.
