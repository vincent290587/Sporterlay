#!/usr/bin/env python3
"""Copies the models the worlds use from third-party packs into assets/, trimmed for
toon shading: normal and roughness maps dropped, textures shrunk. Needs Pillow.

    python tools/import_assets.py megakit  <unzipped Stylized Nature MegaKit>
    python tools/import_assets.py village  <unzipped Medieval Village MegaKit[Standard]>
    python tools/import_assets.py props    <unzipped Fantasy Props MegaKit[Standard]>
    python tools/import_assets.py raft     <unzipped RaftOnTheDesert (the Godot folder)>
    python tools/import_assets.py --bundle out.zip     # local-only packs, for another PC
    python tools/import_assets.py --unbundle in.zip

The Quaternius packs are CC0 and live in the repository (assets/<pack>). The Raft
pack's license allows shipping it inside the game but not handing the files on, and
the repository is public: it goes to assets/local/ (ignored by git), and --bundle
zips that folder to carry to your other computer, where --unbundle puts it back.
"""
import json
import os
import shutil
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.normpath(os.path.join(HERE, "..", "assets"))
LOCAL = os.path.join(ASSETS, "local")

QUATERNIUS_LICENSE = """Models and textures: {pack} by Quaternius
https://quaternius.com

License: CC0 1.0 Universal (public domain dedication)
https://creativecommons.org/publicdomain/zero/1.0/

Copied by tools/import_assets.py: a subset of the models, normal and roughness maps
removed, textures reduced in size.
"""

VILLAGE = ([f"Wall_{m}_{p}" for m in ("Plaster", "UnevenBrick") for p in
            ("Straight", "Window_Thin_Round", "Window_Wide_Round", "Door_Round")]
           + ["Wall_Plaster_WoodGrid", "Wall_Arch", "Wall_BottomCover", "Corner_Exterior_Wood", "Corner_Exterior_Brick"]
           + [f"Roof_RoundTiles_{s}" for s in ("4x4", "4x6", "4x8", "6x6", "6x8", "6x10", "6x12", "8x8", "8x10", "8x12")]
           + ["Roof_Tower_RoundTiles", "Roof_Front_Brick4", "Roof_Front_Brick6", "Roof_Front_Brick8"]
           + ["WindowShutters_Wide_Round_Open", "WindowShutters_Thin_Round_Open", "Floor_WoodDark"]
           + ["Prop_Chimney", "Prop_Chimney2", "Prop_Wagon", "Prop_WoodenFence_Single", "Prop_WoodenFence_Extension1",
              "Prop_Crate", "Prop_Vine1", "Prop_Vine4", "Prop_MetalFence_Ornament", "Prop_Support"])
PROPS = ["Barrel", "Barrel_Apples", "Crate_Wooden", "FarmCrate_Apple", "FarmCrate_Carrot", "Stall_Empty",
         "Stall_Cart_Empty", "Bench", "Lantern_Wall", "Banner_1", "Banner_2", "Bucket_Wooden_1", "Anvil",
         "Workbench", "Chest_Wood", "Table_Large", "Torch_Metal"]

PACKS = {
    "megakit": {"name": "Stylized Nature MegaKit (Standard)", "sub": "glTF", "dest": "megakit",
                "models": [f"TwistedTree_{i}" for i in range(1, 6)] + [f"DeadTree_{i}" for i in range(1, 6)]
                + ["Bush_Common", "Bush_Common_Flowers", "Fern_1", "Plant_1", "Plant_1_Big", "Plant_7", "Plant_7_Big",
                   "Mushroom_Common", "Mushroom_Laetiporus"]
                + [f"Rock_Medium_{i}" for i in range(1, 4)] + [f"Pebble_Round_{i}" for i in range(1, 6)]
                + [f"Pebble_Square_{i}" for i in range(1, 7)],
                "max": {"Bark": 512, "Rocks": 1024, "PathRocks": 1024}, "default_max": 1024},
    "village": {"name": "Medieval Village MegaKit (Standard)", "sub": "glTF", "dest": "village",
                "models": VILLAGE, "max": {}, "default_max": 512},
    "props": {"name": "Fantasy Props MegaKit (Standard)", "sub": os.path.join("Exports", "glTF"), "dest": "props",
              "models": PROPS, "max": {}, "default_max": 512},
}
RAFT = ["EA04_Bld_Tower_Main_01a", "EA04_Bld_Tower_Main_01b", "EA04_Bld_Tower_Main_02a"] \
    + [f"EA04_Bld_Wall_Straight_01{c}" for c in "abcde"] \
    + ["EA04_Prop_Barrel_01a", "EA04_Prop_Fireplace_01a", "EA04_Prop_Flag_01a", "EA04_Prop_washing_Comp",
       "EA04_Prop_cauldron_01a", "EA04_Prop_cover_01a", "EA04_Prop_Pole_01a_001", "EA04_Prop_Skull_01a",
       "EA04_Wehicule_Raft_01a", "Cucumber_bus_01a", "EA04_Env_Tree_Trunk_01a", "EA04_Env_Trunk_and_Stone"] \
    + [f"EA04_Env_Rocks_Sand_01{c}" for c in "abcd"] + [f"EA04_Env_Stone_Sand_01{c}" for c in "ab"]


