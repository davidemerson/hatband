#!/bin/sh
# Prints an -destination argument for an iOS simulator that actually exists on
# this machine, newest runtime first.
#
# Pinning a name ("iPhone 17") fails outright on a runner whose image carries a
# different set: v0.5.1's ios run died with "Unable to find a device matching
# the provided destination specifier" while four other runs of the same commit
# passed. Resolving by id at run time survives that.
set -eu

json=$(xcrun simctl list devices available --json)
id=$(printf '%s' "$json" | python3 -c '
import json, re, sys

def runtime_key(name):
    # com.apple.CoreSimulator.SimRuntime.iOS-26-1 -> (26, 1)
    found = re.findall(r"\d+", name.rsplit(".", 1)[-1])
    return tuple(int(n) for n in found) if found else (0,)

devices = json.load(sys.stdin)["devices"]
best = None
for runtime, entries in devices.items():
    if "iOS" not in runtime:
        continue
    for d in entries:
        if not d.get("isAvailable") or not d["name"].startswith("iPhone"):
            continue
        # Newest runtime, then highest model number, then the plainest name
        # ("iPhone 17" ahead of "iPhone 17 Pro Max") so the pick is predictable.
        key = (runtime_key(runtime), [int(n) for n in re.findall(r"\d+", d["name"])] or [0], -len(d["name"]))
        if best is None or key > best[0]:
            best = (key, d["udid"], d["name"], runtime)
if best is None:
    sys.exit("no available iPhone simulator")
sys.stderr.write("using %s on %s\n" % (best[2], best[3].rsplit(".", 1)[-1]))
print(best[1])
')
printf 'platform=iOS Simulator,id=%s' "$id"
