#!/usr/bin/env python3
"""Run an isolated Jolt cloth experiment without changing the pet project."""
from pathlib import Path
import argparse
import os
import shutil
import subprocess
import tempfile


def main() -> int:
    companion = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", type=Path, default=companion / "tools/Godot_v4.5.2-stable_linux.x86_64")
    parser.add_argument("--output", type=Path, default=companion / "logs/cloth-physics")
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="mate-cloth-") as directory:
        project = Path(directory)
        shutil.copy2(companion / "native/tools/probe_cloth_physics.gd", project / "probe.gd")
        (project / "project.godot").write_text('config_version=5\n[application]\nconfig/name="Mate Cloth Physics Probe"\n[physics]\n3d/physics_engine="Jolt Physics"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n')
        env = dict(os.environ, CLOTH_OUTPUT=str(output))
        if Path("/usr/lib/wsl/lib").is_dir():
            env.update(MESA_LOADER_DRIVER_OVERRIDE="d3d12", GALLIUM_DRIVER="d3d12", MESA_D3D12_DEFAULT_ADAPTER_NAME="NVIDIA")
        with (output / "process.log").open("w") as log:
            result = subprocess.run([str(args.engine.resolve()), "--path", str(project), "--script", "res://probe.gd"], env=env, stdout=log, stderr=subprocess.STDOUT, timeout=90)
        print(output)
        return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
