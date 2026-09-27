#!/usr/bin/env bats
# metadata.mjs: per-route metadata of the built toy site.

load helpers

setup() { make_site; }

@test "metadata: the toy site passes" {
  check metadata
  [ "$status" -eq 0 ]
  [[ "$output" == *"4 page(s) read from export output"* ]] || false
  [[ "$output" == *"0 error(s)"* ]] || false
}

@test "metadata: the same site passes from the ssg-with-endpoints layout" {
  to_ssg_layout
  check metadata
  [ "$status" -eq 0 ]
  [[ "$output" == *"ssg-with-endpoints output"* ]] || false
}

@test "metadata: a duplicate title and description fail" {
  replace out/blog/hello.html "<title>Hello | Toy Studio</title>" "<title>About | Toy Studio</title>"
  replace out/blog/hello.html "The first post on the Toy Studio blog, written to give the checks a nested route." \
    "Who runs Toy Studio, how the studio works, and where to find the team."
  check metadata
  [ "$status" -eq 1 ]
  [[ "$output" == *'/about, /blog/hello: share the title "About | Toy Studio"'* ]] || false
  [[ "$output" == *"/about, /blog/hello: share one description"* ]] || false
}

@test "metadata: a missing lang, viewport, title or description fails" {
  replace out/about.html '<html lang="en">' '<html>'
  replace out/about.html '<meta name="viewport" content="width=device-width, initial-scale=1"/>' ''
  replace out/about.html '<title>About | Toy Studio</title>' ''
  replace out/about.html '<meta name="description" content="Who runs Toy Studio, how the studio works, and where to find the team."/>' ''
  check metadata
  [ "$status" -eq 1 ]
  [[ "$output" == *"out/about.html: <html> has no lang attribute"* ]] || false
  [[ "$output" == *'no <meta name="viewport">'* ]] || false
  [[ "$output" == *"no <title>"* ]] || false
  [[ "$output" == *'no <meta name="description">'* ]] || false
}

@test "metadata: a relative, localhost or missing canonical fails" {
  replace out/about.html '<link rel="canonical" href="https://example.com/about"/>' '<link rel="canonical" href="/about"/>'
  replace out/blog/hello.html 'href="https://example.com/blog/hello"/>' 'href="http://localhost:3000/blog/hello"/>'
  replace out/id.html '<link rel="canonical" href="https://example.com/id"/>' ''
  check metadata
  [ "$status" -eq 1 ]
  [[ "$output" == *"canonical /about is not an absolute URL"* ]] || false
  [[ "$output" == *"points at localhost: set metadataBase"* ]] || false
  [[ "$output" == *'out/id.html: no <link rel="canonical">'* ]] || false
}

@test "metadata: a canonical to a page that is not built fails" {
  replace out/about.html '<link rel="canonical" href="https://example.com/about"/>' '<link rel="canonical" href="https://example.com/about-us"/>'
  check metadata
  [ "$status" -eq 1 ]
  [[ "$output" == *"canonical https://example.com/about-us does not match any built page"* ]] || false
}

@test "metadata: hreflang without x-default fails" {
  replace out/index.html '<link rel="alternate" hreflang="x-default" href="https://example.com"/>' ''
  check metadata
  [ "$status" -eq 1 ]
  [[ "$output" == *"out/index.html: hreflang alternates have no x-default"* ]] || false
}

@test "metadata: an hreflang set without the page itself fails" {
  replace out/id.html '<link rel="alternate" hreflang="id" href="https://example.com/id"/>' ''
  check metadata
  [ "$status" -eq 1 ]
  [[ "$output" == *"out/id.html: the hreflang set does not include the page itself"* ]] || false
}

@test "metadata: hreflang alternates that are not reciprocal fail" {
  replace out/index.html '<link rel="alternate" hreflang="id" href="https://example.com/id"/>' ''
  check metadata
  [ "$status" -eq 1 ]
  [[ "$output" == *"out/id.html: hreflang en page https://example.com does not link back to https://example.com/id"* ]] || false
}

@test "metadata: a short description only warns" {
  replace out/about.html "Who runs Toy Studio, how the studio works, and where to find the team." "Short."
  check metadata
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN  out/about.html: description is 6 characters"* ]] || false
}

@test "metadata: a noindex page is not held to the indexable-page rules" {
  replace out/about.html '<link rel="canonical" href="https://example.com/about"/>' '<meta name="robots" content="noindex, follow"/>'
  check metadata
  [ "$status" -eq 0 ]
}
