# Traspaso de SwiftAttributeGraph

Fecha: 2026-11-14. Nota para el siguiente agente. La fuente de verdad del estado sigue siendo [PLAN-MOTOR.md](PLAN-MOTOR.md).

**Qué es:** un motor de grafo de atributos en Swift puro, sin dependencias, para sostener una UI con sintaxis de SwiftUI. Se verifica en un
Mac M1 (macOS 15.7.9) contra SwiftUI real. Windows ARM64 es el destino final y está **aplazado**.

**Léelo antes de tocar nada:** [AGENTS.md](../AGENTS.md), [PLAN-MOTOR.md](PLAN-MOTOR.md) y [INFORME-RENDIMIENTO.md](INFORME-RENDIMIENTO.md) (con sus
salvedades). Responde y documenta en español; el código, los `///` y los commits en inglés.

## Estado
- **Hecho y en verde:** M0 a M9 en Mac. 202 pruebas en depuración y 219 en release, con 2 «known issues» de M2 declarados.
- **GitHub:** `erhusoft/SwiftAttributeGraph` (privado). `master` y `m7-efficient-edge-removal` estaban al día al escribir esto. La rama contiene casi todo
  lo posterior a M4.
- **M4 (parcial):** las reglas síncronas conservan un límite de profundidad (unos miles de niveles). Solo `ResumableRule` lo evita, a costa de
  escribir máquinas de estados.
- **Paridad con SwiftUI:** medida en 6 rondas. La regla que la explica está en [DISENO-M2.md](DISENO-M2.md) (hipótesis H3; acierta 60/60 en la ronda 6).
- **`Views/`:** paquete aparte con cascarones de SwiftUI escritos a mano (`Text`, `VStack`, `HStack`, `ZStack`, `Spacer`, `ScrollView`, `Button`,
  `ForEach`, `List`, `padding`). Los mismos ejemplos compilan contra SwiftUI real y contra los cascarones (`Views/Scripts/check-compat.sh`).
- **Inventario de la API:** [inventario-api-swiftui.csv](inventario-api-swiftui.csv) y [INVENTARIO-API-SWIFTUI.md](INVENTARIO-API-SWIFTUI.md), solo
  nombres y recuentos. Plan: [DISENO-API-SWIFTUI.md](DISENO-API-SWIFTUI.md).

## Cómo trabajar aquí
```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer   # Swift 6.2.4; el de las Command Line Tools es 6.1 y no compila
swift test --skip Performance                                       # depuración
swift test -c release -Xswiftc -enable-testing                      # release con rendimiento
```
- **Git:** no toques la configuración global. Commit con `git -c user.name="…" -c user.email="…" commit -F archivo.txt`, mensajes en inglés y con la
  línea `Co-Authored-By`.
- **Push:** `gh` tiene sesión iniciada y el repositorio usa `gh` como asistente de credenciales (configuración local). Haz push solo si el dueño lo pide.
- **TDD:** test primero, verlo fallar, implementar, y comprobar con una mutación que el test detecta el fallo.

## Lo que no está en git
`parity/` es material local del dueño (sondas contra SwiftUI real: `SwiftUIProbe`, `Compare`, `Bench`, `Inventory` y sus resultados). **No existe fuera
de este Mac.** Si lo necesita el siguiente agente, hay que copiarlo.

## Pendiente y decisiones abiertas
1. **`State`, `Binding`, `Environment` y `@Observable`** en `Views/`, enlazados al motor. Es lo siguiente y es donde los cascarones pasan a tener
   comportamiento; debe coincidir con el recuento de `body` medido en SwiftUI.
2. **M4:** definir cómo se escriben los `body` de la UI. Con cierres síncronos hay un límite de profundidad; con reglas reanudables hay que escribirlos
   por etapas. Es una decisión del dueño.
3. **Apps de ejemplo** para contar qué API se usa más y ordenar prioridades. Sin definir.
4. **Memoria del motor:** medirla con `estimatedMemoryFootprint`; la medida por memoria residente no sirve a esa escala.
5. **Windows:** compilar y probar. El riesgo principal es `Comparison/TypeLayout.swift`, que usa funciones de reflexión internas del runtime con `@_silgen_name`.
6. **Compute** (`jcmosc/Compute`) como referencia de motor: no se puede ahora porque pide Swift 6.3.

## Trampas que ya nos mordieron
- **El SDK instalado es 26.2 y lo medido es macOS 15.7.9.** Puede haber símbolos en el inventario que no existan en tiempo de ejecución.
- **Estado frío de SwiftUI:** la primera comparación de un tipo en un proceso se comporta «solo bytes». Las medidas de paridad hay que tomarlas en caliente.
- **No copies declaraciones de los `.swiftinterface` del SDK.** Tienen cuerpos con código de Apple y licencia propia. Solo se extraen nombres.
- **Informes:** matiza lo que no está medido. Ya hubo que corregir afirmaciones como «cero recursión» o «motor al 100 %».
