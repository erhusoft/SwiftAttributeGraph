# Primera prueba vertical de estado y vistas

Fecha: 2026-11-14. Mac M1, macOS 15.7.9, Swift 6.2.4 de Xcode.

## Resultado

La conexión experimental `State → Binding → Button.action → grafo → body → Text` funciona en el paquete `Views/`.
**No hay paridad completa:** el caso nativo ejecuta un `body` adicional al modificar un `Binding` leído anteriormente,
aunque esa rama ya no se lea en el cuerpo actual. El valor mostrado coincide en toda la secuencia.

Esto es un banco semántico con montaje explícito, no un renderizador. No se modificó el motor ni se trabajó en Windows.

## Qué se implementó

- `State` conserva almacenamiento compartido entre copias. `install(in:)`, interno y explícito, mueve su valor inicial
  a un atributo con dueño. Las lecturas desde `body` registran dependencias y las escrituras invalidan de forma perezosa.
- `Binding` permite leer y escribir mediante cierres y pasar la proyección a una vista hija.
- `ViewGraphScope`, interno, monta una vista como regla de su `body` y libera los atributos con su subgrafo. No recorre
  árboles de vistas. Se comprueba también la invalidación desde un ancestro.
- El banco invoca la acción almacenada de `Button` y observa el contenido de `Text`, mediante acceso interno. No hay
  entrada de plataforma ni dibujo. Estos dos tipos siguen registrados como cascarones.
- `StateScreen.swift` comprueba las firmas de `@State`, `@Binding`, botones y `if` contra ShellUI y SwiftUI real.

La instalación automática de propiedades, la reconciliación general, la identidad de vistas y el ciclo completo de
`DynamicProperty` siguen pendientes. Fuera del banco, construir una `StateScreen` no la conecta automáticamente al grafo.
El montaje captura una instancia de vista; todavía no actualiza sus propiedades desde una nueva instancia del padre.

## Contraste nativo

`NativeVerticalSliceTests.swift` aloja una pantalla SwiftUI en `NSHostingView` y una ventana AppKit. Usa el hilo principal
y espera al procesamiento del run loop tras cada acción. Las acciones registradas escriben el mismo estado que los botones;
no se simula un clic físico. No se mide latencia nativa con estas esperas.

Después de la evaluación inicial, se observa esta secuencia:

| Acción | Texto en ambos | Evaluaciones propias del cuerpo seleccionado | Evaluaciones SwiftUI |
|---|---|---:|---:|
| Incrementar primero | 1 | 1 | 1 |
| Escribir primero = 1 otra vez | 1 | 0 | 0 |
| Cambiar a segundo | 100 | 1 | 1 |
| Incrementar primero, ahora inactivo | 100 | 0 | **1** |
| Escribir segundo = 101 | 101 | 1 | 1 |
| Volver a primero | 2 | 1 | 1 |

El cuerpo independiente no se vuelve a ejecutar en ninguno. En nuestro banco, el contador de lectores del primer estado
queda en cero al cambiar de rama. El contraste registra la diferencia como **un known issue**, limitado a esa comparación;
comprueba por separado la secuencia nativa observada. Un cambio distinto de comportamiento nativo hace fallar el test.
No se deduce de esta observación cómo implementa Apple internamente el seguimiento de `Binding`.

## Vida y ramas

- Un `if` real construido con `ViewBuilder` cambia la selección desde una acción de botón. El banco reconcilia manualmente
  esa forma fija: crea el nuevo subgrafo y su estado antes de invalidar el anterior. Tras 100 cambios quedan exactamente
  cuatro nodos (estado y cuerpo del padre, estado y cuerpo de la rama activa).
- Otros 100 montajes y desmontajes reinician el estado en 7 y devuelven `nodeCount` a la base en cada vuelta.
- Desmontar la pantalla devuelve nodos y aristas a cero y deja solo el subgrafo raíz.
- Un objeto guardado en estado se libera aun conservando una copia del envoltorio; este no retiene el valor inicial
  después de instalarlo. Un `Binding` retenido no puede leer un estado desmontado: el proceso se detiene deliberadamente.
- 20.000 ámbitos anidados se liberan desde el padre sin añadir ningún recorrido recursivo en la capa de vistas.

## Validación y coste

- TDD: el test inicial falla al faltar `State`, `Binding` y `ViewGraphScope`; después pasa con la implementación mínima.
- Mutación: descartar deliberadamente las escrituras de estado hace fallar el test principal con 13 errores. Se restauró
  la implementación y se volvió a ejecutar la batería.
- `Views`: 15 tests en debug y release, con **1 known issue de paridad** descrito arriba.
- Motor: 202 tests funcionales de debug, con sus 2 known issues preexistentes de M2. Sin cambios en sus fuentes.
- Los tres archivos de `Samples` pasan type-check tanto contra SwiftUI real como contra ShellUI.
- Release: **10.000 escrituras por Binding + evaluación de body + creación de Text: 14,104 ms** en una ejecución,
  aproximadamente 1,41 µs por actualización. Incluye el contador de uso de `Text`. No es un p99, una distribución de frames
  ni una comparación de velocidad con SwiftUI. Sin umbral de aceptación basado en una sola muestra.

Las salidas de la primera batería completa se conservan en `Views/Results/`. Para repetir:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test --package-path Views
swift test --package-path Views -c release -Xswiftc -enable-testing
swift test --package-path Views -c release -Xswiftc -enable-testing --filter PerformanceVerticalSliceUpdates
Views/Scripts/check-compat.sh
```

En un entorno con sandbox de SwiftPM restringido se usó `--disable-sandbox`, `--scratch-path /private/tmp/sag-slice` y
una caché de módulos bajo `/private/tmp`. El type-check se hizo con el SDK macOS de Xcode explícito y los módulos de ese scratch.

## Qué resuelve y qué sigue

La prueba demuestra el enlace con el motor y el control de vida de una composición fija. **No demuestra una UI completa
ni equivalencia general con SwiftUI.** El siguiente estudio es aislar la invalidación de `Binding` tras cambiar de rama
(con `State` directo, vistas hijas distintas y remontaje), antes de decidir si la capa de propiedades dinámicas debe
conservar información adicional. No corresponde alterar la poda exacta del motor solo para reproducir esta observación.

### Seguimiento: estudio de lecturas dinámicas

El [estudio posterior](ESTUDIO-LECTURAS-DINAMICAS.md) amplía este caso a State directo, dos formas de Binding, ramas
estructurales e identidad, con controles de lectura. La evaluación adicional también aparece con State directo:
no es exclusiva de Binding. La discrepancia de esta prueba se mantiene declarada; el núcleo conserva su poda exacta.
