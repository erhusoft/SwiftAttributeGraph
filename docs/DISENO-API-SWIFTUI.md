# Plan de la API compatible con SwiftUI: inventario y cascarones (borrador, pendiente de aprobación)

Fecha: 2026-11-14. Relación: [PLAN-MOTOR.md](PLAN-MOTOR.md) §5 (conexión con la UI) y [INFORME-RENDIMIENTO.md](INFORME-RENDIMIENTO.md). **Estado:
propuesta. No se escribe ni se ejecuta nada hasta que el dueño la apruebe.** Es un plan de trabajo de la capa de vistas
(SwiftGraph), no del motor: el motor no sabe nada de vistas (`AGENTS.md` §1).

## 1. Idea (del dueño)

El Mac tiene el SDK y SwiftUI real; Windows es donde se construirá la UI. Primero se fija **la forma de la API** (los tipos y sus
firmas, sin el comportamiento) y después se implementa la lógica poco a poco en Windows, usando el motor y la especificación
medida del comportamiento de SwiftUI. Ejemplo: existe el `struct ScrollView` con sus constructores, y su layout, recorte,
desplazamiento y dibujo se escriben cuando la UI los necesita.

## 2. Qué hay en el SDK (comprobado en solo lectura)

SwiftUI se reparte en dos módulos; cada uno trae su interfaz pública en texto (`.swiftinterface`):

| Módulo | Líneas | Tipos públicos (aprox.) | Extensiones | Qué contiene (de lo comprobado) |
|---|---|---|---|---|
| `SwiftUICore` | ≈ 22.100 | ≈ 280 | ≈ 1.390 | `View`, `ViewBuilder`, `State`, `Environment`, `ForEach`, `VStack`, `HStack`, `Text`, parte de `Binding` |
| `SwiftUI` | ≈ 27.100 | ≈ 590 | ≈ 1.880 | `ScrollView`, `Button`, `List`, `Binding` (parte), el resto de controles y modificadores |

`@Observable` está en el módulo `Observation`, no en SwiftUI. Los módulos importan `Combine`, `CoreData`, `Spatial`, `Symbols`,
`UniformTypeIdentifiers`, `OSLog` y otros, casi ninguno disponible en Windows.

## 3. Precaución legal (el dueño decide; no es asesoramiento legal)

Los archivos de interfaz son del SDK de Apple y se rigen por su acuerdo de licencia, que limita su uso al desarrollo para plataformas de
Apple, y además incluyen **cuerpos de funciones con código de Apple**. Por eso este plan **no copia declaraciones literales**:
- Del SDK se extrae únicamente **información** (nombre del símbolo, tipo, módulo y número de miembros) para llevar la cobertura.
- Las declaraciones se **escriben a mano** a partir de la documentación pública y de la especificación medida, como hacen
  proyectos abiertos como OpenSwiftUI.
- Antes de copiar nada literal, el dueño revisa la licencia del SDK.

## 4. Tres capas

1. **API (cascarones):** nombres, firmas, etiquetas y valores por omisión. Este plan.
2. **Semántica de vistas:** cuándo corre cada `body`, estado, entorno, listas y ramas. Ya existe en el motor, con el comportamiento medido en
   SwiftUI real (paridad M2 a M5 y banco comparativo).
3. **Backend de Windows:** layout, dibujo, entrada y ventanas. Falta por construir y vive en SwiftGraph.

## 5. Inventario de la API

Un script (Swift o Python, en el Mac, local) lee los `.swiftinterface` y genera una tabla **versionable**, sin código de Apple:

| Columna | Contenido |
|---|---|
| Símbolo | `ScrollView`, `ScrollView.init(_:showsIndicators:content:)`… (solo el nombre y el rol de cada miembro) |
| Módulo y tipo | `SwiftUI`, `SwiftUICore`; struct, protocolo, modificador, propiedad envolvente… |
| Disponibilidad | macOS desde qué versión |
| Estado | `pendiente` / `cascarón` / `implementado` / `descartado`, con una nota |
| Uso | cuántas veces aparece en el código de apps de ejemplo (§6) |

