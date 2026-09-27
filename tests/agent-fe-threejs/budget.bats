#!/usr/bin/env bats
# scripts/check/3d-budget.mjs, the asset-budget gate agent-fe-threejs installs: every budget proven
# both ways (over fails, within passes), every image header it reads, and every configuration error.

load helpers

setup() {
  tj_env
  command -v "$JS" >/dev/null 2>&1 || skip "$JS is not installed"
  budget_repo
}

# ── configuration ──────────────────────────────────────────────────────────────────────────────

@test "an empty public/ passes and says it read nothing" {
  run -0 budget
  [ "$output" = "3d-budget: 0 models, 0 textures, 0 environment maps under public; 0 over budget or unreadable" ]
}

@test "--help exits 0; an unknown argument is a usage error" {
  run -0 budget --help
  assert_has "usage: node scripts/check/3d-budget.mjs [--warn]"
  run -2 budget --frobnicate
  assert_has 'unknown argument "--frobnicate"'
}

@test "a missing or malformed config is a configuration error, exit 2" {
  rm "$R/scripts/check/3d-budget.json"
  run -2 budget
  assert_has "scripts/check/3d-budget.json: not found; /agent-fe-threejs:setup creates it"
  printf '{ nope' >"$R/scripts/check/3d-budget.json"
  run -2 budget
  assert_has "not JSON"
  printf '[]' >"$R/scripts/check/3d-budget.json"
  run -2 budget
  assert_has "must hold a JSON object"
}

@test "config mistakes are refused, not ignored" {
  local good
  good="$(cat "$R/scripts/check/3d-budget.json")"
  for patch in '{"rootz": ["public"]}' '{"roots": []}' '{"roots": ["../elsewhere"]}' '{"roots": ["assets"]}' \
    '{"budgets": {"triangles": 0}}' '{"budgets": {"triangles": "many"}}' '{"budgets": {"polygons": 5}}' \
    '{"budgets": {"modelKB": null}}' '{"textureDirs": "public/models"}' '{"exceptions": {}}' \
    '{"exceptions": [{"path": "public/a.glb", "budget": "triangles", "max": 200000}]}' \
    '{"exceptions": [{"path": "public/a.glb", "budget": "triangles", "max": 90000, "reason": "a hero model with more detail"}]}' \
    '{"exceptions": [{"path": "public/a.glb", "budget": "polys", "max": 200000, "reason": "a hero model with more detail"}]}' \
    '{"exceptions": [{"path": "/etc/a.glb", "budget": "triangles", "max": 200000, "reason": "a hero model with more detail"}]}' \
    '{"exceptions": [{"path": "public/a.glb", "budget": "triangles", "max": 200000, "reason": "a hero model with more detail", "until": "soon"}]}' \
    '{"exceptions": [{"path": "public/a.glb", "budget": "triangles", "max": 200000, "reason": "a hero model with more detail"}, {"path": "public/a.glb", "budget": "triangles", "max": 300000, "reason": "the same file a second time"}]}'; do
    printf '%s' "$good" >"$R/scripts/check/3d-budget.json"
    config "$patch"
    run -2 budget
    assert_has "scripts/check/3d-budget.json: "
  done
}

@test "a root that is not a folder names the fix" {
  config '{"roots": ["public", "static"]}'
  run -2 budget
  assert_has 'root "static" is not a folder in this repository'
  mkdir "$R/static"
  run -0 budget
  assert_has "under public, static"
}

# ── models ─────────────────────────────────────────────────────────────────────────────────────

@test "a model within every budget passes" {
  asset public/models/small.glb '{"kind": "glb", "meshes": [[{"count": 3000}]], "images": [{"embed": {"kind": "png", "w": 1024, "h": 1024}}]}'
  run -0 budget
  assert_has "3d-budget: 1 model (1 image inside), 0 textures, 0 environment maps under public; 0 over budget"
}

