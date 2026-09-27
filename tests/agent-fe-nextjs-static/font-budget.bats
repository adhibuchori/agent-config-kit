#!/usr/bin/env bats
# font-budget.mjs: font families, hosts and formats, from the build and from the source.

load helpers

setup() { make_site; }

@test "font-budget: the toy site passes from the build and from the source" {
  check font-budget
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 family from 1 built stylesheet(s)"* ]] || false
  check font-budget --source
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 family from source files"* ]] || false
}

@test "font-budget: a third family in the built CSS fails (the local() fallback face does not count)" {
  printf '%s\n' '@font-face{font-family:display;src:url(../media/brand.woff2)format("woff2");font-display:swap}' \
    '@font-face{font-family:"__Mono_1a2b3c";src:url(../media/brand.woff2)format("woff2");font-display:swap}' >>out/_next/static/chunks/app.css
  check font-budget
  [ "$status" -eq 1 ]
  [[ "$output" == *"3 font families, budget 2: brand"*"display"*"Mono"* ]] || false
}

@test "font-budget: a third family in the source fails" {
  printf '%s\n' "import { Inter, Playfair_Display } from 'next/font/google';" \
    "export const inter = Inter({ subsets: ['latin'] });" \
    "export const display = Playfair_Display({ subsets: ['latin'], weight: ['400', '700'] });" >app/fonts.ts
  check font-budget --source
  [ "$status" -eq 1 ]
  [[ "$output" == *"3 font families, budget 2"*"Inter (app/fonts.ts)"*"Playfair Display (app/fonts.ts)"* ]] || false
}

@test "font-budget: fonts from a third-party host fail" {
  printf '%s\n' '@import url("https://fonts.googleapis.com/css2?family=Inter");' >app/globals.css
  check font-budget --source
  [ "$status" -eq 1 ]
  [[ "$output" == *"app/globals.css: requests fonts from a third-party host"* ]] || false
}

@test "font-budget: a face with no font-display or a non-WOFF2 file warns" {
  cp out/_next/static/media/brand.woff2 out/_next/static/media/brand.ttf
  replace out/_next/static/chunks/app.css 'src:url(../media/brand.woff2)format("woff2");font-display:swap' 'src:url(../media/brand.ttf)format("truetype")'
  check font-budget
  [ "$status" -eq 0 ]
  [[ "$output" == *'@font-face "brand" has font-display unset'* ]] || false
  [[ "$output" == *"brand.ttf: is not WOFF2"* ]] || false
}

@test "font-budget: a face that points at a missing file fails" {
  rm out/_next/static/media/brand.woff2
  check font-budget
  [ "$status" -eq 1 ]
  [[ "$output" == *"points at ../media/brand.woff2, which is not in the build"* ]] || false
}
