#!/usr/bin/env python3
"""
Scan heap pointers and layout structures of AttributeGraph processes using LLDB Python API.
Usage:
    ./Scripts/lldb_trace.py <binary_path> [args...]
"""
import sys
import os
import subprocess

LLDB_PY = "/Library/Developer/CommandLineTools/Library/PrivateFrameworks/LLDB.framework/Resources/Python"

def main():
    if len(sys.argv) < 2:
        print("Usage: ./Scripts/lldb_trace.py <binary_executable> [args...]")
        sys.exit(1)

    target_bin = sys.argv[1]
    extra_args = sys.argv[2:]

    # Ensure PYTHONPATH includes lldb
    env = os.environ.copy()
    existing_py = env.get("PYTHONPATH", "")
    env["PYTHONPATH"] = f"{LLDB_PY}:{existing_py}" if existing_py else LLDB_PY

    # LLDB driver inline script
    runner_script = f"""
import lldb
import sys

debugger = lldb.SBDebugger.Create()
debugger.SetAsync(False)
target = debugger.CreateTarget("{target_bin}")

if not target.IsValid():
    print("Error: Could not load target binary: {target_bin}")
    sys.exit(1)

print("[*] Target loaded:", target.GetExecutable().GetFilename())

# Set breakpoint on AGGraphCreate and create_graph
bp_create = target.BreakpointCreateByName("create_graph")
bp_shared = target.BreakpointCreateByName("_AGGraphCreateShared")
bp_getvalue = target.BreakpointCreateByName("_AGGraphGetValue")

print("[*] Breakpoints active:", target.GetNumBreakpoints())

launch_info = lldb.SBLaunchInfo({extra_args})
error = lldb.SBError()
process = target.Launch(launch_info, error)

if not error.Success():
    print("Launch error:", error.GetCString())
    sys.exit(1)

while process.GetState() == lldb.eStateStopped:
    thread = process.GetSelectedThread()
    frame = thread.GetSelectedFrame()
    func = frame.GetFunctionName()
    print(f"\\n--- Hit breakpoint: {{func}} ---")

    # Read registers
    regs = frame.GetRegisters()[0]
    for r in regs:
        if r.GetName() in ['x0', 'x1', 'x2', 'w0', 'w1', 'w2', 'x8', 'x19', 'x20', 'x21']:
            print(f"  {{r.GetName()}} = {{hex(r.GetValueAsUnsigned())}}")

    process.Continue()

print("[*] Process finished with state:", process.GetState())
"""

    p = subprocess.run([sys.executable, "-c", runner_script], env=env)
    sys.exit(p.returncode)

if __name__ == "__main__":
    main()