@test "modelKB: a model over its byte budget fails, one under it passes" {
  asset public/models/big.glb '{"kind": "glb", "pad": 1600000}'
  asset public/models/fits.glb '{"kind": "glb", "pad": 1400000}'
  run -1 budget
  assert_has "3D-BUDGET public/models/big.glb: 1562.9 KB > 1,536 KB (modelKB)"
  assert_lacks "fits.glb"
  assert_has "2 models, 0 textures, 0 environment maps under public; 1 over budget or unreadable"
  assert_has "Budgets and exceptions: scripts/check/3d-budget.json. Why they exist: .claude/rules/web/3d.md § 5."
}

@test "triangles: indexed, non-indexed, strips and fans count; points and lines do not" {
  # 30,000 indices = 10,000; 3,000 vertices = 1,000; a 102-vertex strip = 100; a 12-vertex fan = 10;
  # 999 points and 1,000 line vertices = 0. Total 11,110.
  asset public/models/mix.glb '{"kind": "glb", "meshes": [[{"count": 30000}, {"count": 3000, "indexed": false},
    {"count": 102, "mode": 5}, {"count": 12, "mode": 6, "indexed": false}, {"count": 999, "mode": 0}, {"count": 1000, "mode": 1}]]}'
  config '{"budgets": {"triangles": 11109}}'
  run -1 budget
  assert_has "3D-BUDGET public/models/mix.glb: 11,110 triangles > 11,109 triangles (triangles)"
  config '{"budgets": {"triangles": 11110}}'
  run -0 budget
}

@test "triangles are counted as rendered: each node placing a mesh, and GPU instances" {
  # Node 0 and its child node 1 place the 1,000-triangle mesh; node 2 places it 10 times, instanced.
  asset public/models/forest.glb '{"kind": "glb", "meshes": [[{"count": 3000}]],
    "nodes": [{"mesh": 0, "children": [1]}, {"mesh": 0}, {"mesh": 0, "instances": 10}]}'
  config '{"budgets": {"triangles": 11999}}'
  run -1 budget
  assert_has "public/models/forest.glb: 12,000 triangles > 11,999 triangles"
}

@test "triangles: only the default scene is walked; without scenes, every root node is" {
  asset public/models/scene.glb '{"kind": "glb", "meshes": [[{"count": 3000}], [{"count": 300000}]], "scene": [0]}'
  config '{"budgets": {"triangles": 999}}'
  run -1 budget
  assert_has "public/models/scene.glb: 1,000 triangles > 999 triangles"
  asset public/models/scene.glb '{"kind": "glb", "meshes": [[{"count": 3000}], [{"count": 300000}]], "scene": "none"}'
  run -1 budget
  assert_has "public/models/scene.glb: 101,000 triangles > 999 triangles"
}

@test "embedded images: the pixel size is read from PNG, JPEG, WebP, AVIF and KTX2 headers" {
  asset public/models/m.glb '{"kind": "glb", "images": [
    {"embed": {"kind": "png", "w": 4096, "h": 1024}, "name": "albedo"},
    {"embed": {"kind": "jpeg", "w": 3000, "h": 2000, "progressive": true, "fill": true}},
    {"embed": {"kind": "webp", "variant": "VP8", "w": 2100, "h": 100}},
    {"embed": {"kind": "webp", "variant": "VP8L", "w": 1000, "h": 2049}},
    {"embed": {"kind": "webp", "variant": "VP8X", "w": 5000, "h": 10}},
    {"embed": {"kind": "avif", "w": 2049, "h": 2}},
    {"embed": {"kind": "ktx2", "w": 4096, "h": 4096}},
    {"embed": {"kind": "jpeg", "w": 2048, "h": 2048}},
    {"embed": {"kind": "webp", "variant": "VP8L", "w": 16, "h": 16}}]}'
  run -1 budget
  assert_has 'public/models/m.glb image 0 "albedo": 4,096 px (4096x1024) > 2,048 px (texturePx)'
  assert_has "public/models/m.glb image 1: 3,000 px (3000x2000) > 2,048 px"
  assert_has "public/models/m.glb image 2: 2,100 px (2100x100) > 2,048 px"
  assert_has "public/models/m.glb image 3: 2,049 px (1000x2049) > 2,048 px"
  assert_has "public/models/m.glb image 4: 5,000 px (5000x10) > 2,048 px"
  assert_has "public/models/m.glb image 5: 2,049 px (2049x2) > 2,048 px"
  assert_has "public/models/m.glb image 6: 4,096 px (4096x4096) > 2,048 px"
  assert_lacks "image 7"
  assert_lacks "image 8"
  assert_has "1 model (9 images inside)"
}

