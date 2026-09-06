#!/usr/bin/env python3
"""Check actual installed mini VRM geometry, expression coverage and voice assets."""

import hashlib
import json
from pathlib import Path
import struct
import wave
import numpy as np

ROOT = Path(__file__).resolve().parents[2]


def digest(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def glb(p):
    b = p.read_bytes()
    size, kind = struct.unpack_from("<II", b, 12)
    assert b[:4] == b"glTF" and kind == 0x4E4F534A
    d = json.loads(b[20 : 20 + size])
    start = 20 + size + 8
    return d, b[start:]


def accessor(d, b, ix):
    a = d["accessors"][ix]
    v = d["bufferViews"][a["bufferView"]]
    off = v.get("byteOffset", 0) + a.get("byteOffset", 0)
    n = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}[a["type"]]
    dtype = {5126: "<f4", 5123: "<u2", 5125: "<u4"}[a["componentType"]]
    return np.frombuffer(b, dtype=dtype, count=a["count"] * n, offset=off).reshape(
        -1, n
    )


def run():
    rows = []
    for ident in ["mambo", "hachimi"]:
        profile = json.loads((ROOT / "characters" / f"{ident}.json").read_text())
        row = {
            "id": ident,
            "profile_sha256": digest(ROOT / "characters" / f"{ident}.json"),
            "variants": [],
        }
        for suffix in ["", "-wet"]:
            p = ROOT / "assets" / f"{ident}{suffix}.vrm"
            d, b = glb(p)
            checks = []

            def check(x, label):
                checks.append({"check": label, "passed": bool(x)})
                if not x:
                    raise AssertionError((ident, suffix, label))

            mouth = [m for m in d["meshes"] if m["name"] == "M_Mouth"]
            cover = [m for m in d["meshes"] if m["name"] == "M_Mouth_skin_cover"]
            check(
                len(mouth) == 1 and len(cover) == 1,
                "one mouth surface and persistent skin cover",
            )
            prim = mouth[0]["primitives"][0]
            base = accessor(d, b, prim["attributes"]["POSITION"])
            check(len(prim["targets"]) == 5, "five vowel shape targets")
            for i, t in enumerate(prim["targets"]):
                delta = accessor(d, b, t["POSITION"])
                heights = []
                for w in [0, 0.3, 0.6, 1.0]:
                    vertices = base + delta * w
                    check(np.isfinite(vertices).all(), f"vowel {i} weight {w} finite")
                    heights.append(float(np.ptp(vertices[:, 1])))
                check(
                    all(b > a for a, b in zip(heights, heights[1:])),
                    f"vowel {i} aperture grows continuously",
                )
            coverprim = cover[0]["primitives"][0]
            check(
                not coverprim.get("targets") and not cover[0].get("weights"),
                "skin cover never collapses with speech",
            )
            texture_names = [x["name"] for x in d["images"]]
            check(
                any(
                    ("tex_mbdy" if not suffix else "tex_bdy") in x
                    for x in texture_names
                ),
                "actual intended dry mini or wet diffuse selection",
            )
            meshes = []
            for m in d["meshes"]:
                for primitive in m["primitives"]:
                    for a in primitive["attributes"].values():
                        check(
                            np.isfinite(accessor(d, b, a)).all(),
                            "finite installed vertex attribute",
                        )
                meshes.append({"name": m["name"], "primitives": m["primitives"]})
            row["variants"].append(
                {
                    "variant": "dry" if not suffix else "wet",
                    "sha256": digest(p),
                    "bytes": p.stat().st_size,
                    "checks": len(checks),
                    "failures": 0,
                    "mesh_layout_sha256": hashlib.sha256(
                        json.dumps(meshes, sort_keys=True).encode()
                    ).hexdigest(),
                    "geometry_sha256": hashlib.sha256(
                        b"".join(
                            accessor(d, b, i).tobytes()
                            for i in range(len(d["accessors"]))
                        )
                    ).hexdigest(),
                    "humanoid_bones": len(
                        d["extensions"]["VRM"]["humanoid"]["humanBones"]
                    ),
                }
            )
        assert (
            row["variants"][0]["geometry_sha256"]
            == row["variants"][1]["geometry_sha256"]
        ), "dry/wet must preserve identical geometry"
        ref = ROOT / profile["assets"]["reference_audio"]
        with wave.open(str(ref)) as w:
            row["voice"] = {
                "sha256": digest(ref),
                "channels": w.getnchannels(),
                "sample_rate": w.getframerate(),
                "seconds": w.getnframes() / w.getframerate(),
            }
            assert (
                w.getnchannels() == 1
                and w.getframerate() == 32000
                and 3 <= row["voice"]["seconds"] <= 10
            )
        rows.append(row)
    out = {
        "scope": "Actual installed GLB/VRM numeric and reference-WAV checks; not GPU rendering or subjective voice similarity.",
        "rows": rows,
        "checks": sum(v["checks"] for r in rows for v in r["variants"]) + 8,
        "failures": 0,
    }
    (ROOT / "diagnostics/meme_characters/asset-validation.json").write_text(
        json.dumps(out, indent=2) + "\n"
    )
    print(out["checks"], "checks,0failures")


if __name__ == "__main__":
    run()
