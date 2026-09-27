#!/usr/bin/env bats
# og-image.mjs: share cards of the built toy site.

load helpers

setup() { make_site; }

@test "og-image: the toy site passes (the extension-less opengraph-image file is read by its bytes)" {
  check og-image
  [ "$status" -eq 0 ]
  [[ "$output" == *"4 indexable page(s), 1 image(s)"* ]] || false
  [[ "$output" == *"0 error(s)"* ]] || false
}

@test "og-image: the same site passes from the ssg-with-endpoints layout (opengraph-image.body)" {
  to_ssg_layout
  check og-image
  [ "$status" -eq 0 ]
}

@test "og-image: a page without og:image or og:title fails" {
  replace out/about.html '<meta property="og:image" content="https://example.com/opengraph-image?4f2a91c0d3e5b6a7"/>' ''
  replace out/about.html '<meta property="og:title" content="About | Toy Studio"/>' ''
  check og-image
  [ "$status" -eq 1 ]
  [[ "$output" == *"out/about.html: no og:image"* ]] || false
  [[ "$output" == *"out/about.html: no og:title"* ]] || false
}

@test "og-image: an image that is too small fails" {
  node "$FIXTURE/make-assets.mjs" --png out/opengraph-image 600 315
  replace out/index.html 'content="1200"' 'content="600"'
  replace out/index.html 'og:image:height" content="630"' 'og:image:height" content="315"'
  check og-image
  [ "$status" -eq 1 ]
  [[ "$output" == *"is 600x315; use at least 1200x630"* ]] || false
}

@test "og-image: declared width and height that do not match the file fail" {
  replace out/about.html '<meta property="og:image:width" content="1200"/>' '<meta property="og:image:width" content="1600"/>'
  check og-image
  [ "$status" -eq 1 ]
  [[ "$output" == *"og:image:width/height say 1600x630 but out/opengraph-image is 1200x630"* ]] || false
}

@test "og-image: a relative, localhost, missing or SVG image fails" {
  replace out/about.html 'https://example.com/opengraph-image?4f2a91c0d3e5b6a7' '/opengraph-image'
  replace out/blog/hello.html '<meta property="og:image" content="https://example.com/opengraph-image?4f2a91c0d3e5b6a7"/>' '<meta property="og:image" content="http://localhost:3000/opengraph-image"/>'
  replace out/id.html '<meta property="og:image" content="https://example.com/opengraph-image?4f2a91c0d3e5b6a7"/>' '<meta property="og:image" content="https://example.com/share.png"/>'
  replace out/index.html '<meta property="og:image" content="https://example.com/opengraph-image?4f2a91c0d3e5b6a7"/>' '<meta property="og:image" content="https://example.com/icon.svg"/>'
  check og-image
  [ "$status" -eq 1 ]
  [[ "$output" == *"og:image /opengraph-image is not an absolute URL"* ]] || false
  [[ "$output" == *"points at localhost: set metadataBase"* ]] || false
  [[ "$output" == *"og:image https://example.com/share.png is not in the build"* ]] || false
  [[ "$output" == *"out/icon.svg is not a raster image; share cards need PNG, JPEG, GIF or WebP"* ]] || false
}

@test "og-image: an image over the byte budget fails" {
  set_config ogImage.maxKB 1
  check og-image
  [ "$status" -eq 1 ]
  [[ "$output" == *"KB (budget 1 KB)"* ]] || false
}