@test "embedded images: bytes over textureKB fail" {
  asset public/models/heavy.glb '{"kind": "glb", "images": [{"embed": {"kind": "png", "w": 512, "h": 512, "pad": 600000}}]}'
  run -1 budget
  assert_has "public/models/heavy.glb image 0: 586."
  assert_has "KB > 512 KB (textureKB)"
}

@test "a .gltf counts the .bin and image files it points at, and checks the image once" {
  mkdir -p "$R/public/models"
  asset public/models/tex.png '{"kind": "png", "w": 1024, "h": 1024, "pad": 700000}'
  asset public/models/scene.gltf '{"kind": "gltf", "bin_uri": "scene.bin", "pad": 1000000, "images": [{"uri": "tex.png"}]}'
  run -1 budget
  assert_has "3D-BUDGET public/models/scene.gltf: 1660."
  assert_has "KB > 1,536 KB (modelKB)"
  assert_has "3D-BUDGET public/models/tex.png (image 0 of public/models/scene.gltf): 683."
  assert_has "KB > 512 KB (textureKB)"
  # tex.png sits in a texture folder, and is not reported a second time on its own.
  [ "$(printf '%s\n' "$output" | grep -c 'tex.png')" -eq 1 ]
  assert_has "1 model (1 image inside), 0 textures"
}

@test "a texture file shared by two models counts toward both, and is reported once" {
  asset public/models/shared.png '{"kind": "png", "w": 4096, "h": 16, "pad": 900000}'
  asset public/models/a.gltf '{"kind": "gltf", "images": [{"uri": "shared.png"}, {"uri": "shared.png"}]}'
  asset public/models/b.gltf '{"kind": "gltf", "images": [{"uri": "shared.png"}]}'
  config '{"budgets": {"modelKB": 800}}'
  run -1 budget
  [ "$(printf '%s\n' "$output" | grep -c 'shared.png (image')" -eq 2 ]
  assert_has "public/models/shared.png (image 0 of public/models/a.gltf): 4,096 px"
  assert_has "public/models/shared.png (image 0 of public/models/a.gltf): 879."
  assert_has "3D-BUDGET public/models/a.gltf: 879."
  assert_has "3D-BUDGET public/models/b.gltf: 879."
}

@test "a URI-encoded image path is decoded" {
  asset "public/models/my tex.png" '{"kind": "png", "w": 4000, "h": 10}'
  asset public/models/a.gltf '{"kind": "gltf", "images": [{"uri": "my%20tex.png"}]}'
  run -1 budget
  assert_has "public/models/my tex.png (image 0 of public/models/a.gltf): 4,000 px"
}

@test "data: URI images and buffers are decoded and checked" {
  asset public/models/inline.gltf '{"kind": "gltf", "images": [{"data": {"kind": "png", "w": 3000, "h": 10}}]}'
  run -1 budget
  assert_has "public/models/inline.gltf image 0: 3,000 px (3000x10) > 2,048 px"
}

@test "a model pointing at a missing file, or outside the repository, is unreadable" {
  asset public/models/a.gltf '{"kind": "gltf", "images": [{"uri": "missing.png"}]}'
  run -1 budget
  assert_has "3D-BUDGET public/models/a.gltf: unreadable, image 0 points at public/models/missing.png, which does not exist"
  asset public/models/a.gltf '{"kind": "gltf", "images": [{"uri": "../../../outside.png"}]}'
  run -1 budget
  assert_has "public/models/a.gltf: unreadable, image 0 points outside the repository"
  # ../../../ from public/models/ is the test's temp folder: outside the repo, inside the sandbox.
  asset public/models/b.gltf '{"kind": "gltf", "bin_uri": "../../../b.bin"}'
  run -1 budget
  assert_has "public/models/b.gltf: unreadable, buffer 0 points outside the repository"
}

