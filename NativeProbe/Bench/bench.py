#!/usr/bin/env python3
import os, statistics, subprocess, sys

BENCH_DIR = os.path.dirname(os.path.abspath(__file__))
SCRATCH = "/Users/erhusoft/NativeAttributeGraphBackendProbe/native-scratch/bench"
INTERFACES = "/Users/erhusoft/NativeAttributeGraphBackendProbe/native-interfaces"
REPORT = "/Users/erhusoft/NativeAttributeGraphBackendProbe/BENCH_NATIVO_VS_PROPIO.md"
os.makedirs(SCRATCH, exist_ok=True)

env = os.environ.copy()
env["DEVELOPER_DIR"] = "/Applications/Xcode.app/Contents/Developer"

native_bin = os.path.join(SCRATCH, "bench-native")
subprocess.run([
    "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc",
    "-sdk", "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.2.sdk",
    "-target", "arm64-apple-macos15.0",
    "-module-cache-path", os.path.join(SCRATCH, "native-modules"),
    "-F", INTERFACES, "-D", "NATIVE_ATTRIBUTE_GRAPH", "-O",
    os.path.join(BENCH_DIR, "Sources/main.swift"),
    "-o", native_bin
], env=env, check=True)

subprocess.run([
    "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift",
    "build", "--package-path", BENCH_DIR,
    "--scratch-path", os.path.join(SCRATCH, "own"),
    "--disable-sandbox", "-c", "release"
], env=env, check=True)
own_bin = os.path.join(SCRATCH, "own/arm64-apple-macosx/release/Bench")

WORKLOADS = [
    ("create-inputs-rules", [1000, 10000, 100000]),
    ("hot-chain", [1000, 10000, 100000]),
    ("fan-out", [1000, 10000, 100000]),
    ("fan-in", [1000, 10000, 100000]),
    ("diamond-layers", [1000, 10000, 100000]),
    ("batch-writes", [1000, 10000]),
    ("equal-write-cut", [1000, 10000, 100000]),
    ("subgraph-churn", [1000, 10000, 100000]),
    ("display-list-shape", [1000, 10000, 100000]),
    ("cold-read-moderate", [1000, 5000]),
]

def run_one(bin_path, w, n):
    res = subprocess.run([bin_path, w, str(n)], capture_output=True, text=True, timeout=60)
    if res.returncode != 0:
        return None
    parts = res.stdout.strip().split("|")
    return float(parts[3]), int(parts[4]), int(parts[5])

rows = []
ratios = []
for w, sizes in WORKLOADS:
    for n in sizes:
        try:
            _ = run_one(native_bin, w, n)
            _ = run_one(own_bin, w, n)
            nat_samples, own_samples = [], []
            nat_vr, own_vr = None, None
            for _ in range(5):
                r1 = run_one(native_bin, w, n)
                r2 = run_one(own_bin, w, n)
                if r1 is None or r2 is None:
                    raise RuntimeError("crash/timeout")
                nat_samples.append(r1[0]); nat_vr = (r1[1], r1[2])
                own_samples.append(r2[0]); own_vr = (r2[1], r2[2])
            if nat_vr != own_vr:
                rows.append(f"| `{w}` | {n} | — | — | no comparable | nat={nat_vr} vs own={own_vr} |")
                continue
            nm, nmin, nmax = statistics.median(nat_samples), min(nat_samples), max(nat_samples)
            om, omin, omax = statistics.median(own_samples), min(own_samples), max(own_samples)
            ratio = om / nm if nm > 0 else 0.0
            unstable = []
            if (nmax - nmin) > 0.2 * nm: unstable.append("nativo")
            if (omax - omin) > 0.2 * om: unstable.append("propio")
            note = f"runs={nat_vr[1]}" + (f" (inestable: {','.join(unstable)})" if unstable else "")
            rows.append(f"| `{w}` | {n} | {nm:.2f} ms [{nmin:.2f}–{nmax:.2f}] | {om:.2f} ms [{omin:.2f}–{omax:.2f}] | {ratio:.2f}x | {note} |")
            ratios.append((ratio, w, n, nm, om))
        except Exception as e:
            rows.append(f"| `{w}` | {n} | — | — | omitido | {e} |")

ratios.sort(reverse=True)
top3 = "\n".join([f"- `{w}` (N={n}): **{r:.2f}x** (nativo {nm:.2f} ms vs propio {om:.2f} ms)" for r, w, n, nm, om in ratios[:3]])

md = f"""# Benchmark Nativo vs Propio (`release`)

Fecha: 2026-11-19 | Máquina: Mac arm64, macOS 15.x, Swift 6.2.4 | 1 calentamiento + mediana de 5 repeticiones.

## Cómo leerlo
Nuestro motor omite trabajo que realiza el `AttributeGraph.framework` nativo (trazas de depuración, banderas de subgrafo adicionales, protecciones de hilo en runtime y metadata C++), por lo que una razón `< 1.0x` **no** prueba superioridad; una razón `> 1.0x` sí señala trabajo pendiente de optimización.

## Resultados

| Carga | N | Nativo (mediana [rango]) | Propio (mediana [rango]) | Razón (propio/nativo) | Notas |
|---|---|---|---|---|---|
""" + "\n".join(rows) + f"""

## 3 cargas con razón más desfavorable
{top3}
"""
open(REPORT, "w").write(md)
print("DONE")
for r in rows: print(r)
print("TOP3:\n" + top3)
