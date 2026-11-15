# Estudio de lecturas dinámicas: State, Binding e identidad

Fecha: 2026-11-14. Experimento en Mac; Windows aplazado.

## Predicciones fijadas antes de ejecutar

La prueba vertical encontró una reevaluación adicional tras cambiar la rama de una expresión condicional.
Se contrastan estas explicaciones, sin asumir cómo funciona AttributeGraph por dentro:

- H1: SwiftUI poda las lecturas del cuerpo en cada evaluación, como el motor actual. Al cambiar a segundo, escribir
  primero no debe ejecutar el cuerpo seleccionado.
- H2: se conservan lecturas durante la vida de una propiedad dinámica o cuerpo. Escribir primero puede seguir
  ejecutándolo después del cambio. Recrear el cuerpo mediante identidad puede borrar esa información.
- H3: el efecto es específico de Binding. State directo debe podar aunque Binding no lo haga.

Se compararán State directo, Binding proyectado, Binding construido con cierres, ramas estructurales con hijos distintos,
un Binding que nunca se lee y un control que lee deliberadamente ambas entradas. El cambio explícito de identidad del
hijo se medirá por separado de cambiar la selección de datos. Se registrarán los cuerpos del padre y de los hijos para
no confundir una reevaluación del padre con una dependencia conservada en el hijo.

Los tests del motor mantienen la predicción H1: dependencias exactas y perezosas. Si los resultados nativos difieren,
se documenta la diferencia; no se altera su contrato para conseguir un recuento artificialmente igual.

## Protocolo

Mismo proceso de alojamiento con NSHostingView/AppKit, main thread y pasos separados por run loop. Los valores son Int,
sin geometría ni animaciones. Se medirá la secuencia de cuerpos y valores, no velocidad de dibujo. Cada cambio comprueba
que el valor esperado se estabilizó. Las escrituras sin cambio son controles negativos; leer ambas entradas es el positivo.
Las sondas y resultados se guardan en git, fuera del directorio local parity/.

## Descubrimiento y predicción de verificación (antes de ejecutar la secuencia inversa)

La primera observación refuta H1 para State directo y ambos tipos de Binding; también refuta H3 como explicación
exclusiva. Probar H1 como aserción produjo tres fallos, uno por caso; la rama estructural sí coincidió.

Se fijan los perfiles de diez acciones observados como oráculos de regresión y se predice **antes de medir** que, al
iniciar por segundo e invertir todas las escrituras, los mismos perfiles se mantendrán para directo, proyectado,
cierres, estructural y control de lectura doble. El control que solo lee segundo seguirá exclusivamente las escrituras
a segundo. La recreación por identidad del hijo debe borrar la lectura anterior en el Binding proyectado, mientras
que el cuerpo del propietario de State directo conserva su identidad. Esto último es una distinción de la sonda,
no una afirmación sobre la representación interna de Apple.

## Resultados observados

Mac M1, macOS 15.7.9, arm64, Swift 6.2.4 de Xcode. Los perfiles fijados pasan tanto en la secuencia original como en
la inversa, en procesos independientes de debug y release. Son **6 variantes × 2 direcciones × 10 acciones = 120 acciones
nativas por ejecución**; las acciones están relacionadas, no son 120 experimentos independientes.

Secuencia original (primero=0, segundo=100, inicialmente se lee primero):

1. Primero=1.
2. Primero=1 otra vez.
3. Seleccionar segundo.
4. Primero=2, ahora inactivo.
5. Recrear la identidad del contenido con `.id(generation)`; los State del padre permanecen.
6. Primero=3, todavía inactivo.
7. Segundo=101.
8. Volver a primero.
9. Segundo=102, ahora inactivo.
10. Primero=4.

La inversa inicia por segundo y cambia las fuentes y los valores simétricamente. Los oráculos de recuentos se fijaron
antes de ejecutarla: todas sus predicciones pasaron, también el control que solo lee segundo.

| Variante | Cuerpo seleccionado en paso 4 | Cuerpo seleccionado en paso 6 | Padre en escrituras de datos |
|---|---:|---:|---|
| State directo en el padre | 1 | 1 | Se evalúa |
| Binding proyectado con `$state` en hijo | 1 | **0** | No se evalúa |
| Binding construido con `get/set` en hijo | 1 | 1 | Se evalúa |
| Dos hijos distintos en ramas de `if` | **0** | **0** | No se evalúa |
| Binding recibido pero nunca leído (solo se lee segundo) | 0 | 0 | No se evalúa |
| Control: se leen ambas entradas | 1 | 1 | No se evalúa |