@test "a remote image is named, not checked, and does not fail the gate" {
  asset public/models/a.gltf '{"kind": "gltf", "images": [{"uri": "https://cdn.example.test/t.png"}]}'
  run -0 budget
  assert_has "3d-budget: warning: public/models/a.gltf image 0 is a remote file, not checked"
}

@test "files that are not glTF 2.0 are unreadable, never skipped" {
  printf 'not a model at all' >"$R/public/junk.glb"
  asset public/v1.glb '{"kind": "glb", "glb_version": 1}'
  asset public/old.gltf '{"kind": "gltf", "asset_version": "1.0"}'
  printf '{"asset": ' >"$R/public/broken.gltf"
  asset public/cut.glb '{"kind": "glb", "pad": 64}'
  python3 -c 'import sys; p = sys.argv[1]; d = open(p, "rb").read(); open(p, "wb").write(d[:-40])' "$R/public/cut.glb"
  run -1 budget
  assert_has "public/junk.glb: unreadable, not a glTF binary (no glTF header)"
  assert_has "public/v1.glb: unreadable, glTF binary version 1, not 2"
  assert_has "public/old.gltf: unreadable, not glTF 2.0 (asset.version)"
  assert_has "public/broken.gltf: unreadable, not JSON"
  assert_has "public/cut.glb: unreadable, its header says"
  assert_has "5 over budget or unreadable"
}

@test "names from inside a model are printed without control characters" {
  asset public/models/m.glb '{"kind": "glb", "images": [{"embed": {"kind": "png", "w": 4096, "h": 1}, "name": "a\u001b[31mb"}]}'
  run -1 budget
  assert_lacks $'\033'
  assert_has 'image 0 "a [31mb"'
}

# ── textures and environment maps ──────────────────────────────────────────────────────────────

@test "textures: KTX2 anywhere under the roots, plain images only inside textureDirs" {
  asset public/gpu/huge.ktx2 '{"kind": "ktx2", "w": 4096, "h": 2048}'
  asset public/textures/wide.webp '{"kind": "webp", "variant": "VP8X", "w": 4096, "h": 512}'
  asset public/images/photo.png '{"kind": "png", "w": 6000, "h": 4000}'
  asset public/textures/ok.jpg '{"kind": "jpeg", "w": 1024, "h": 1024}'
  run -1 budget
  assert_has "3D-BUDGET public/gpu/huge.ktx2: 4,096 px (4096x2048) > 2,048 px (texturePx)"
  assert_has "3D-BUDGET public/textures/wide.webp: 4,096 px (4096x512) > 2,048 px (texturePx)"
  assert_lacks "photo.png"
  assert_has "0 models, 3 textures, 0 environment maps"
  config '{"textureDirs": ["public/textures", "public/images"]}'
  run -1 budget
  assert_has "public/images/photo.png: 6,000 px (6000x4000)"
}

@test "texture bytes: over textureKB fails, under passes" {
  asset public/textures/big.png '{"kind": "png", "w": 256, "h": 256, "pad": 530000}'
  run -1 budget
  assert_has "public/textures/big.png: 517."
  assert_has "KB > 512 KB (textureKB)"
  asset public/textures/big.png '{"kind": "png", "w": 256, "h": 256, "pad": 520000}'
  run -0 budget
}

@test "environment maps: .hdr and .exr are held to environmentKB" {
  asset public/env/studio.hdr '{"kind": "hdr", "pad": 2200000}'
  asset public/env/small.exr '{"kind": "bytes", "pad": 1000}'
  run -1 budget
  assert_has "3D-BUDGET public/env/studio.hdr: 2148."
  assert_has "KB > 2,048 KB (environmentKB)"
  assert_lacks "small.exr:"
  assert_has "2 environment maps under public"
}

