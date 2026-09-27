#!/usr/bin/env python3
"""Writes the small 3D assets the agent-fe-threejs tests feed to scripts/check/3d-budget.mjs.

usage: make_assets.py OUT SPEC_JSON

SPEC is one JSON object; its "kind" picks the file:
  png | jpeg | webp | avif | ktx2   {"w", "h", "pad"}; jpeg also "progressive", "fill";
                                    webp also "variant": "VP8" | "VP8L" | "VP8X"
  hdr | bytes                       {"pad"} bytes of payload
  glb | gltf                        a model; see model() below
Images carry a valid header and filler, not pixels: the check reads headers and sizes only.
"""
import base64
import json
import os
import struct
import sys
import zlib


def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)


def png(w, h, pad=0):
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)
    filler = chunk(b"prVt", b"\0" * pad) if pad else b""
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + filler + chunk(b"IEND", b"")


def jpeg(w, h, pad=0, progressive=False, fill=False):
    out = b"\xff\xd8"
    out += b"\xff\xe0" + struct.pack(">H", 16) + b"JFIF\0\x01\x01\0\0\x01\0\x01\0\0"
    while pad > 0:
        part = min(pad, 65000)
        out += b"\xff\xfe" + struct.pack(">H", part + 2) + b"\0" * part
        pad -= part
    out += b"\xff" * 3 if fill else b""
    sof = b"\xc2" if progressive else b"\xc0"
    out += b"\xff" + sof + struct.pack(">HBHHB", 17, 8, h, w, 3) + b"\x01\x22\0\x02\x11\x01\x03\x11\x01"
    return out + b"\xff\xd9"


def webp(w, h, variant="VP8X", pad=0):
    if variant == "VP8X":
        data = b"\0\0\0\0" + (w - 1).to_bytes(3, "little") + (h - 1).to_bytes(3, "little")
    elif variant == "VP8L":
        data = b"\x2f" + struct.pack("<I", (w - 1) | ((h - 1) << 14)) + b"\0" * 5
    else:
        data = b"\0\0\0" + b"\x9d\x01\x2a" + struct.pack("<HH", w, h) + b"\0" * 4
    data += b"\0" * pad
    body = b"WEBP" + variant.ljust(4).encode() + struct.pack("<I", len(data)) + data
    return b"RIFF" + struct.pack("<I", len(body)) + body


def box(kind, data, full=False):
    payload = (b"\0\0\0\0" if full else b"") + data
    return struct.pack(">I", 8 + len(payload)) + kind + payload


def avif(w, h, pad=0):
    ftyp = box(b"ftyp", b"avif" + b"\0\0\0\0" + b"avifmif1miaf")
    ispe = box(b"ispe", struct.pack(">II", w, h), full=True)
    thumb = box(b"ispe", struct.pack(">II", 32, 32), full=True)
    meta = box(b"meta", box(b"iprp", box(b"ipco", thumb + ispe)), full=True)
    return ftyp + meta + box(b"mdat", b"\0" * pad)


def ktx2(w, h, pad=0):
    ident = bytes([0xAB, 0x4B, 0x54, 0x58, 0x20, 0x32, 0x30, 0xBB, 0x0D, 0x0A, 0x1A, 0x0A])
    return ident + struct.pack("<IIIIIIII", 0, 1, w, h, 0, 0, 1, 1) + b"\0" * (48 + pad)


def image(spec):
    kind = spec["kind"]
    w, h, pad = spec.get("w", 1), spec.get("h", 1), spec.get("pad", 0)
    if kind == "png":
        return png(w, h, pad)
    if kind == "jpeg":
        return jpeg(w, h, pad, spec.get("progressive", False), spec.get("fill", False))
    if kind == "webp":
        return webp(w, h, spec.get("variant", "VP8X"), pad)
    if kind == "avif":
        return avif(w, h, pad)
    if kind == "ktx2":
        return ktx2(w, h, pad)
    if kind == "hdr":
        return b"#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n-Y 1 +X 1\n" + b"\0" * pad
    if kind == "bytes":
        return b"\0" * pad
    raise SystemExit(f"unknown kind {kind}")


