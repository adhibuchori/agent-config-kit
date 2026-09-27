#!/usr/bin/env bats
# image-budget.mjs: image budgets, unused public/ files and <img> dimensions on the toy site.

load helpers

setup() { make_site; }

@test "image-budget: the toy site passes" {
  check image-budget
  [ "$status" -eq 0 ]
  [[ "$output" == *"0 unused"* ]] || false
  [[ "$output" == *"0 error(s)"* ]] || false
}

@test "image-budget: an unused public file fails, unless listed in images.unusedIgnore" {
  node "$FIXTURE/make-assets.mjs" --png public/images/old-banner.png 10 10
  check image-budget
  [ "$status" -eq 1 ]
  [[ "$output" == *"public/images/old-banner.png: is not referenced by the source or the build"* ]] || false
  set_config images.unusedIgnore '["images/old-*.png"]'
  check image-budget
  [ "$status" -eq 0 ]
}

@test "image-budget: a file used only through the build output counts as used" {
  node "$FIXTURE/make-assets.mjs" --png public/images/team.png 10 10
  replace out/about.html '<a href="/">Home</a>' '<a href="/">Home</a><img alt="Team" width="10" height="10" src="/images/team.png"/>'
  check image-budget
  [ "$status" -eq 0 ]
  check image-budget --source-only
  [ "$status" -eq 1 ]
  [[ "$output" == *"public/images/team.png: is not referenced"* ]] || false
}

@test "image-budget: an image over the byte budget fails" {
  node "$FIXTURE/make-assets.mjs" --bytes public/images/hero.png 300
  check image-budget
  [ "$status" -eq 1 ]
  [[ "$output" == *"public/images/hero.png: 301 KB is over the 250 KB image budget"* ]] || false
}

@test "image-budget: an image wider than the cap fails" {
  set_config images.maxWidthPx 1000
  check image-budget
  [ "$status" -eq 1 ]
  [[ "$output" == *"public/images/hero.png: 1200px wide; nothing on a page needs more than 1000px"* ]] || false
}

@test "image-budget: a large PNG only warns to use AVIF or WebP" {
  set_config images.modernFormatKB 1
  check image-budget
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN  public/images/hero.png:"*"an AVIF or WebP copy is usually far smaller"* ]] || false
}

@test "image-budget: an <img> without width and height in the build fails" {
  replace out/index.html '<img alt="A toy hero" width="1200" height="630"' '<img alt="A toy hero"'
  check image-budget
  [ "$status" -eq 1 ]
  [[ "$output" == *'out/index.html <img src="/images/hero.png">: has no width and height'* ]] || false
}

@test "image-budget: a next/image fill image is accepted without width and height" {
  replace out/index.html '<img alt="A toy hero" width="1200" height="630" decoding="async" data-nimg="1"' '<img alt="A toy hero" decoding="async" data-nimg="fill"'
  check image-budget
  [ "$status" -eq 0 ]
}