Para qué sirve: medir el avance («85 de 590 tipos»), ordenar por uso real, no olvidar miembros de un tipo (un `ScrollView` incompleto),
generar pruebas y detectar cambios entre versiones de macOS comparando dos inventarios. **No dice cómo se comporta nada.**

## 6. Prioridades: empezar por lo que usa una app

1. Se reúne un conjunto pequeño de **apps de ejemplo** (escritas por nosotros, o código abierto con licencia compatible) y se cuentan las
   apariciones de cada símbolo.
2. Primer corte (hipótesis a confirmar con el recuento): `View`, `ViewBuilder`, `Text`, `VStack`, `HStack`, `ZStack`, `Spacer`, `ScrollView`,
   `Button`, `State`, `Binding`, `Environment`, `ForEach`, `List`, `@Observable`, `padding`, `frame`, `foregroundStyle`, `onAppear`.
3. Lo demás se añade según aparezca en las apps.

## 7. Cascarones: cómo se comportan hasta que se implementan

- **Forma:** firmas idénticas (etiquetas, valores por omisión, constructores de resultados). Es lo que permite que el código fuente compile igual.
- **Sin implementar ≠ en silencio:** un cascarón sin lógica **registra** que se usó (un contador por símbolo) y, en modo estricto,
  detiene el programa con «`ScrollView` sin implementar». Así una pantalla en blanco nunca es un fallo silencioso.
- **Informe de cobertura:** al terminar una ejecución se puede listar qué símbolos fueron cascarón y cuáles reales.

## 8. Prueba de compatibilidad de código fuente

La prueba que demuestra que la API es compatible, mecánica y repetible:
1. Un archivo de ejemplo usa un grupo de símbolos.
2. En el Mac se compila contra **SwiftUI real** (y se ejecuta con el banco de paridad existente).
3. En Windows (y también en el Mac, contra el módulo propio) se compila **el mismo archivo** contra el módulo propio.
4. Si compila en ambos, las firmas coinciden. Si además el recuento de `body` por mutación coincide con el medido en SwiftUI, el
   comportamiento coincide en lo observable.

Los archivos de ejemplo y sus resultados esperados se versionan; el código de las rondas de medida contra SwiftUI sigue en `parity/` (local).

## 9. Riesgos y límites

- **Tamaño:** ≈ 870 tipos y miles de miembros entre los dos módulos, sin contar `AppKit`/`UIKit`. Solo se cubrirá lo que usen las apps de
  ejemplo; el resto queda como `pendiente` a propósito.
- **Compatibilidad parcial:** una firma igual no garantiza el mismo comportamiento (layout, animaciones, accesibilidad); eso se comprueba
  con medidas, no con el inventario.
- **Dependencias de Apple ausentes en Windows** (`Combine`, `CoreData`, `UniformTypeIdentifiers`…): hay que decidir qué sustituir y qué dejar fuera.
- **Licencia del SDK** (§3).
- **El comportamiento medido es de una versión** (macOS 15.7.9). Si Apple cambia algo, se actualiza la especificación y se comparan inventarios.
- **No se toca el motor.** Si la UI pide algo que el motor no da, se anota para una pieza nueva del plan.

## 10. Orden de trabajo

1. Script de inventario en el Mac y primera tabla, **solo nombres y recuentos**. Informe corto.
2. Apps de ejemplo y recuento de uso; primer corte de prioridades (§6).
3. Cascarones del primer corte con su registro de uso, y prueba de compatibilidad (§8) de cada uno.
4. Preparar el paso a Windows: qué sustituyen `Combine`, `UniformTypeIdentifiers` y los demás.
5. Implementar el comportamiento de cada tipo en Windows, de menor a mayor, con tests y paridad.

## 11. Preguntas para el dueño

1. ¿Aceptas el criterio «no copiar declaraciones literales, solo inventario y escritura propia» (§3)? ¿Quieres consultar la licencia del SDK?
2. ¿Dónde vive este trabajo: en este repositorio (carpeta nueva `Views/`), o en SwiftGraph?
3. ¿Qué apps de ejemplo usamos para el recuento de prioridades?
4. ¿El inventario se versiona (solo nombres y recuentos)? Propongo que sí.
