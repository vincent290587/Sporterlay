#!/usr/bin/env python3
"""Copies the models we use from Quaternius' Stylized Nature MegaKit (CC0) into
assets/megakit: glTF + bin, without normal maps (toon shading doesn't use them), with
textures shrunk to at most MAX_SIZE px. Needs Pillow.

    python3 tools/import_megakit.py ~/Downloads/Stylized_Nature_MegaKitStandard   (unzipped)
"""
import json
import os
import shutil
import sys

from PIL import Image

MAX_SIZE = {"Bark": 512, "Rocks": 1024, "PathRocks": 1024}   # by texture name prefix
DEFAULT_MAX = 1024

MODELS = ([f"TwistedTree_{i}" for i in range(1, 6)] + [f"DeadTree_{i}" for i in range(1, 6)] + [
    "Bush_Common", "Bush_Common_Flowers", "Fern_1", "Plant_1", "Plant_1_Big", "Plant_7", "Plant_7_Big",
    # not their yellow or pink flowers, clover or grass, by choice
    "Mushroom_Common", "Mushroom_Laetiporus"]
    + [f"Rock_Medium_{i}" for i in range(1, 4)] + [f"Pebble_Round_{i}" for i in range(1, 6)]
    + [f"Pebble_Square_{i}" for i in range(1, 7)])

LICENSE = """Models and textures: Stylized Nature MegaKit (Standard) by Quaternius
https://quaternius.com/packs/stylizednaturemegakit.html

License: CC0 1.0 Universal (public domain dedication)
https://creativecommons.org/publicdomain/zero/1.0/

Copied by tools/import_megakit.py: a subset of the models, normal maps removed,
textures reduced in size.
"""


def main() -> None:
    src = os.path.join(sys.argv[1], "glTF")
    dst = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "megakit")
    if os.path.isdir(dst):
        shutil.rmtree(dst)
    os.makedirs(dst)
    images = set()
    for name in MODELS:
        with open(os.path.join(src, name + ".gltf")) as f:
            g = json.load(f)
        # drop normal maps
        normal_images = set()
        for m in g.get("materials", []):
            nt = m.pop("normalTexture", None)
            if nt is not None:
                normal_images.add(g["textures"][nt["index"]]["source"])
        keep = [i for i in range(len(g.get("images", []))) if i not in normal_images]
        remap = {old: new for new, old in enumerate(keep)}
        g["images"] = [g["images"][i] for i in keep]
        textures = []
        tex_remap = {}
        for ti, t in enumerate(g.get("textures", [])):
            if t["source"] in remap:
                tex_remap[ti] = len(textures)
                textures.append(dict(t, source=remap[t["source"]]))
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
        img = Image.open(os.path.join(src, uri))
        limit = next((v for k, v in MAX_SIZE.items() if uri.startswith(k + "_")), DEFAULT_MAX)
        if max(img.size) > limit:
            img.thumbnail((limit, limit), Image.LANCZOS)
        img.save(os.path.join(dst, uri), optimize=True)
        print(f"{uri}: {img.size[0]}x{img.size[1]}")
    with open(os.path.join(dst, "LICENSE.txt"), "w") as f:
        f.write(LICENSE)
    print(f"{len(MODELS)} models, {len(images)} textures")


if __name__ == "__main__":
    main()
