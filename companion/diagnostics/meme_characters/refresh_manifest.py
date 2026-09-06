#!/usr/bin/env python3
"""Refresh generated mini asset hashes/provenance without replacing authored personas."""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def main():
    manifest = ROOT / "character-assets.json"
    items = json.loads(manifest.read_text())
    for ident in ["mambo", "hachimi"]:
        prov = json.loads(
            (
                ROOT / "diagnostics/meme_characters" / f"{ident}-asset-provenance.json"
            ).read_text()
        )
        wet = json.loads(
            (
                ROOT
                / "diagnostics/meme_characters"
                / f"{ident}-wet-asset-provenance.json"
            ).read_text()
        )
        p = ROOT / "characters" / f"{ident}.json"
        d = json.loads(p.read_text())
        d["package"]["provenance"] = {k: v for k, v in prov.items() if k != "vrm"}
        d["package"]["provenance"]["optional_wet_variant"] = {
            k: v for k, v in wet.items() if k != "vrm"
        }
        d["package"]["motion_ids"] = ["playful_strut", "mambo_goofy_walk"]
        p.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n")
        for item in items:
            if item["id"] == ident:
                item["vrm"]["sha256"] = prov["sha256"]
                item["vrm"]["optional_wet_sha256"] = wet["sha256"]
    manifest.write_text(json.dumps(items, ensure_ascii=False, indent=2) + "\n")


if __name__ == "__main__":
    main()
