#!/usr/bin/env python3
"""Build one fixture against Apple's installed graph and the local engine; compare process-isolated traces."""
import argparse
import concurrent.futures
import json
import os
from pathlib import Path
import shutil
import subprocess
import urllib.request

REVISION = "511cc728141f57dc325753f23898568ccd49c339"
REPOSITORY = "https://github.com/OpenSwiftUIProject/DarwinPrivateFrameworks"
PREFIX = "AG/2024/AttributeGraph.xcframework/macos-arm64e-arm64-x86_64/AttributeGraph.framework/Versions/A/"
SCENARIOS = [
    "dynamic", "cut", "lazy", "lifetime",
    "diamond-source-forward", "diamond-source-reverse",
    "diamond-multiple-forward", "diamond-multiple-reverse",
    "stateful-no-write-cut", "stateful-unread-input", "stateful-has-value-and-revert",
    "selector-input-order", "invalidate-in-rule", "weak-attribute-in-rule",
    "indirect-rule-and-redirect", "focus-keypath-cut",
    "slot-reuse-input-order", "duplicate-writes-before-read",
    "double-read-and-prune", "indirect-source-invalidated",
    "random-graph-oracle-trace", "random-graph-oracle-trace", "random-graph-oracle-trace",
    "random-graph-oracle-trace", "random-graph-oracle-trace", "random-graph-oracle-trace",
    "random-graph-oracle",
    "random-subgraph-weak-indirect-oracle-trace", "random-subgraph-weak-indirect-oracle-trace",
    "random-subgraph-weak-indirect-oracle-trace", "random-subgraph-weak-indirect-oracle-trace",
    "random-subgraph-weak-indirect-oracle-trace", "random-subgraph-weak-indirect-oracle-trace",
    "random-subgraph-weak-indirect-oracle", "map-and-property-wrappers",
    "without-update-read", "mutate-body-and-invalidate-value",
    "indirect-dependency-cut-and-redirect", "subgraph-flags-forEach-and-update",
    "has-value-validate-update-value", "without-subgraph-invalidation-and-ancestor",
    "breadth-first-search", "attribute-keypath-dynamic-member",
    "branch-switch-and-invalidate-before-read",
    "indirect-original-dies-while-redirected",
    "stateful-dependency-pruned-without-write",
    "initial-value-no-first-write",
    "nested-special-scopes",
    "reentrant-subgraph-invalidation",
    "weak-attribute-slot-reuse",
    "indirect-reset-source-multi-redirect",
    "indirect-chain-and-intermediate-death",
    "changed-value-after-skipped-and-indirect",
    "multi-observer-tree-order-and-cancel",
    "cc-create-input-in-rule-scoped",
    "cc-create-rule-in-rule-scoped",
    "cc-create-rule-every-run-scoped",
    "cc-create-rule-during-update-flags-scoped",
    "cc-caller-invalidated-after-input",
    "cc-caller-invalidated-after-rule",
    "cc-caller-falling-input",
    "cc-create-placement-caller-scope",
    "cc-create-placement-explicit-owner",
    "cc-closure-recreated-plain",
    "cc-closure-stable-plain",
    "cc-closure-captured-state-plain",
    "cc-closure-thin-plain",
    "cc-closure-stable-equatable",
    "cc-closure-captured-state-equatable",
    "offset-range-inside-outside",
]
SYSTEM_IMAGE = "/System/Library/PrivateFrameworks/AttributeGraph.framework/Versions/A/AttributeGraph"


def download(url):
    request = urllib.request.Request(url, headers={"User-Agent": "SwiftAttributeGraph-native-research"})
    with urllib.request.urlopen(request, timeout=30) as response:
        return response.read()


