#!/usr/bin/env bats
# jsonld.mjs: structured data in the built toy site.

load helpers

setup() { make_site; }

@test "jsonld: the toy site passes (Organization, and a @graph of BlogPosting + BreadcrumbList)" {
  check jsonld
  [ "$status" -eq 0 ]
  [[ "$output" == *"2 block(s)"* ]] || false
  [[ "$output" == *"0 error(s)"* ]] || false
}

@test "jsonld: a block the renderer HTML-escaped is invalid JSON, with the reason" {
  replace out/index.html '{"@context":"https://schema.org","@type":"Organization"' '{&quot;@context&quot;:&quot;https://schema.org&quot;,"@type":"Organization"'
  check jsonld
  [ "$status" -eq 1 ]
  [[ "$output" == *"out/index.html [ld+json 1]: not valid JSON"* ]] || false
  [[ "$output" == *"it was HTML-escaped"* ]] || false
}

@test "jsonld: an Organization without url, and a relative logo, fail" {
  replace out/index.html '"url":"https://example.com",' ''
  replace out/index.html '"logo":"https://example.com/images/logo.png"' '"logo":"/images/logo.png"'
  check jsonld
  [ "$status" -eq 1 ]
  [[ "$output" == *"Organization has no url"* ]] || false
  [[ "$output" == *'logo "/images/logo.png" is not an absolute http(s) URL'* ]] || false
}

@test "jsonld: a missing @context or @type fails" {
  replace out/index.html '"@context":"https://schema.org",' ''
  replace out/blog/hello.html '{"@type":"BlogPosting",' '{'
  check jsonld
  [ "$status" -eq 1 ]
  [[ "$output" == *"out/index.html [ld+json 1]: no @context naming https://schema.org"* ]] || false
  [[ "$output" == *"out/blog/hello.html [ld+json 1]: a node has no @type"* ]] || false
}

@test "jsonld: a breadcrumb item without a position fails" {
  replace out/blog/hello.html '"position":2,' ''
  check jsonld
  [ "$status" -eq 1 ]
  [[ "$output" == *"BreadcrumbList item 2 has no integer position"* ]] || false
}

@test "jsonld: a raw < in a block only warns" {
  replace out/index.html '"name":"Toy Studio"' '"name":"Toy <Studio>"'
  check jsonld
  [ "$status" -eq 0 ]
  [[ "$output" == *'contains a raw "<": escape it as \u003c'* ]] || false
}
