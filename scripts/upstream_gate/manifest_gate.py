"""Validate every manifest Duck Studio can publish with Pollen's own validate_manifest.

    swift run --package-path scripts/upstream_gate/trgen ... (see README) > /tmp/app-manifests.jsonl
    python scripts/upstream_gate/manifest_gate.py /tmp/app-manifests.jsonl

Needs mjlab_microduck importable (the same environment as gate.py). Exits 1 on any refusal.
"""
import json
import sys

from mjlab_microduck.publish.manifest import validate_manifest

bad = 0
for line in open(sys.argv[1]):
    m = json.loads(line)
    try:
        validate_manifest(m)
        print(f"PASS {m['name']} kind={m.get('kind')} slot={m.get('slot')}")
    except Exception as e:  # noqa: BLE001
        bad += 1
        print(f"FAIL {m.get('name')}: {e}")
sys.exit(1 if bad else 0)
