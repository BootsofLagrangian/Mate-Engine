"""Author conservative VRM0 secondary chains on the extracted UMA mini rig.

Pure doc mutation for the source converter; does not touch mesh buffers. This is
new Mate tuning, not spring metadata recovered from the original game. Only
known hair/skirt root naming is supported. Existing authored physics is retained.
"""
from __future__ import annotations
import re


def add_mini_springs(doc: dict) -> dict:
    vrm = doc.get("extensions", {}).get("VRM")
    if not isinstance(vrm, dict):
        raise ValueError("Mini spring authoring requires VRM 0.x")
    previous = vrm.get("secondaryAnimation", {})
    if previous.get("boneGroups") or previous.get("colliderGroups"):
        return {"changed": False, "reason": "existing_authored_secondary_retained"}
    nodes = doc["nodes"]
    names = {node.get("name", ""): i for i, node in enumerate(nodes)}
    roots = {kind: [] for kind in ("hair", "skirt")}
    for name, idx in names.items():
        kind = "hair" if re.fullmatch(r"Sp_He_Hair\d+_[CLR]_00", name) else "skirt" if re.fullmatch(r"Sp_Hi_MSkirt\d+_[A-Z]+_00", name) else None
        if kind and nodes[idx].get("children"):
            roots[kind].append(idx)
    if not roots["hair"] or not roots["skirt"]:
        raise ValueError("Known UMA mini hair and skirt root chains not found")
    bones = {x["bone"]: x["node"] for x in vrm["humanoid"]["humanBones"]}
    # Small source rigs are ~0.55 m high before avatar display scale. Proxy
    # radii are deliberately conservative, not an enclosing head/skirt shell.
    collider_groups = []
    for bone, radius, offset in [("head", .065, (0,.07,0)), ("hips", .065, (0,-.015,0)), ("leftUpperLeg", .027, (0,.035,0)), ("rightUpperLeg", .027, (0,.035,0))]:
        if bone not in bones:
            raise ValueError(f"Required humanoid bone missing: {bone}")
        collider_groups.append({"node": bones[bone], "colliders": [{"offset": dict(zip(("x","y","z"),offset)), "radius": radius}]})
    groups = []
    for kind, stiffness, gravity, drag, hit, colliders in [("hair", 1.0, .025, .60, .006, [0]), ("skirt", 1.5, .035, .65, .005, [1,2,3])]:
        groups.append({"comment": f"Mate authored mini {kind} v1 (not original game physics)", "stiffiness": stiffness, "gravityPower": gravity, "gravityDir": {"x":0,"y":-1,"z":0}, "dragForce": drag, "center": -1, "hitRadius": hit, "bones": sorted(roots[kind]), "colliderGroups": colliders})
    vrm["secondaryAnimation"] = {"boneGroups": groups, "colliderGroups": collider_groups}
    return {"changed": True, "version": 1, "source": "Mate authored conservative VRM0 spring tuning", "hair_roots": len(roots["hair"]), "skirt_roots": len(roots["skirt"]), "collider_groups": len(collider_groups), "cloth_triangles": False}
