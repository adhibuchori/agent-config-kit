#!/usr/bin/env bats
# sitemap-robots.mjs: robots.txt and the sitemap of the built toy site, production and preview.

load helpers

setup() { make_site; }

@test "sitemap-robots: the toy site passes" {
  check sitemap-robots
  [ "$status" -eq 0 ]
  [[ "$output" == *"4 sitemap URL(s)"* ]] || false
  [[ "$output" == *"0 error(s)"* ]] || false
}

@test "sitemap-robots: the same site passes from the ssg-with-endpoints layout (.next/server/app)" {
  to_ssg_layout
  check sitemap-robots
  [ "$status" -eq 0 ]
  [[ "$output" == *"4 sitemap URL(s)"* ]] || false
}

@test "sitemap-robots: a production robots.txt that blocks the site fails" {
  printf 'User-agent: *\nDisallow: /\n\nSitemap: https://example.com/sitemap.xml\n' >out/robots.txt
  check sitemap-robots
  [ "$status" -eq 1 ]
  [[ "$output" == *"blocks the home page for every crawler"* ]] || false
}

@test "sitemap-robots: a missing robots.txt and a relative Sitemap line fail" {
  rm out/robots.txt
  check sitemap-robots
  [ "$status" -eq 1 ]
  [[ "$output" == *"robots.txt: missing"* ]] || false
  printf 'User-agent: *\nAllow: /\nSitemap: /sitemap.xml\n' >out/robots.txt
  check sitemap-robots
  [ "$status" -eq 1 ]
  [[ "$output" == *"Sitemap /sitemap.xml is not an absolute URL"* ]] || false
}

@test "sitemap-robots: an indexable page missing from the sitemap fails, unless excluded" {
  cp out/about.html out/team.html
  replace out/team.html "https://example.com/about" "https://example.com/team"
  replace out/team.html "<title>About | Toy Studio</title>" "<title>Team | Toy Studio</title>"
  check sitemap-robots
  [ "$status" -eq 1 ]
  [[ "$output" == *"indexable page /team is missing from the sitemap"* ]] || false
  set_config sitemapExclude '["/team"]'
  check sitemap-robots
  [ "$status" -eq 0 ]
}

@test "sitemap-robots: a sitemap URL that is not built, noindex or off-site fails" {
  replace out/sitemap.xml "<loc>https://example.com/about</loc>" "<loc>https://example.com/gone</loc>"
  replace out/blog/hello.html '<meta charSet="utf-8"/>' '<meta charSet="utf-8"/><meta name="robots" content="noindex"/>'
  replace out/sitemap.xml "<loc>https://example.com/id</loc>" "<loc>https://other.example.net/id</loc>"
  check sitemap-robots
  [ "$status" -eq 1 ]
  [[ "$output" == *"https://example.com/gone does not match any built page"* ]] || false
  [[ "$output" == *"https://example.com/blog/hello is noindex"* ]] || false
  [[ "$output" == *"https://other.example.net/id is not on https://example.com"* ]] || false
}

@test "sitemap-robots: a URL listed twice fails" {
  replace out/sitemap.xml "<url>
<loc>https://example.com/about</loc>" "<url><loc>https://example.com/about/</loc></url>
<url>
<loc>https://example.com/about</loc>"
  check sitemap-robots
  [ "$status" -eq 1 ]
  [[ "$output" == *"https://example.com/about is listed twice"* ]] || false
}

@test "sitemap-robots: a sitemap index is followed" {
  mv out/sitemap.xml out/sitemap-pages.xml
  printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' \
    '<sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"><sitemap><loc>https://example.com/sitemap-pages.xml</loc></sitemap></sitemapindex>' >out/sitemap.xml
  check sitemap-robots
  [ "$status" -eq 0 ]
  [[ "$output" == *"4 sitemap URL(s)"* ]] || false
}

@test "sitemap-robots: --env preview fails when the build can be indexed and passes when it cannot" {
  check sitemap-robots --env preview
  [ "$status" -eq 1 ]
  [[ "$output" == *"this build can be indexed"* ]] || false
  printf 'User-agent: *\nDisallow: /\n' >out/robots.txt
  check sitemap-robots --env preview
  [ "$status" -eq 0 ]
}

@test "sitemap-robots: no siteUrl is an error, and NEXT_PUBLIC_SITE_URL supplies it" {
  set_config siteUrl '""'
  check sitemap-robots
  [ "$status" -eq 1 ]
  [[ "$output" == *"siteUrl is not set"* ]] || false
  NEXT_PUBLIC_SITE_URL=https://example.com check sitemap-robots
  [ "$status" -eq 0 ]
}

@test "sitemap-robots: nothing built is a usage error, not a pass" {
  rm -rf out
  check sitemap-robots
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"out does not exist: build the site first"* ]] || false
}
