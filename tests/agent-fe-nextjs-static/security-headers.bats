#!/usr/bin/env bats
# security-headers.mjs: the static host's headers file, and a hash-based CSP against the build.

load helpers

setup() { make_site; }

@test "security-headers: the toy site passes, including every inline script hash" {
  check security-headers --verify-hashes
  [ "$status" -eq 0 ]
  [[ "$output" == *"_headers format, 5 path(s), 5 inline script check(s)"* ]] || false
  [[ "$output" == *"0 error(s), 0 warning(s)"* ]] || false
}

@test "security-headers: a missing headers file fails" {
  rm public/_headers
  check security-headers
  [ "$status" -eq 1 ]
  [[ "$output" == *"public/_headers: missing"* ]] || false
}

@test "security-headers: an inline script the CSP does not hash fails --verify-hashes" {
  replace out/about.html '<script>self.__next_f=self.__next_f||[]</script>' '<script>self.__next_f=[]</script>'
  check security-headers
  [ "$status" -eq 0 ]
  check security-headers --verify-hashes
  [ "$status" -eq 1 ]
  [[ "$output" == *"out/about.html: inline script 'sha256-"*"' is blocked by the CSP for /about"* ]] || false
}

@test "security-headers: --print-hashes lists what each page needs" {
  check security-headers --print-hashes
  [ "$status" -eq 0 ]
  [[ "$output" == *"/about	'sha256-sXjGqJ00dxxEvsgy0wz4SHVW5xv3gsSh03kmxXNPOKo='"* ]] || false
}

@test "security-headers: unsafe-eval, a wildcard script source and a missing object-src fail" {
  replace public/_headers "script-src 'self' 'sha256" "script-src 'self' 'unsafe-eval' https: 'sha256"
  replace public/_headers " object-src 'none';" ""
  check security-headers
  [ "$status" -eq 1 ]
  [[ "$output" == *"CSP allows 'unsafe-eval'"* ]] || false
  [[ "$output" == *"CSP script sources https: allow scripts from anywhere"* ]] || false
  [[ "$output" == *"CSP needs object-src 'none'"* ]] || false
}

@test "security-headers: 'unsafe-inline' without hashes only warns" {
  replace public/_headers "script-src 'self' 'sha256-sXjGqJ00dxxEvsgy0wz4SHVW5xv3gsSh03kmxXNPOKo='" "script-src 'self' 'unsafe-inline'"
  check security-headers --verify-hashes
  [ "$status" -eq 0 ]
  [[ "$output" == *"CSP allows 'unsafe-inline' scripts"* ]] || false
}

@test "security-headers: a short HSTS, no nosniff and no framing protection fail" {
  replace public/_headers "max-age=63072000" "max-age=86400"
  replace public/_headers "  X-Content-Type-Options: nosniff
" ""
  replace public/_headers "; frame-ancestors 'none'" ""
  check security-headers
  [ "$status" -eq 1 ]
  [[ "$output" == *"HSTS max-age=86400; use at least 31536000"* ]] || false
  [[ "$output" == *"X-Content-Type-Options must be nosniff"* ]] || false
  [[ "$output" == *"no framing protection"* ]] || false
}

@test "security-headers: strict-dynamic with <script src> and no integrity fails" {
  replace public/_headers "script-src 'self' 'sha256" "script-src 'strict-dynamic' 'sha256"
  check security-headers --verify-hashes
  [ "$status" -eq 1 ]
  [[ "$output" == *"'strict-dynamic' ignores 'self' and host sources, so 1 <script src> without integrity are blocked"* ]] || false
}

@test "security-headers: an nginx config is read as well" {
  printf '%s\n' 'server {' \
    "  add_header Content-Security-Policy \"default-src 'self'; object-src 'none'; base-uri 'self'; frame-ancestors 'none'\" always;" \
    '  add_header Strict-Transport-Security "max-age=63072000; includeSubDomains" always;' \
    '  add_header X-Content-Type-Options nosniff always;' \
    '  add_header Referrer-Policy strict-origin-when-cross-origin always;' \
    '  add_header Permissions-Policy "camera=()" always;' \
    '  add_header Cross-Origin-Opener-Policy same-origin always;' '}' >nginx.conf
  set_config headersFile '"nginx.conf"'
  check security-headers
  [ "$status" -eq 0 ]
  [[ "$output" == *"nginx format"* ]] || false
  check security-headers --verify-hashes
  [ "$status" -eq 1 ]
  [[ "$output" == *"is blocked by the CSP"* ]] || false
}

@test "security-headers: an empty headersFile skips loudly, never silently" {
  set_config headersFile '""'
  check security-headers
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIPPED: headersFile is empty"* ]] || false
}