def _find_texture(src: str, uri: str) -> str:
    for d in (src, os.path.join(src, "..", "Textures"), os.path.join(src, "..", "..", "Textures")):
        p = os.path.join(d, uri)
        if os.path.isfile(p):
            return p
    raise FileNotFoundError(uri)


def import_quaternius(key: str, root: str) -> None:
    from PIL import Image
    pack = PACKS[key]
    src = os.path.join(root, pack["sub"])
    dst = os.path.join(ASSETS, pack["dest"])
    if os.path.isdir(dst):
        shutil.rmtree(dst)
    os.makedirs(dst)
    images = set()
    for name in pack["models"]:
        with open(os.path.join(src, name + ".gltf")) as f:
            g = json.load(f)
        # keep only the base colour textures
        keep_tex = set()
        for m in g.get("materials", []):
            m.pop("normalTexture", None)
            m.pop("occlusionTexture", None)
            pbr = m.get("pbrMetallicRoughness", {})
            pbr.pop("metallicRoughnessTexture", None)
            if "baseColorTexture" in pbr:
                keep_tex.add(pbr["baseColorTexture"]["index"])
        keep_img = sorted({g["textures"][t]["source"] for t in keep_tex})
        img_remap = {old: new for new, old in enumerate(keep_img)}
        tex_remap = {}
        textures = []
        for t in sorted(keep_tex):
            tex_remap[t] = len(textures)
            textures.append(dict(g["textures"][t], source=img_remap[g["textures"][t]["source"]]))
        g["images"] = [g["images"][i] for i in keep_img]
        g["textures"] = textures
        for m in g.get("materials", []):
            pbr = m.get("pbrMetallicRoughness", {})
            if "baseColorTexture" in pbr:
                pbr["baseColorTexture"]["index"] = tex_remap[pbr["baseColorTexture"]["index"]]
        for i in g["images"]:
            images.add(i["uri"])
        with open(os.path.join(dst, name + ".gltf"), "w") as f:
            json.dump(g, f, separators=(",", ":"))
        for b in g.get("buffers", []):
            shutil.copy(os.path.join(src, b["uri"]), dst)
    for uri in sorted(images):
        img = Image.open(_find_texture(src, uri))
        limit = next((v for k, v in pack["max"].items() if uri.startswith(k + "_")), pack["default_max"])
        if max(img.size) > limit:
            img.thumbnail((limit, limit), Image.LANCZOS)
        img.save(os.path.join(dst, uri), optimize=True)
        print(f"{uri}: {img.size[0]}x{img.size[1]}")
    with open(os.path.join(dst, "LICENSE.txt"), "w") as f:
        f.write(QUATERNIUS_LICENSE.format(pack=pack["name"]))
    print(f"{key}: {len(pack['models'])} models, {len(images)} textures -> {dst}")


def import_raft(root: str) -> None:
    dst = os.path.join(LOCAL, "raft")
    if os.path.isdir(dst):
        shutil.rmtree(dst)
    os.makedirs(dst)
    import glob
    import re
    prefabs = {os.path.splitext(os.path.basename(f))[0]: f for f in glob.glob(os.path.join(root, "Prefabs", "**", "*.tscn"), recursive=True)}
    for name in RAFT:
        # a prefab can point at a mesh file of another name: follow it
        with open(prefabs[name], encoding="utf-8") as f:
            meshes = re.findall(r'path="res://Meshes/([^"]+\.glb)"', f.read())
        if len(meshes) != 1:
            print(f"raft: {name} uses {meshes}, skipped")
            continue
        shutil.copy(os.path.join(root, "Meshes", meshes[0]), os.path.join(dst, name + ".glb"))
    shutil.copy(os.path.join(root, "Textures", "texture.png"), os.path.join(dst, "texture.png"))
    for lic in ("LICENSE.txt", os.path.join("Documentation", "LICENSE.txt")):
        if os.path.isfile(os.path.join(root, lic)):
            shutil.copy(os.path.join(root, lic), os.path.join(dst, "LICENSE.txt"))
            break
    with open(os.path.join(dst, "README.txt"), "w") as f:
        f.write("Raft on the Desert by Maciej EmacEArt: may be shipped inside a game, not handed on as\n"
                "files. Local only (ignored by git); carry it with tools/import_assets.py --bundle.\n")
    print(f"raft: {len(RAFT)} models -> {dst} (local only)")


def bundle(path: str) -> None:
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        for d, _, files in os.walk(LOCAL):
            for f in files:
                if f.endswith(".import"):
                    continue
                full = os.path.join(d, f)
                z.write(full, os.path.relpath(full, ASSETS))
    print(f"local packs -> {path}")


def unbundle(path: str) -> None:
    with zipfile.ZipFile(path) as z:
        for n in z.namelist():
            if not n.startswith("local/") or ".." in n:
                raise SystemExit(f"unexpected entry {n}")
        z.extractall(ASSETS)
    print(f"{path} -> {LOCAL}")


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    what, arg = sys.argv[1], sys.argv[2]
    if what == "--bundle":
        bundle(arg)
    elif what == "--unbundle":
        unbundle(arg)
    elif what == "raft":
        import_raft(arg)
    elif what in PACKS:
        import_quaternius(what, arg)
    else:
        raise SystemExit(__doc__)


if __name__ == "__main__":
    main()