def model(spec, out):
    """meshes: [[{"count", "mode", "indexed"}]]; nodes: [{"mesh", "instances", "children"}] (default:
    one node per mesh); scene: root node indices, or "none" to omit scenes; images: [{"embed": SPEC} |
    {"data": SPEC} | {"uri": "..."}]; pad: extra BIN bytes; bin_uri: gltf only, write BIN to that file."""
    gltf = {"asset": {"version": spec.get("asset_version", "2.0")}, "accessors": [], "meshes": [], "bufferViews": []}
    bin_data = bytearray(b"\0" * 16)
    for prims in spec.get("meshes", [[{"count": 3}]]):
        mesh = {"primitives": []}
        for p in prims:
            prim = {"attributes": {}, "mode": p.get("mode", 4)}
            if p.get("indexed", True):
                gltf["accessors"].append({"count": 3, "componentType": 5126, "type": "VEC3"})
                prim["attributes"]["POSITION"] = len(gltf["accessors"]) - 1
                gltf["accessors"].append({"count": p["count"], "componentType": 5125, "type": "SCALAR"})
                prim["indices"] = len(gltf["accessors"]) - 1
            else:
                gltf["accessors"].append({"count": p["count"], "componentType": 5126, "type": "VEC3"})
                prim["attributes"]["POSITION"] = len(gltf["accessors"]) - 1
            mesh["primitives"].append(prim)
        gltf["meshes"].append(mesh)
    nodes = spec.get("nodes") or [{"mesh": i} for i in range(len(gltf["meshes"]))]
    gltf["nodes"] = []
    for n in nodes:
        node = {k: v for k, v in n.items() if k in ("mesh", "children")}
        if n.get("instances"):
            gltf["accessors"].append({"count": n["instances"], "componentType": 5126, "type": "VEC3"})
            node["extensions"] = {"EXT_mesh_gpu_instancing": {"attributes": {"TRANSLATION": len(gltf["accessors"]) - 1}}}
        gltf["nodes"].append(node)
    if spec.get("scene") != "none":
        children = {c for n in nodes for c in n.get("children", [])}
        roots = spec.get("scene") or [i for i in range(len(nodes)) if i not in children]
        gltf["scenes"] = [{"nodes": roots}]
        gltf["scene"] = 0
    images = []
    for entry in spec.get("images", []):
        if "embed" in entry:
            data = image(entry["embed"])
            while len(bin_data) % 4:
                bin_data += b"\0"
            gltf["bufferViews"].append({"buffer": 0, "byteOffset": len(bin_data), "byteLength": len(data)})
            bin_data += data
            images.append({"bufferView": len(gltf["bufferViews"]) - 1, "mimeType": "image/png", "name": entry.get("name", "")})
        elif "data" in entry:
            images.append({"uri": "data:application/octet-stream;base64," + base64.b64encode(image(entry["data"])).decode()})
        else:
            images.append({"uri": entry["uri"]})
    if images:
        gltf["images"] = [{k: v for k, v in i.items() if v != ""} for i in images]
    bin_data += b"\0" * spec.get("pad", 0)
    while len(bin_data) % 4:
        bin_data += b"\0"
    if not gltf["bufferViews"]:
        del gltf["bufferViews"]
    if spec["kind"] == "glb":
        gltf["buffers"] = [{"byteLength": len(bin_data)}]
        js = json.dumps(gltf).encode()
        js += b" " * (-len(js) % 4)
        body = struct.pack("<II", len(js), 0x4E4F534A) + js + struct.pack("<II", len(bin_data), 0x004E4942) + bytes(bin_data)
        version = spec.get("glb_version", 2)
        return struct.pack("<III", 0x46546C67, version, 12 + len(body)) + body
    uri = spec.get("bin_uri")
    if uri:
        with open(os.path.join(os.path.dirname(out), uri), "wb") as fh:
            fh.write(bytes(bin_data))
        gltf["buffers"] = [{"byteLength": len(bin_data), "uri": uri}]
    else:
        gltf["buffers"] = [{"byteLength": len(bin_data), "uri": "data:application/octet-stream;base64," + base64.b64encode(bytes(bin_data)).decode()}]
    return json.dumps(gltf).encode()


def main():
    out, spec = sys.argv[1], json.loads(sys.argv[2])
    os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
    data = model(spec, out) if spec["kind"] in ("glb", "gltf") else image(spec)
    with open(out, "wb") as fh:
        fh.write(data)


main()
