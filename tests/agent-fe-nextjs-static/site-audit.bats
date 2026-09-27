#!/usr/bin/env bats
# site-audit.mjs: the post-build runner over every check.

load helpers

setup() { make_site; }

@test "site-audit: every check passes on the toy site" {
  run --separate-stderr node "$CHECKS/site-audit.mjs"
  [ "$status" -eq 0 ]
  [[ "$output" == *"10 check(s), 0 failed"* ]] || false
}

@test "site-audit: every check passes on the ssg-with-endpoints layout" {
  to_ssg_layout
  run --separate-stderr node "$CHECKS/site-audit.mjs"
  [ "$status" -eq 0 ]
  [[ "$output" == *"10 check(s), 0 failed"* ]] || false
}

@test "site-audit: one failing check fails the run and is named in the table" {
  replace out/index.html '<a href="/about">About</a>' '<a href="/careers">Careers</a>'
  run --separate-stderr node "$CHECKS/site-audit.mjs"
  [ "$status" -eq 1 ]
  [[ "$output" == *"broken-links          1"* ]] || false
  [[ "$output" == *"10 check(s), 1 failed"* ]] || false
}

@test "site-audit: --only runs the named checks, --env reaches sitemap-robots" {
  run --separate-stderr node "$CHECKS/site-audit.mjs" --only sitemap-robots,metadata --env preview
  [ "$status" -eq 1 ]
  [[ "$output" == *"this build can be indexed"* ]] || false
  [[ "$output" == *"2 check(s), 1 failed"* ]] || false
}

@test "site-audit: a check that cannot run makes the run exit 2" {
  rm -rf out
  run --separate-stderr node "$CHECKS/site-audit.mjs" --only metadata
  [ "$status" -eq 2 ]
  run --separate-stderr node "$CHECKS/site-audit.mjs" --only nope
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"no check named nope"* ]] || false
}
