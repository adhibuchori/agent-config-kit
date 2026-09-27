#!/usr/bin/env bats
# broken-links.mjs: internal links, assets and fragments of the built toy site (no network).

load helpers

setup() { make_site; }

@test "broken-links: the toy site passes, and external links are counted, not fetched" {
  check broken-links
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 external reference(s)"* ]] || false
  [[ "$output" == *"0 error(s)"* ]] || false
}

@test "broken-links: the same site passes from the ssg-with-endpoints layout" {
  to_ssg_layout
  check broken-links
  [ "$status" -eq 0 ]
}

@test "broken-links: a link to a page that is not built fails" {
  replace out/index.html '<a href="/about">About</a>' '<a href="/careers">Careers</a>'
  check broken-links
  [ "$status" -eq 1 ]
  [[ "$output" == *'out/index.html <a href="/careers">: nothing in the build serves /careers'* ]] || false
}

@test "broken-links: a missing image, stylesheet or script fails" {
  replace out/about.html '/_next/static/chunks/app.css' '/_next/static/chunks/gone.css'
  replace out/index.html 'src="/images/hero.png"' 'src="/images/hero-old.png"'
  check broken-links
  [ "$status" -eq 1 ]
  [[ "$output" == *"nothing in the build serves /_next/static/chunks/gone.css"* ]] || false
  [[ "$output" == *"nothing in the build serves /images/hero-old.png"* ]] || false
}

@test "broken-links: a fragment with no matching id fails, on this page and on another" {
  replace out/index.html '<a href="#contact">Contact</a>' '<a href="#kontak">Contact</a>'
  replace out/about.html '<a href="/#contact">Contact</a>' '<a href="/#pricing">Pricing</a>'
  check broken-links
  [ "$status" -eq 1 ]
  [[ "$output" == *'no element with id "kontak" on this page'* ]] || false
  [[ "$output" == *'/ has no element with id "pricing"'* ]] || false
}

@test "broken-links: a relative link resolves against the page URL" {
  replace out/blog/hello.html '<a href="../about">About</a>' '<a href="about">About</a>'
  check broken-links
  [ "$status" -eq 1 ]
  [[ "$output" == *"nothing in the build serves /blog/about"* ]] || false
}

@test "broken-links: javascript: URLs and http: subresources fail" {
  replace out/about.html '<a href="/">Home</a>' '<a href="javascript:void(0)">Home</a><img alt="x" width="1" height="1" src="http://cdn.example.net/x.png"/>'
  check broken-links
  [ "$status" -eq 1 ]
  [[ "$output" == *"javascript: URL; use a <button> for actions"* ]] || false
  [[ "$output" == *"loads over http: from an https page (mixed content is blocked)"* ]] || false
}

@test "broken-links: an absolute link on the production origin is checked like an internal one" {
  replace out/about.html '<a href="/">Home</a>' '<a href="https://example.com/pricing">Pricing</a>'
  check broken-links
  [ "$status" -eq 1 ]
  [[ "$output" == *"nothing in the build serves /pricing"* ]] || false
}
