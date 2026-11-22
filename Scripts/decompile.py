#!/usr/bin/env python3
"""
CLI wrapper to decompile any symbol in AttributeGraph or any binary using Ghidra Headless.
Usage:
    ./Scripts/decompile.py <SymbolName>
"""
import sys
import os
import subprocess

PROJECT_DIR = "/Users/erhusoft/SwiftAttributeGraph/scratch/ag_project"
PROJECT_NAME = "AGProject"
SCRIPTS_DIR = "/Users/erhusoft/SwiftAttributeGraph/scratch/ghidra"
GHIDRA_HEADLESS = "/opt/homebrew/Cellar/ghidra/12.2/libexec/support/analyzeHeadless"
JAVA_HOME = "/opt/homebrew/opt/openjdk@25"

def main():
    if len(sys.argv) < 2:
        print("Usage: ./Scripts/decompile.py <symbol_substring>")
        sys.exit(1)
        
    symbol = sys.argv[1]
    env = os.environ.copy()
    env["JAVA_HOME"] = JAVA_HOME

    cmd = [
        GHIDRA_HEADLESS,
        PROJECT_DIR,
        PROJECT_NAME,
        "-process", "AttributeGraph",
        "-noanalysis",
        "-scriptPath", SCRIPTS_DIR,
        "-postScript", "DecompileSymbol.java", symbol
    ]

    p = subprocess.Popen(cmd, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    
    in_block = False
    for line in p.stdout:
        if "<<<DECOMPILE_START>>>" in line:
            in_block = True
            print("=" * 60)
            continue
        elif "<<<DECOMPILE_END>>>" in line:
            in_block = False
            print("=" * 60 + "\n")
            continue
        elif "Target not found:" in line:
            print(line.strip())
            
        if in_block:
            print(line, end='')

    p.wait()

if __name__ == "__main__":
    main()
