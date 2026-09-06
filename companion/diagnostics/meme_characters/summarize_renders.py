#!/usr/bin/env python3
"""Index owned Windows mouth renders and measure front-view pink aperture growth."""

import argparse
import hashlib
import json
from pathlib import Path
from PIL import Image
import numpy as np

ROOT = Path(__file__).resolve().parents[2]


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--prefix", default="meme-spring-windows")
    args = parser.parse_args()
    prefix = args.prefix
    if Path(prefix).name != prefix:
        parser.error("prefix must be a single filename component")
    report = {
        "scope": "Owned Godot source-window captures, Windows RTX4090 D3D12 Forward+; static neutral/blink/vowels at0.3/0.6/1, front and45degrees. No live microphone/viseme timing claim.",
        "avatar_hashes": {
            n: sha(ROOT / "assets" / f"{n}.vrm") for n in ["mambo", "hachimi"]
        },
        "captures": [],
        "aperture_checks": [],
    }
    for angle in ["front", "45"]:
        for p in sorted((ROOT / "logs" / f"{prefix}-{angle}").glob("*.png")):
            report["captures"].append(
                {"path": str(p.relative_to(ROOT)), "sha256": sha(p), "angle": angle}
            )
    assert len(report["captures"]) == 76
    for name in ["mambo", "hachimi"]:
        for vowel in ["aa", "ih", "ou", "ee", "oh"]:
            areas = []
            for weight in [0.3, 0.6, 1.0]:
                p = (
                    ROOT
                    / f"logs/{prefix}-front"
                    / f"{name}-{vowel}-{weight}.png"
                )
                a = np.array(Image.open(p).convert("RGB"))[395:455, 180:300].astype(int)
                pink = (
                    (a[:, :, 0] > 200)
                    & (a[:, :, 0] - a[:, :, 1] > 25)
                    & (a[:, :, 2] - a[:, :, 1] > -5)
                    & (a[:, :, 2] < 230)
                )
                areas.append(int(pink.sum()))
            passed = all(y > x for x, y in zip(areas, areas[1:]))
            report["aperture_checks"].append(
                {
                    "character": name,
                    "vowel": vowel,
                    "weights": [0.3, 0.6, 1.0],
                    "pink_pixels": areas,
                    "strictly_increasing": passed,
                }
            )
            assert passed, (name, vowel, areas)
    report["process_log_sha256"] = sha(ROOT / f"logs/{prefix}.log")
    report["render_script_sha256"] = sha(
        ROOT / "diagnostics/meme_characters/render_mini.gd"
    )
    report["checks"] = 10
    report["failures"] = 0
    (ROOT / "diagnostics/meme_characters/windows-mouth-validation.json").write_text(
        json.dumps(report, indent=2) + "\n"
    )
    print("76 captures;10 mouth-aperture checks passed")


if __name__ == "__main__":
    main()
