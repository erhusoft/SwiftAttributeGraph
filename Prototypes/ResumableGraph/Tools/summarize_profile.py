"""Summarize an xctrace time-profile XML export using only Python's standard library."""

import argparse
import collections
import xml.etree.ElementTree as ET


def summarize(path):
    root = ET.parse(path).getroot()
    references = {element.attrib["id"]: element for element in root.iter() if "id" in element.attrib}

    def resolve(element):
        return references[element.attrib["ref"]] if "ref" in element.attrib else element

    self_weights = collections.Counter()
    inclusive_weights = collections.Counter()
    total = 0
    samples = 0
    for row in root.iter("row"):
        backtrace = row.find("backtrace")
        weight = row.find("weight")
        if backtrace is None or weight is None:
            continue
        names = [resolve(frame).attrib.get("name", "?") for frame in resolve(backtrace)]
        if not any("PrototypeGraph.update" in name for name in names):
            continue
        value = int(resolve(weight).text)
        samples += 1
        total += value
        self_weights[names[0]] += value
        for name in set(names):
            inclusive_weights[name] += value

    if not total:
        raise SystemExit("No samples containing PrototypeGraph.update were found.")
    print(f"Samples during PrototypeGraph.update: {samples}; weighted CPU: {total / 1e6:.2f} ms")
    for label, weights in [("SELF", self_weights), ("INCLUSIVE (overlapping; do not sum)", inclusive_weights)]:
        print(label)
        for name, value in weights.most_common(30):
            print(f"{100 * value / total:6.2f}% {name}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("xml", help="xctrace XML containing the time-profile table")
    summarize(parser.parse_args().xml)
