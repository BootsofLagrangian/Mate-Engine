#!/usr/bin/env python3
"""Convert user-local UMA mini models to self-contained humanoid VRM0 files.
No downloads or embedded source meshes in this script. Requires UnityPy/numpy/scipy.
"""

import argparse, hashlib, io, json, struct
from pathlib import Path
import numpy as np
from scipy.spatial.transform import Rotation
import UnityPy
from UnityPy.helpers.MeshHelper import MeshHandler

ROOT = Path(__file__).resolve().parents[2]
SRC = Path("/mnt/f/ULTIMA/UMA-Extractor/UmaMusumeToolbox/uma_asset/3d/chara")
MIR = np.diag([1.0, 1, -1, 1])


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def trs(d):
    m = np.eye(4)
    q = d.m_LocalRotation
    s = d.m_LocalScale
    p = d.m_LocalPosition
    m[:3, :3] = Rotation.from_quat([q.x, q.y, q.z, q.w]).as_matrix() @ np.diag(
        [s.x, s.y, s.z]
    )
    m[:3, 3] = [p.x, p.y, p.z]
    return m


def run(cid, ident, variant="dry"):
    sources = []
    worlds = {}
    parents = {}
    parts = []
    tex = {}

    def load(rel):
        p = SRC / rel
        sources.append(
            {
                "path": str(p.relative_to(SRC.parent.parent)),
                "sha256": sha(p),
                "bytes": p.stat().st_size,
            }
        )
        return UnityPy.load(str(p))

    def part(rel, head=False):
        e = load(rel)
        trans = {}
        mesh_render = {}
        for o in e.objects:
            if o.type.name == "Transform":
                d = o.read()
                trans[o.path_id] = d

        def world(d):
            return (
                world(trans[d.m_Father.m_PathID])
                if d.m_Father.m_PathID in trans
                else np.eye(4)
            ) @ trs(d)

        attach = worlds["Neck"] if head else np.eye(4)
        for d in trans.values():
            n = d.m_GameObject.read().m_Name
            if n.startswith("pfb_") or n.startswith("M_"):
                continue
            if n not in worlds:
                worlds[n] = attach @ world(d)
                p = trans.get(d.m_Father.m_PathID)
                pn = p.m_GameObject.read().m_Name if p else None
                parents[n] = pn if pn and not pn.startswith("pfb_") else None
        for o in e.objects:
            if o.type.name == "SkinnedMeshRenderer":
                d = o.read()
                mesh_render[d.m_Mesh.m_PathID] = [
                    b.read().m_GameObject.read().m_Name for b in d.m_Bones
                ]
        for o in e.objects:
            if o.type.name != "Mesh":
                continue
            d = o.read()
            h = MeshHandler(d)
            h.process()
            n = d.m_Name
            if n == "M_Cheek":
                continue  # Optional blush overlay: neutral material already includes cheeks.
            v = np.array(h.m_Vertices)
            v = (attach @ np.c_[v, np.ones(len(v))].T).T[:, :3]
            normals = (
                np.array(h.m_Normals)[:, :3] @ attach[:3, :3].T if h.m_Normals else None
            )
            bones = mesh_render.get(o.path_id, [])
            parts.append(
                {
                    "name": n,
                    "v": v,
                    "normals": normals,
                    "uv": np.array(h.m_UV0)[:, :2],
                    "tri": np.concatenate(
                        [np.array(x).reshape(-1, 3) for x in h.get_triangles()]
                    ),
                    "bones": bones,
                    "weights": h.m_BoneWeights if bones else None,
                    "indices": h.m_BoneIndices if bones else None,
                }
            )

    part(f"mini/body/mbdy{cid}_00/pfb_mbdy{cid}_00")
    part(f"mini/head/mchr{cid}_00/pfb_mchr{cid}_00_hair", True)
    part("mini/head/mchr0001_00/pfb_mchr0001_00_face0", True)
    texture_files = []
    for rel in [f"mini/head/mchr{cid}_00/textures", "mini/head/mchr0001_00/textures"]:
        texture_files.extend(sorted((SRC / rel).glob("*")))
    if variant == "dry":
        texture_files += [
            SRC.parent.parent / "sourceresources/3d/chara" / rel
            for rel in [
                f"mini/body/mbdy{cid}_00/materials/mtl_mbdy{cid}_00",
                f"mini/head/mchr{cid}_00/materials/mtl_mchr{cid}_00_hair",
            ]
        ]
    else:
        for rel in [f"body/bdy{cid}_00/textures", f"head/chr{cid}_00/textures"]:
            texture_files.extend(sorted((SRC / rel).glob("*")))
    for p in texture_files:
        if not p.name.startswith("mtl_") and not any(
            t in p.name for t in ["_diff", "_base"]
        ):
            continue
        for o in load(str(p)).objects:
            if o.type.name == "Texture2D":
                d = o.read()
                b = io.BytesIO()
                im = d.image
                if "_eye_diff" in d.m_Name or "_mouth_diff" in d.m_Name:
                    # The game composites these atlas decals over face skin. Preserve artwork
                    # while making only its flat skin background transparent in standard glTF.
                    from PIL import Image

                    a = np.array(im.convert("RGBA"))
                    background = a[-1, -1, :3].astype(int)
                    delta = np.max(np.abs(a[:, :, :3].astype(int) - background), axis=2)
                    a[:, :, 3] = np.where(delta <= 3, 0, a[:, :, 3])
                    im = Image.fromarray(a)
                if "_mouth_diff" in d.m_Name:
                    # Match transparent border RGB to the persistent opaque skin cover
                    # to avoid a colored fringe during filtered sampling.
                    from PIL import Image

                    a = np.array(im.convert("RGBA"))
                    bg = a[-1, -1, :3].astype(int)
                    mask = np.max(np.abs(a[:, :, :3].astype(int) - bg), axis=2) <= 3
                    a[mask, :3] = [255, 235, 217]
                    im = Image.fromarray(a)
                im.save(b, format="PNG")
                tex[d.m_Name] = b.getvalue()
    # VRM0 faces -Z in glTF; the Godot VRM0 importer applies its standard 180-degree correction.
    # Mirror source Z and reverse triangle winding once, preserving source handedness.
    worlds = {n: MIR @ m @ MIR for n, m in worlds.items()}
    nodes = []
    names = {}
    for n in worlds:
        names[n] = len(nodes)
        nodes.append({"name": n})
    for n, m in worlds.items():
        p = parents[n]
        local = np.linalg.inv(worlds[p]) @ m if p in worlds else m
        nodes[names[n]]["matrix"] = local.T.reshape(-1).tolist()
        if p in names:
            nodes[names[p]].setdefault("children", []).append(names[n])
    doc = {
        "asset": {"version": "2.0", "generator": "Mate local UMA mini converter 1"},
        "scene": 0,
        "scenes": [{"nodes": [names[n] for n in worlds if parents[n] not in names]}],
        "nodes": nodes,
        "meshes": [],
        "skins": [],
        "materials": [],
        "textures": [],
        "images": [],
        "samplers": [
            {"magFilter": 9729, "minFilter": 9987, "wrapS": 33071, "wrapT": 33071}
        ],
        "bufferViews": [],
        "accessors": [],
        "extensionsUsed": ["VRM", "KHR_materials_unlit"],
    }
    buf = bytearray()

    def view(data):
        while len(buf) % 4:
            buf.append(0)
        i = len(doc["bufferViews"])
        doc["bufferViews"].append(
            {"buffer": 0, "byteOffset": len(buf), "byteLength": len(data)}
        )
        buf.extend(data)
        return i

    def accessor(data, typ, dtype="<f4", bounds=False):
        a = np.asarray(data, dtype=dtype)
        i = len(doc["accessors"])
        d = {
            "bufferView": view(a.tobytes()),
            "componentType": {"<f4": 5126, "<u2": 5123, "<u4": 5125}[dtype],
            "count": len(a),
            "type": typ,
        }
        if bounds:
            d.update(min=a.min(axis=0).tolist(), max=a.max(axis=0).tolist())
        doc["accessors"].append(d)
        return i

    from PIL import Image

    b = io.BytesIO()
    Image.new("RGBA", (2, 2), (255, 235, 217, 255)).save(b, format="PNG")
    tex["neutral_mouth_skin_cover"] = b.getvalue()
    mats = {}

    def mat(texture):
        if texture in mats:
            return mats[texture]
        ix = len(doc["images"])
        doc["images"].append(
            {"bufferView": view(tex[texture]), "mimeType": "image/png", "name": texture}
        )
        doc["textures"].append({"source": ix, "sampler": 0})
        mi = len(doc["materials"])
        doc["materials"].append(
            {
                "name": texture,
                "doubleSided": True,
                "alphaMode": "MASK",
                "alphaCutoff": 0.05,
                "pbrMetallicRoughness": {
                    "baseColorTexture": {"index": ix},
                    "metallicFactor": 0,
                    "roughnessFactor": 1,
                },
                "extensions": {"KHR_materials_unlit": {}},
            }
        )
        mats[texture] = mi
        return mi

    skin = {
        "joints": list(range(len(worlds))),
        "inverseBindMatrices": accessor(
            [np.linalg.inv(m).T.reshape(-1) for m in worlds.values()], "MAT4"
        ),
    }
    doc["skins"].append(skin)
    expression_binds = {}
    neutral_meshes = {}

    def emit(p, texture, uv=None, expression=None, collapse=False):
        v = p["v"].copy()
        v[:, 2] *= -1
        n = p["normals"].copy() if p["normals"] is not None else None
        if n is not None:
            n[:, 2] *= -1
        u = (uv if uv is not None else p["uv"]).copy()
        u[:, 1] = 1 - u[:, 1]
        actual = v.copy()
        center = np.tile(v.mean(axis=0), (len(v), 1))
        target = None
        if p["name"] == "M_Eye":
            for side in [v[:, 0] < 0, v[:, 0] >= 0]:
                if side.any():
                    center[side] = v[side].mean(axis=0)
        if collapse:
            v[:] = center
            target = actual - v
        elif p["name"] == "M_Eye":
            goal = v.copy()
            goal[:, 1] = center[:, 1] + (v[:, 1] - center[:, 1]) * 0.02
            target = goal - v
        if p["name"] == "M_Mouth":

            def surface_xy(points):
                x, y = points[:, 0], points[:, 1]
                return np.c_[np.ones(len(x)), x, y, x * x, x * y, y * y]

            surface_fit = np.linalg.lstsq(surface_xy(actual), actual[:, 2], rcond=None)[
                0
            ]
            v[:, 1] = center[:, 1] + (actual[:, 1] - center[:, 1]) * 0.035
            v[:, 2] = surface_xy(v) @ surface_fit - 0.002
        attr = {
            "POSITION": accessor(v, "VEC3", bounds=True),
            "TEXCOORD_0": accessor(u, "VEC2"),
        }
        if n is not None:
            attr["NORMAL"] = accessor(n, "VEC3")
        if p["bones"]:
            j = np.array(
                [[names[p["bones"][int(x)]] for x in row] for row in p["indices"]]
            )
            w = np.array(p["weights"])
            w /= w.sum(axis=1, keepdims=True)
        else:
            j = np.tile([names["Head"], 0, 0, 0], (len(v), 1))
            w = np.tile([1.0, 0, 0, 0], (len(v), 1))
        attr["JOINTS_0"] = accessor(j, "VEC4", "<u2")
        attr["WEIGHTS_0"] = accessor(w, "VEC4")
        prim = {
            "attributes": attr,
            "indices": accessor(p["tri"][:, ::-1].reshape(-1, 1), "SCALAR", "<u4"),
            "material": mat(texture),
        }
        mesh = {
            "name": p["name"] + ("_" + expression if expression else ""),
            "primitives": [prim],
        }
        if target is not None:
            prim["targets"] = [{"POSITION": accessor(target, "VEC3")}]
            mesh["weights"] = [0.0]
            mesh["extras"] = {"targetNames": ["show" if collapse else "hide"]}
        if p["name"] == "M_Mouth":
            prim["targets"] = []
            mesh["weights"] = [0.0] * 5
            mesh["extras"] = {"targetNames": ["a", "i", "u", "e", "o"]}
            for exp, sx, sy in [
                ("a", 1.0, 1.0),
                ("i", 1.05, 0.35),
                ("u", 0.55, 0.6),
                ("e", 1.0, 0.65),
                ("o", 0.65, 0.85),
            ]:
                goal = actual.copy()
                goal[:, 0] = center[:, 0] + (actual[:, 0] - center[:, 0]) * sx
                goal[:, 1] = center[:, 1] + (actual[:, 1] - center[:, 1]) * sy
                goal[:, 2] = surface_xy(goal) @ surface_fit - 0.002
                prim["targets"].append({"POSITION": accessor(goal - v, "VEC3")})
        mi = len(doc["meshes"])
        doc["meshes"].append(mesh)
        ni = len(nodes)
        nodes.append({"name": mesh["name"], "mesh": mi, "skin": 0})
        doc["scenes"][0]["nodes"].append(ni)
        if p["name"] == "M_Mouth":
            for ix, exp in enumerate(["a", "i", "u", "e", "o"]):
                expression_binds[exp] = [{"mesh": mi, "index": ix, "weight": 100}]
        if expression:
            expression_binds.setdefault(expression, []).append(
                {"mesh": mi, "index": 0, "weight": 100}
            )
        elif target is not None:
            neutral_meshes[p["name"]] = mi

    def atlas(p, col, row, cols, rows):
        u = p["uv"].copy()
        lo = u.min(axis=0)
        hi = u.max(axis=0)
        # Source facial geometry UVs already span a single atlas tile. Translate tile,
        # preserving the artist's inset and left/right eye layout rather than stretching.
        oldcol = int(((lo[0] + hi[0]) / 2) * cols)
        oldrow = int((1 - (lo[1] + hi[1]) / 2) * rows)
        u[:, 0] += (col - oldcol) / cols
        u[:, 1] -= (row - oldrow) / rows
        return u

    for p in parts:
        n = p["name"]
        texture = (
            (
                f"tex_mbdy{cid}_00_diff"
                if variant == "dry"
                else f"tex_bdy{cid}_00_diff_wet"
            )
            if n == "M_Body"
            else (
                f"tex_mchr{cid}_00_hair_diff"
                if variant == "dry"
                else f"tex_chr{cid}_00_hair_diff_wet"
            )
            if n == "M_Hair"
            else "tex_mchr0001_00_face0_0_diff"
            if n == "M_Face"
            else f"tex_mchr{cid}_00_mayu_diff"
            if n.startswith("M_Mayu")
            else f"tex_mchr{cid}_00_eye_diff"
            if n == "M_Eye"
            else f"tex_mchr{cid}_00_mouth_diff"
        )
        if n == "M_Mouth":
            centers = p["uv"][p["tri"]].mean(axis=1)
            p = dict(p)
            p["tri"] = p["tri"][(centers[:, 0] < 0.25) & (centers[:, 1] > 0.875)]
            used = np.unique(p["tri"])
            remap = {old: i for i, old in enumerate(used)}
            p["tri"] = np.array([[remap[x] for x in row] for row in p["tri"]])
            p["v"] = p["v"][used]
            p["uv"] = p["uv"][used]
            p["normals"] = p["normals"][used] if p["normals"] is not None else None
        uv = (
            atlas(p, 0, 0, 4, 8)
            if n == "M_Eye"
            else atlas(p, 2, 0, 4, 8)
            if n == "M_Mouth"
            else atlas(p, 0, 0, 4, 8)
            if n.startswith("M_Mayu")
            else None
        )
        if n == "M_Mouth":
            cover = dict(p)
            cover["name"] = "M_Mouth_skin_cover"
            cover["v"] = p["v"].copy()
            cover["v"][:, 2] -= 0.00015
            emit(cover, "neutral_mouth_skin_cover")
        emit(p, texture, uv)
        if n == "M_Eye":
            expression_binds["blink"] = [
                {"mesh": neutral_meshes["M_Eye"], "index": 0, "weight": 100}
            ]

    groups = []
    for exp, binds in expression_binds.items():
        neutral = []
        groups.append(
            {
                "name": exp,
                "presetName": exp,
                "binds": neutral + binds,
                "materialValues": [],
                "isBinary": False,
            }
        )
    mapping = {
        "hips": "Hip",
        "spine": "Waist",
        "chest": "Chest",
        "neck": "Neck",
        "head": "Head",
    }
    for side, abbr in [("left", "L"), ("right", "R")]:
        for human, bone in [
            ("Shoulder", "Shoulder"),
            ("UpperArm", "Arm"),
            ("LowerArm", "Elbow"),
            ("Hand", "Wrist"),
            ("UpperLeg", "Thigh"),
            ("LowerLeg", "Knee"),
            ("Foot", "Ankle"),
        ]:
            mapping[side + human] = bone + "_" + abbr
        for human, bone in [
            ("ThumbProximal", "Thumb_01"),
            ("ThumbDistal", "Thumb_03"),
            ("IndexProximal", "Index_01"),
            ("IndexDistal", "Index_03"),
            ("RingProximal", "Ring_01"),
            ("RingDistal", "Ring_03"),
        ]:
            mapping[side + human] = bone + "_" + abbr
    doc["extensions"] = {
        "VRM": {
            "exporterVersion": "MateMini1",
            "specVersion": "0.0",
            "meta": {
                "title": ident + " — UMA mini",
                "version": "1",
                "author": "Cygames (source); local Mate conversion",
                "contactInformation": "",
                "reference": "User-local UMA-Extractor assets. Not an independently licensed avatar.",
                "allowedUserName": "OnlyAuthor",
                "violentUssageName": "Disallow",
                "sexualUssageName": "Disallow",
                "commercialUssageName": "Disallow",
                "licenseName": "Other",
                "otherLicenseUrl": "https://umamusume.jp/derivativework_guidelines/",
            },
            "humanoid": {
                "humanBones": [
                    {"bone": h, "node": names[n], "useDefaultValues": True}
                    for h, n in mapping.items()
                    if n in names
                ]
            },
            "firstPerson": {
                "firstPersonBone": names["Head"],
                "firstPersonBoneOffset": {"x": 0, "y": 0, "z": 0},
                "meshAnnotations": [],
                "lookAtTypeName": "Bone",
                **{
                    k: {"curve": [0, 0, 0, 1, 1, 1, 1, 0], "xRange": 90, "yRange": 10}
                    for k in [
                        "lookAtHorizontalInner",
                        "lookAtHorizontalOuter",
                        "lookAtVerticalDown",
                        "lookAtVerticalUp",
                    ]
                },
            },
            "blendShapeMaster": {"blendShapeGroups": groups},
            "secondaryAnimation": {"boneGroups": [], "colliderGroups": []},
            "materialProperties": [
                {
                    "name": m["name"],
                    "shader": "VRM_USE_GLTFSHADER",
                    "renderQueue": -1,
                    "floatProperties": {},
                    "vectorProperties": {},
                    "textureProperties": {},
                    "keywordMap": {},
                    "tagMap": {},
                }
                for m in doc["materials"]
            ],
        }
    }
    # Reuse the generic, independently tested mini spring authoring pass.
    import importlib.util

    spring_path = (
        Path(__file__).resolve().parents[1] / "physics_cloth/author_mini_springs.py"
    )
    spec = importlib.util.spec_from_file_location("mate_mini_springs", spring_path)
    spring_module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(spring_module)
    physics_report = spring_module.add_mini_springs(doc)
    doc["buffers"] = [{"byteLength": len(buf)}]
    j = json.dumps(doc, separators=(",", ":")).encode()
    j += b" " * ((-len(j)) % 4)
    buf += b"\0" * ((-len(buf)) % 4)
    suffix = "" if variant == "dry" else "-wet"
    out = ROOT / "assets" / f"{ident}{suffix}.vrm"
    out.write_bytes(
        struct.pack("<III", 0x46546C67, 2, 28 + len(j) + len(buf))
        + struct.pack("<II", len(j), 0x4E4F534A)
        + j
        + struct.pack("<II", len(buf), 0x004E4942)
        + buf
    )
    report = {
        "id": ident,
        "character_id": cid,
        "variant": "actual UMA mini/chibi game model, locally assembled",
        "texture_variant": variant,
        "vrm": str(out.relative_to(ROOT)),
        "sha256": sha(out),
        "bytes": out.stat().st_size,
        "bones": len(worlds),
        "humanoid_bones": len(mapping),
        "meshes": len(parts),
        "source_files": sources,
        "physics": physics_report,
        "spring_authoring_sha256": sha(spring_path),
        "expressions": list(expression_binds),
        "limits": [
            "Mate-authored bounded hair/skirt spring groups; not original game physics or full cloth simulation.",
            (
                "Original mini-specific dry diffuse textures."
                if variant == "dry"
                else "Optional main-model wet diffuse adaptation on mini geometry."
            ),
            "Single source AA atlas surface with five continuous mouth deformations; no original facial animation engine.",
            "Copyrighted user-local game assets; no redistribution license inferred.",
        ],
    }
    dest = (
        ROOT / "diagnostics/meme_characters" / f"{ident}{suffix}-asset-provenance.json"
    )
    dest.write_text(json.dumps(report, indent=2) + "\n")
    print(ident, out, sha(out))


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--id", choices=["mambo", "hachimi"])
    p.add_argument("--variant", choices=["dry", "wet", "all"], default="all")
    a = p.parse_args()
    for cid, ident in [("1062", "mambo"), ("1003", "hachimi")]:
        if not a.id or a.id == ident:
            for variant in ["dry", "wet"] if a.variant == "all" else [a.variant]:
                run(cid, ident, variant)