def prepare_interfaces(directory, sdk):
    framework = directory / "AttributeGraph.framework"
    marker = directory / "revision.txt"
    if not marker.exists() or marker.read_text().strip() != REVISION:
        tree = json.loads(download(f"https://api.github.com/repos/OpenSwiftUIProject/DarwinPrivateFrameworks/git/trees/{REVISION}?recursive=1"))
        paths = [item["path"] for item in tree["tree"] if item["path"].startswith(PREFIX)
                 and (item["path"].endswith(".h") or item["path"].endswith("module.modulemap")
                      or item["path"].endswith("arm64-apple-macos.swiftinterface"))]
        if not paths:
            raise RuntimeError("No research interfaces found at the pinned revision")
        def fetch(path):
            destination = framework / path.removeprefix(PREFIX)
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(download(f"https://raw.githubusercontent.com/OpenSwiftUIProject/DarwinPrivateFrameworks/{REVISION}/{path}"))
        with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
            list(pool.map(fetch, paths))
        marker.write_text(REVISION + "\n")
    # The link stub comes from this machine's SDK; no foreign implementation binary is downloaded.
    shutil.copyfile(Path(sdk) / "System/Library/PrivateFrameworks/AttributeGraph.framework/AttributeGraph.tbd",
                    framework / "AttributeGraph.tbd")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--interfaces", type=Path, default=Path("/private/tmp/sag-native-interfaces"))
    parser.add_argument("--scratch", type=Path, default=Path("/private/tmp/sag-native-comparison"))
    parser.add_argument("--output", type=Path, default=Path("/private/tmp/sag-native-results"))
    parser.add_argument("--repeats", type=int, default=3)
    args = parser.parse_args()
    if args.repeats < 1:
        parser.error("--repeats must be positive")
    if subprocess.check_output(["uname", "-m"], text=True).strip() != "arm64":
        parser.error("This interface probe currently supports macOS arm64 only")
    env = os.environ.copy()
    env.setdefault("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer")
    def capture(command):
        return subprocess.check_output(command, env=env, text=True, stderr=subprocess.STDOUT).strip()
    sdk = capture(["xcrun", "--sdk", "macosx", "--show-sdk-path"])
    compiler = capture(["xcrun", "--find", "swiftc"])
    swift = capture(["xcrun", "--find", "swift"])
    args.scratch.mkdir(parents=True, exist_ok=True)
    args.output.mkdir(parents=True, exist_ok=True)
    env["CLANG_MODULE_CACHE_PATH"] = str(args.scratch / "clang-modules")
    prepare_interfaces(args.interfaces, sdk)
    package = Path(__file__).resolve().parent
    sources = sorted(str(p) for p in (package / "Sources/Probe").glob("*.swift"))
    metadata = {"system": capture(["sw_vers", "-productVersion"]), "build": capture(["sw_vers", "-buildVersion"]),
                "swift": capture([compiler, "--version"]), "interface_revision": REVISION,
                "interface_repository": REPOSITORY, "sdk": sdk, "native_image": SYSTEM_IMAGE,
                "repeats": args.repeats, "scenarios": SCENARIOS, "probe_only": True}
    (args.output / "environment.json").write_text(json.dumps(metadata, indent=2) + "\n")
    for configuration in ["debug", "release"]:
        native = args.scratch / f"native-{configuration}"
        command = [compiler, "-sdk", sdk, "-target", "arm64-apple-macos15.0", "-module-cache-path",
                   str(args.scratch / "native-modules"), "-F", str(args.interfaces), "-D", "NATIVE_ATTRIBUTE_GRAPH",
                   "-O" if configuration == "release" else "-Onone", *sources, "-o", str(native)]
        with (args.output / f"compile-native-{configuration}.txt").open("w") as log:
            subprocess.run(command, env=env, stdout=log, stderr=log, check=True)
        linkage = capture(["otool", "-L", str(native)])
        (args.output / f"linkage-native-{configuration}.txt").write_text(linkage + "\n")
        if SYSTEM_IMAGE not in linkage or "SwiftUI.framework" in linkage:
            raise RuntimeError("Unexpected native linkage: not an isolated system AttributeGraph probe")
        build = [swift, "build", "--package-path", str(package), "--scratch-path", str(args.scratch / "own"),
                 "--disable-sandbox", "-c", configuration]
        with (args.output / f"compile-own-{configuration}.txt").open("w") as log:
            subprocess.run(build, env=env, stdout=log, stderr=log, check=True)
        binary_path = capture(build + ["--show-bin-path"])
        own = str(Path(binary_path) / "Probe")
        own_linkage = capture(["otool", "-L", own])
        (args.output / f"linkage-own-{configuration}.txt").write_text(own_linkage + "\n")
        if "AttributeGraph.framework" in own_linkage or "SwiftUI.framework" in own_linkage:
            raise RuntimeError("The local engine probe unexpectedly links an Apple graph or UI framework")
        for run in range(1, args.repeats + 1):
            outputs = []
            for label, binary in [("native", str(native)), ("own", own)]:
                result = subprocess.run([binary], env=env, text=True, capture_output=True)
                (args.output / f"{configuration}-{label}-{run}.txt").write_text(result.stdout)
                if result.stderr:
                    (args.output / f"{configuration}-{label}-{run}.stderr.txt").write_text(result.stderr)
                result.check_returncode()
                outputs.append(result.stdout)
            names = [line.split("|", 1)[0] for line in outputs[0].splitlines()]
            if outputs[0] != outputs[1] or names != SCENARIOS:
                raise RuntimeError(f"Trace mismatch: {configuration} run {run}; inspect {args.output}")
            print(f"PASS {configuration} run {run}: {len(SCENARIOS)} direct graph traces match", flush=True)
    print(f"Results: {args.output}", flush=True)


if __name__ == "__main__":
    main()