Los recuentos del padre excluyen el paso de identidad; el padre siempre se evalúa en ese paso. En la variante estructural
también se evalúa al cambiar la selección. El control de escritura sin cambio no ejecuta el cuerpo seleccionado en ningún
caso. Los valores finales coinciden con los esperados en los 120 pasos.

### Conclusiones limitadas a estas sondas

- **H1 no describe toda la semántica de vistas de SwiftUI.** Cambiar una lectura condicional dentro de un cuerpo que
  conserva identidad no basta para eliminar todas las reevaluaciones por la entrada anterior.
- **H3 queda refutada como explicación exclusiva:** State directo también muestra el efecto.
- **H2 es compatible con los datos**, con una precisión: la identidad del hijo importa en el Binding proyectado;
  cambiar solo la identidad del contenido no recrea el cuerpo propietario de State directo. No se ha identificado
  qué estructura interna conserva esa información.
- **La forma de construir un Binding importa.** En la sonda con cierres también se reevalúa el padre; con la proyección
  `$state`, no. No se atribuye esto a un mecanismo interno concreto sin otra prueba que lo aísle.
- **Separar ramas estructurales sí elimina la reevaluación por el dato de la rama retirada.** Los datos pertenecen al
  padre y siguen vivos; lo que se retira es el cuerpo hijo consumidor.
- **Recibir un Binding no basta para consumirlo:** las escrituras en la propiedad nunca leída no ejecutan al hijo.

## Consecuencia para nuestro motor

El oráculo propio ejecuta la misma secuencia de selección y recreación con dos políticas de lectura expresas:
solo la entrada activa, o ambas entradas como control positivo. En el primer caso registra `[1,0,1,0,1,0,1,1,0,1]`;
en el segundo, `[1,0,1,1,1,1,1,1,1,1]`. Comprueba dos o tres aristas exactas según la política, cuatro nodos vivos tras
cada paso y cero nodos/aristas al destruir al dueño. Esto coincide con la variante nativa estructural y con el control
de lectura doble respectivamente. No es una implementación general de esos árboles de vistas.

**No se modifica la poda del motor.** Se conserva la diferencia de paridad declarada en la primera prueba vertical.
La futura capa de propiedades dinámicas necesitará un contrato de identidad y seguimiento de lecturas sustentado por
estos resultados. Los datos no demuestran un defecto del núcleo ni justifican añadirle dependencias persistentes.
No se añaden recorridos ni algoritmos de producción: solo sondas, oráculos y documentación; no hay un coste nuevo
del motor que optimizar o presupuestar.

## Reproducción y límites

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test --package-path Views --filter dynamicRead
swift test --package-path Views -c release -Xswiftc -enable-testing --filter dynamicRead
```

Se ejecutó también la batería completa de Views en debug y release: **18 tests, 1 known issue preexistente de paridad**.
Las tres pruebas nuevas no ocultan diferencias mediante known issues: afirman todos sus perfiles nativos y el contrato
propio explícitamente. Fuentes: `Views/Tests/ShellUITests/DynamicReadProbeTests.swift`. Salidas completas en
`Views/Results/dynamic-reads-*.txt`, incluida la refutación de H1. No se volvió a ejecutar la batería completa del paquete
raíz en esta pieza: sus fuentes no cambiaron; sí se ejecutó el nuevo oráculo que usa el motor.

Cada acción tiene una ventana de procesamiento de 100 ms; los valores y recuentos se verifican al terminarla. Esto no
prueba que no pueda haber trabajo posterior bajo otras cargas. Tampoco mide latencia ni constituye una garantía sobre
otras versiones de macOS, tipos de valor o árboles arbitrarios. Los procesos se ejecutaron consecutivamente para evitar
interferencia entre ventanas de las propias sondas. Windows no se implementó ni se probó.

Siguiente estudio: separar las lecturas producidas al crear `Binding(get:set:)` de las que ocurren al evaluar al hijo,
y variar la identidad del propietario de State frente a la del consumidor. Esas pruebas permitirán afinar H2 antes de
promover una política de propiedades dinámicas a la implementación.
