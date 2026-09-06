"""Summarize explicitly named Windows runs; retain full evidence in local logs."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def summarize(directory: Path) -> dict:
    report_path = directory / "report.json"
    report = json.loads(report_path.read_text())
    build_path = directory / "build.json"
    build = json.loads(build_path.read_text())
    captures = []
    for capture in report["captures"]:
        path = directory / capture["file"]
        captures.append({**capture, "sha256": digest(path)})
    return {
        "raw_directory": str(directory),
        "report_sha256": digest(report_path),
        "build_record_sha256": digest(build_path),
        "executable_sha256": build["sha256"],
        "executable_bytes": build["bytes"],
        "source_stable_during_build": build["source_stable_during_build"],
        "probe_sha256": (directory / "probe-sha256.txt").read_text().strip(),
        "renderer": report["renderer"],
        "character": report["actual_character"],
        "model_sha256": report["actual_model_sha256"],
        "scale": report["actual_pet_scale"],
        "mode": report["mode"],
        "checks": report["checks"],
        "failures": report["failures"],
        "contacts": report["contacts"],
        "computer_contact": report.get("computer_contact", {}),
        "outcomes": [
            {key: row[key] for key in ("id", "verb", "outcome", "ms")}
            for row in report["outcomes"]
        ],
        "captures": captures,
        "capture_scope": "Own root viewport, shared 3D depth buffer while occupied; no external desktop-content capture.",
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, action="append", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    runs = [summarize(directory) for directory in args.input]
    result = {
        "selection": "All explicitly named final-package runs. Development failures are separately retained and described in README.md.",
        "runs": runs,
        "assertions": sum(len(run["checks"]) for run in runs),
        "failures": sum(run["failures"] for run in runs),
        "same_executable": len({run["executable_sha256"] for run in runs}) == 1,
        "analyzer_sha256": digest(Path(__file__)),
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, ensure_ascii=False, allow_nan=False) + "\n")
    print(json.dumps({key: result[key] for key in ("assertions", "failures", "same_executable")}))


if __name__ == "__main__":
    main()
