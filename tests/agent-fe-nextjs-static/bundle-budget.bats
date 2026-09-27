#!/usr/bin/env bats
# bundle-budget.mjs: first-load JavaScript and CSS per built page, gzipped.

load helpers

setup() { make_site; }

@test "bundle-budget: the toy site passes and every built page is measured" {
  check bundle-budget
  [ "$status" -eq 0 ]
  [[ "$output" == *"5 page(s)"* ]] || false
  [[ "$output" == *"0 error(s), 0 warning(s)"* ]] || false
}

@test "bundle-budget: a page over the JavaScript budget fails, naming the page" {
  set_config bundle.maxJsKB 0.05
  check bundle-budget
  [ "$status" -eq 1 ]
  [[ "$output" == *"bundle-budget: ERROR out/index.html:"*"KB of JavaScript (gzipped) on first load; budget 0.05 KB"* ]] || false
}

@test "bundle-budget: a larger script on one page fails only that page" {
  node -e 'require("fs").writeFileSync("out/_next/static/chunks/big.js", require("crypto").randomBytes(80 * 1024).toString("base64"))'
  replace out/about.html '<script src="/_next/static/chunks/main.js" async=""></script>' \
    '<script src="/_next/static/chunks/main.js" async=""></script><script src="/_next/static/chunks/big.js" async=""></script>'
  set_config bundle.maxJsKB 50
  check bundle-budget
  [ "$status" -eq 1 ]
  [[ "$output" == *"ERROR out/about.html:"* ]] || false
  [[ "$output" != *"ERROR out/index.html:"* ]] || false
}

@test "bundle-budget: CSS over its budget fails" {
  set_config bundle.maxCssKB 0.01
  check bundle-budget
  [ "$status" -eq 1 ]
  [[ "$output" == *"KB of CSS (gzipped) on first load; budget 0.01 KB"* ]] || false
}

@test "bundle-budget: a script from another host is listed, not measured" {
  replace out/index.html '</body>' '<script src="https://cdn.example.net/widget.js" async=""></script></body>'
  check bundle-budget
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN  build: loads https://cdn.example.net/widget.js from another host"* ]] || false
}

@test "bundle-budget: --report prints every page, heaviest first" {
  check bundle-budget --report
  [ "$status" -eq 0 ]
  [[ "$output" == *"js KB  css KB"* ]] || false
  for p in / /about /blog/hello /id /404; do grep -qE "^$p +[0-9.]+ +[0-9.]+$" <<<"$output"; done
}

@test "bundle-budget: the ssg-with-endpoints layout reads chunks from .next/static" {
  to_ssg_layout
  set_config bundle.maxCssKB 0.01
  check bundle-budget
  [ "$status" -eq 1 ]
  [[ "$output" == *"KB of CSS (gzipped)"* ]] || false
}
