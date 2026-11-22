# Toolkit de Ingeniería Inversa y Desensamblado Avanzado

Este documento detalla la metodología y las herramientas integradas en el entorno local (macOS Apple Silicon) para inspeccionar binarios nativos de Apple (`AttributeGraph.framework`), desensamblar a nivel de instrucción, descompilar a pseudo-código C/C++ de alta fidelidad y realizar trazado dinámico de memoria y heap en tiempo de ejecución.

---

## 1. Herramientas instaladas en el sistema

| Herramienta | Motor / Versión | Ubicación | Uso principal |
|---|---|---|---|
| **Ghidra Headless** | Ghidra 12.2 + OpenJDK 25 | `/opt/homebrew/Cellar/ghidra/12.2/` | Descompilación estática masiva o granular a C/C++ |
| **Rizin** | Rizin 0.9.1 (fork moderno de radare2) | `/opt/homebrew/bin/rizin` | Desensamblado rápido por CLI, control flow graphs, cross-references |
| **LLDB Python API** | LLDB 1700 (Apple Swift 6.1.2) | `/Library/Developer/CommandLineTools/.../LLDB.framework` | Trazado dinámico de heap, llamadas, inspección de registros en vivo |

---

## 2. Herramientas de automatización (`Scripts/`)

### `Scripts/decompile.py`
Permite descompilar cualquier función o símbolo de `AttributeGraph` a C/C++ directamente en la terminal en ~2-3 segundos, utilizando la base de datos pre-analizada en `scratch/ag_project`.

**Uso:**
```bash
./Scripts/decompile.py <nombre_o_subcadena_del_simbolo>
```

**Ejemplos:**
```bash
# Descompilar creación de grafos
./Scripts/decompile.py "_AGGraphCreateShared"
./Scripts/decompile.py "create_graph"

# Descompilar lectura/escritura de valores
./Scripts/decompile.py "_AGGraphGetValue"
./Scripts/decompile.py "_AGGraphSetValue"

# Descompilar exportación a JSON
./Scripts/decompile.py "AGGraphArchive"
```

---

### `Scripts/lldb_trace.py`
Permite ejecutar un binario de prueba (como `NativeProbe`) conectando automáticamente el debugger LLDB mediante Python scripting, interceptando breakpoints clave (`create_graph`, `_AGGraphGetValue`, etc.) y volcando el contenido de los registros y offsets de memoria.

**Uso:**
```bash
./Scripts/lldb_trace.py <ruta_del_binario> [argumentos...]
```

---

## 3. Desensamblado rápido interactivo con Rizin

Para inspeccionar instrucciones específicas, saltos y referencias cruzadas (XREFs) de forma inmediata:

```bash
# Desensamblar una función completa
rizin -qc "aaa; s sym._AGGraphCreateShared; pdf" "/Users/erhusoft/Library/Developer/Xcode/iOS DeviceSupport/iPhone15,4 27.0.1 (24A446)/Symbols/System/Library/PrivateFrameworks/AttributeGraph.framework/AttributeGraph"

# Listar funciones de un módulo
rizin -qc "aaa; afl" "<binario>" | grep -i "Graph"
```

---

## 4. Hallazgos clave obtenidos con el nuevo toolkit

1. **`_AGGraphCreate` vs `_AGGraphCreateShared`**:
   - `_AGGraphCreate()` ejecuta exactamente:
     ```c
     create_graph((AGGraphStorage *)0x0, 1);
     ```
   - `_AGGraphCreateShared(AGGraphStorage *param_1)` ejecuta:
     ```c
     create_graph(param_1, 1);
     ```
   - Ambas delegan directamente a `create_graph(AGGraphStorage*, unsigned int)`.

2. **Estructura de `create_graph`**:
   - Asigna un handle CF/AGGraph de tamaño `0x50` bytes (`func_0x0001900ce6a0(0, typeID, 0x50, 0)`).
   - Si `param_1 == NULL`, asigna el estado interno del grafo (`Graph`) de tamaño `0x1b8` bytes y llama al constructor `AG::Graph::Graph(this, flags)`.
   - Si `param_1 != NULL`, extrae el puntero al estado compartido desde `*(param_1 + 0x10)` e incrementa el contador de referencias en `*(this + 0x170)`.
   - Inicializa el contexto local del nuevo handle en `*(handle + 0x10)` mediante `AG::Graph::Context::Context((Context *)(handle + 0x10), this)`.
   - Configura el byte de flag en `*(handle + 0x58) = 0`.

3. **Lectura y escritura en `_AGGraphGetValue` / `_AGGraphSetValue`**:
   - Las lecturas y escrituras no consultan el handle `AGGraphRef` directamente.
   - Acceden directamente a la tabla global compartida: `AG::data::_shared_table_bytes`.
   - A partir del `AttributeID` indexan `_shared_table_bytes + (attributeID & 0xfffffe00)` para localizar el puntero al `Graph` en offset `+0x28`.
