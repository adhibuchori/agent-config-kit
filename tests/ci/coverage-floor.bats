#!/usr/bin/env bats
# actions/quality-gate/scripts/coverage-floor.mjs: lcov, istanbul summary and final reports, and Go's
# cover profile; the newest report wins; every measured metric counts; exit 1 below, 3 with no
# report, 2 on bad input.

load helpers

setup() {
  ci_isolate
  need_node
  D="$BATS_TEST_TMPDIR/cov"
  mkdir -p "$D/coverage"
}

floor() { # $1 threshold
  run --separate-stderr node "$QG/coverage-floor.mjs" --threshold "$1" "$D/coverage"
}

@test "coverage-floor: lcov at 100% passes a 100 floor; one missed line fails it" {
  printf 'SF:a.ts\nFNF:2\nFNH:2\nLF:4\nLH:4\nend_of_record\nSF:b.ts\nFNF:1\nFNH:1\nLF:6\nLH:6\nend_of_record\n' >"$D/coverage/lcov.info"
  floor 100
  [ "$status" -eq 0 ]
  [[ "$output" == *"lines"*"10 / 10"*"100.00%  ok"* ]]
  [[ "$output" == *"functions"*"3 / 3"* ]]
  [[ "$output" != *"branches"* ]]
  printf 'SF:a.ts\nFNF:2\nFNH:2\nLF:4\nLH:3\nend_of_record\n' >"$D/coverage/lcov.info"
  floor 100
  [ "$status" -eq 1 ]
  [[ "$output" == *"75.00%  BELOW"* ]]
  floor 75
  [ "$status" -eq 0 ]
}

@test "coverage-floor: 99.995% is below 100, not rounded up" {
  { printf 'SF:a.ts\nLF:20000\nLH:19999\nend_of_record\n'; } >"$D/coverage/lcov.info"
  floor 100
  [ "$status" -eq 1 ]
}

@test "coverage-floor: lcov without LF/LH counts the DA lines; branches count when measured" {
  printf 'SF:a.ts\nDA:1,1\nDA:2,0\nBRF:4\nBRH:4\nend_of_record\n' >"$D/coverage/lcov.info"
  floor 50
  [ "$status" -eq 0 ]
  [[ "$output" == *"lines"*"1 / 2"* ]]
  [[ "$output" == *"branches"*"4 / 4"* ]]
}

@test "coverage-floor: an istanbul summary report" {
  printf '{"total":{"lines":{"total":10,"covered":10,"pct":100},"statements":{"total":12,"covered":12},"functions":{"total":3,"covered":3},"branches":{"total":4,"covered":3}}}\n' >"$D/coverage/coverage-summary.json"
  floor 100
  [ "$status" -eq 1 ]
  [[ "$output" == *"branches"*"3 / 4"*"BELOW"* ]]
}

@test "coverage-floor: an istanbul final report (vitest's default json reporter)" {
  cat >"$D/coverage/coverage-final.json" <<'EOF'
{"/src/a.ts":{"path":"/src/a.ts",
 "statementMap":{"0":{"start":{"line":1}},"1":{"start":{"line":2}},"2":{"start":{"line":2}}},
 "s":{"0":1,"1":0,"2":3},
 "fnMap":{},"f":{"0":1},
 "branchMap":{},"b":{"0":[1,0]}}}
EOF
  floor 50
  [ "$status" -eq 0 ]
  [[ "$output" == *"lines"*"2 / 2"* ]]
  [[ "$output" == *"statements"*"2 / 3"* ]]
  [[ "$output" == *"branches"*"1 / 2"* ]]
  floor 100
  [ "$status" -eq 1 ]
}

@test "coverage-floor: a Go cover profile counts statements; one missed block fails 100" {
  printf 'mode: atomic\nexample.com/svc/a.go:3.20,5.2 2 4\nexample.com/svc/a.go:7.10,9.3 3 1\nexample.com/svc/b.go:1.1,2.2 1 9\n' \
    >"$D/coverage/coverage.out"
  floor 100
  [ "$status" -eq 0 ]
  [[ "$output" == *"coverage.out (floor 100%)"* ]] || false
  [[ "$output" == *"statements"*"6 / 6"*"ok"* ]] || false
  [[ "$output" != *"lines"* ]] || false
  printf 'mode: set\nexample.com/svc/a.go:3.20,5.2 2 1\nexample.com/svc/a.go:7.10,9.3 3 0\n' >"$D/coverage/coverage.out"
  floor 100
  [ "$status" -eq 1 ]
  [[ "$output" == *"statements"*"2 / 5"*"BELOW"* ]] || false
  floor 40
  [ "$status" -eq 0 ]
}

@test "coverage-floor: a block two test binaries both report counts once, covered if either ran it" {
  # The same block appears once per test binary that instrumented it: 0 in one, 3 in the other.
  printf 'mode: count\nexample.com/svc/a.go:3.20,5.2 2 0\nexample.com/svc/a.go:3.20,5.2 2 3\nexample.com/svc/a.go:7.1,8.2 1 1\n' \
    >"$D/coverage/coverage.out"
  floor 100
  [ "$status" -eq 0 ]
  [[ "$output" == *"statements"*"3 / 3"* ]] || false
}

@test "coverage-floor: a Go profile with no mode line or an unreadable line exits 2; raw.out is not read" {
  printf 'example.com/svc/a.go:3.20,5.2 2 4\n' >"$D/coverage/coverage.out"
  floor 100
  [ "$status" -eq 2 ]
  [[ "$stderr" == *'no "mode:" line'* ]] || false
  printf 'mode: set\nnot a block\n' >"$D/coverage/coverage.out"
  floor 100
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"unreadable profile line: not a block"* ]] || false
  rm "$D/coverage/coverage.out"
  printf 'mode: set\nexample.com/svc/a.go:3.20,5.2 2 0\n' >"$D/coverage/raw.out"
  floor 100
  [ "$status" -eq 3 ]
}

@test "coverage-floor: the newest report wins over an older one" {
  mkdir -p "$D/coverage/old"
  printf 'SF:a.ts\nLF:10\nLH:1\nend_of_record\n' >"$D/coverage/old/lcov.info"
  touch -t 202001010000 "$D/coverage/old/lcov.info"
  printf 'SF:a.ts\nLF:10\nLH:10\nend_of_record\n' >"$D/coverage/lcov.info"
  floor 100
  [ "$status" -eq 0 ]
  [[ "$output" == *"$D/coverage/lcov.info"* ]]
}

@test "coverage-floor: no report exits 3; an empty or broken one exits 2" {
  floor 100
  [ "$status" -eq 3 ]
  printf 'SF:a.ts\nend_of_record\n' >"$D/coverage/lcov.info"
  floor 100
  [ "$status" -eq 2 ]
  rm "$D/coverage/lcov.info"
  printf '{not json\n' >"$D/coverage/coverage-summary.json"
  floor 100
  [ "$status" -eq 2 ]
}

@test "coverage-floor: a bad threshold or no folder exits 2" {
  floor 101
  [ "$status" -eq 2 ]
  floor abc
  [ "$status" -eq 2 ]
  run --separate-stderr node "$QG/coverage-floor.mjs" --threshold 90
  [ "$status" -eq 2 ]
}