@test "node_modules and symlinked folders are not scanned" {
  asset public/node_modules/pkg/huge.glb '{"kind": "glb", "pad": 3000000}'
  mkdir -p "$BATS_TEST_TMPDIR/elsewhere"
  python3 "$MAKE" "$BATS_TEST_TMPDIR/elsewhere/huge.glb" '{"kind": "glb", "pad": 3000000}'
  ln -s "$BATS_TEST_TMPDIR/elsewhere" "$R/public/linked"
  run -0 budget
  assert_has "0 models"
}

# ── exceptions and modes ───────────────────────────────────────────────────────────────────────

@test "an exception raises one file's budget, and says so when even that is exceeded" {
  asset public/models/hero.glb '{"kind": "glb", "meshes": [[{"count": 450000}]]}'
  asset public/models/prop.glb '{"kind": "glb", "meshes": [[{"count": 450000}]]}'
  config '{"exceptions": [{"path": "public/models/hero.glb", "budget": "triangles", "max": 200000, "reason": "the hero model is seen full screen"}]}'
  run -1 budget
  assert_lacks "hero.glb"
  assert_has "public/models/prop.glb: 150,000 triangles > 100,000 triangles (triangles)"
  asset public/models/hero.glb '{"kind": "glb", "meshes": [[{"count": 750000}]]}'
  rm "$R/public/models/prop.glb"
  run -1 budget
  assert_has "public/models/hero.glb: 250,000 triangles > 200,000 triangles (triangles, raised by an exception)"
}

@test "an exception for an image inside a model is keyed by the model" {
  asset public/models/hero.glb '{"kind": "glb", "images": [{"embed": {"kind": "png", "w": 4096, "h": 4096}}]}'
  config '{"exceptions": [{"path": "public/models/hero.glb", "budget": "texturePx", "max": 4096, "reason": "the hero is seen full screen on 4K"}]}'
  run -0 budget
}

@test "stale exceptions are warned about, and do not fail the gate" {
  asset public/models/small.glb '{"kind": "glb"}'
  asset public/env/a.hdr '{"kind": "hdr", "pad": 10}'
  config '{"exceptions": [
    {"path": "public/models/gone.glb", "budget": "triangles", "max": 200000, "reason": "a model that was deleted"},
    {"path": "public/models/small.glb", "budget": "triangles", "max": 200000, "reason": "it used to be big"},
    {"path": "public/env/a.hdr", "budget": "triangles", "max": 200000, "reason": "the wrong kind of budget"}]}'
  run -0 budget
  assert_has "warning: exception for public/models/gone.glb (triangles) names a file that does not exist; remove it"
  assert_has "warning: exception for public/models/small.glb (triangles) is no longer needed: the file fits the budget"
  assert_has "warning: exception for public/env/a.hdr (triangles) does not apply to that file; remove it"
}

@test "--warn reports every finding and exits 0" {
  asset public/models/big.glb '{"kind": "glb", "pad": 1600000}'
  run -0 budget --warn
  assert_has "3D-BUDGET public/models/big.glb:"
  assert_has "1 over budget or unreadable"
}

@test "it checks the repo it lives in, from any working directory" {
  asset public/models/big.glb '{"kind": "glb", "pad": 1600000}'
  cd "$BATS_TEST_TMPDIR"
  run -1 "$JS" "$R/scripts/check/3d-budget.mjs"
  assert_has "3D-BUDGET public/models/big.glb:"
}

@test "the same file runs under bun" {
  command -v bun >/dev/null 2>&1 || skip "bun is not installed"
  asset public/models/m.glb '{"kind": "glb", "meshes": [[{"count": 330000}]], "images": [{"embed": {"kind": "avif", "w": 3000, "h": 3}}]}'
  # shellcheck disable=SC2016 # $1 belongs to the inner shell
  run -1 bash -c 'cd "$1" && bun scripts/check/3d-budget.mjs' _ "$R"
  assert_has "public/models/m.glb: 110,000 triangles > 100,000 triangles"
  assert_has "public/models/m.glb image 0: 3,000 px (3000x3) > 2,048 px"
}
