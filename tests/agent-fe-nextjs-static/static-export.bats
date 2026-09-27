#!/usr/bin/env bats
# static-export.mjs: keeps the toy site static; each failure case matches what `next build`
# rejects (missing force-static, missing generateStaticParams) or drops without failing
# (headers(), a proxy file, a POST route handler).

load helpers

setup() { make_site; }

@test "static-export: the toy site passes in export mode" {
  check static-export
  [ "$status" -eq 0 ]
  [[ "$output" == *"export mode"* ]] || false
  [[ "$output" == *"0 error(s)"* ]] || false
}

@test "static-export: a POST route handler is refused in export mode" {
  mkdir -p app/api/contact
  printf '%s\n' "export const dynamic = 'force-static';" \
    'export async function POST(request: Request) { return new Response(await request.text()); }' >app/api/contact/route.ts
  check static-export
  [ "$status" -eq 1 ]
  [[ "$output" == *"app/api/contact/route.ts: exports POST"* ]] || false
}

@test "static-export: a route handler without force-static is refused in export mode" {
  replace app/robots.ts "export const dynamic = 'force-static';" ""
  check static-export
  [ "$status" -eq 1 ]
  [[ "$output" == *"app/robots.ts: needs export const dynamic = 'force-static'"* ]] || false
}

@test "static-export: headers() in next.config is refused in export mode" {
  replace next.config.mjs "images: { unoptimized: true }," "images: { unoptimized: true },
  async headers() { return []; },"
  check static-export
  [ "$status" -eq 1 ]
  [[ "$output" == *"headers() is ignored under output: 'export'"* ]] || false
}

@test "static-export: a proxy or middleware file is refused in export mode" {
  printf '%s\n' 'export function proxy() {}' >proxy.ts
  mkdir -p src && printf '%s\n' 'export function middleware() {}' >src/middleware.ts
  check static-export
  [ "$status" -eq 1 ]
  [[ "$output" == *"proxy.ts: a proxy file does not run in a static export"* ]] || false
  [[ "$output" == *"src/middleware.ts: a middleware file does not run"* ]] || false
}

@test "static-export: a dynamic segment without generateStaticParams is refused" {
  replace "app/blog/[slug]/page.tsx" "export function generateStaticParams" "function unusedParams"
  check static-export
  [ "$status" -eq 1 ]
  [[ "$output" == *"dynamic segment blog/[slug] has no generateStaticParams"* ]] || false
}

@test "static-export: generateStaticParams in a layout at the segment counts" {
  replace "app/blog/[slug]/page.tsx" "export function generateStaticParams" "function unusedParams"
  printf '%s\n' "export function generateStaticParams() { return [{ slug: 'hello' }]; }" \
    'export default function Layout({ children }: { children: React.ReactNode }) { return children; }' >"app/blog/[slug]/layout.tsx"
  check static-export
  [ "$status" -eq 0 ]
}

@test "static-export: a server action is refused in export mode" {
  printf '%s\n' "'use server';" 'export async function send() {}' >app/actions.ts
  check static-export
  [ "$status" -eq 1 ]
  [[ "$output" == *"app/actions.ts: a server action ('use server') cannot run in a static export"* ]] || false
}

@test "static-export: 'use server' inside a comment is not a server action" {
  printf '%s\n' "// 'use server' would make this an action" 'export const x = 1;' >app/notes.ts
  check static-export
  [ "$status" -eq 0 ]
}

@test "static-export: cookies(), force-dynamic, ISR and searchParams in pages are refused" {
  printf '%s\n' "import { cookies } from 'next/headers';" "export const dynamic = 'force-dynamic';" 'export const revalidate = 60;' \
    'export default async function P({ searchParams }: { searchParams: Promise<object> }) { await cookies(); return null; }' >app/about/page.tsx
  check static-export
  [ "$status" -eq 1 ]
  [[ "$output" == *"force-dynamic renders on every request"* ]] || false
  [[ "$output" == *"revalidate = 60 (ISR) needs a server"* ]] || false
  [[ "$output" == *"reads searchParams in a server page"* ]] || false
  [[ "$output" == *"cookies()/headers()/draftMode()"* ]] || false
}

@test "static-export: next/image without unoptimized or a loader is refused in export mode" {
  replace next.config.mjs "  images: { unoptimized: true },
" ""
  check static-export
  [ "$status" -eq 1 ]
  [[ "$output" == *"next/image with the default loader cannot be exported"* ]] || false
}

@test "static-export: a missing not-found page is refused" {
  rm app/not-found.tsx
  check static-export
  [ "$status" -eq 1 ]
  [[ "$output" == *"no not-found page"* ]] || false
}

@test "static-export: ssg-with-endpoints allows route handlers under the endpoints globs only" {
  replace next.config.mjs "  output: 'export',
" ""
  mkdir -p app/api/contact app/hooks
  printf '%s\n' 'export async function POST(request: Request) { return new Response(await request.text()); }' >app/api/contact/route.ts
  check static-export
  [ "$status" -eq 0 ]
  [[ "$output" == *"ssg-with-endpoints mode"* ]] || false
  printf '%s\n' 'export async function POST() { return new Response(null); }' >app/hooks/route.ts
  check static-export
  [ "$status" -eq 1 ]
  [[ "$output" == *"app/hooks/route.ts: a route handler outside the endpoints globs"* ]] || false
}

@test "static-export: the mode can be forced from the config" {
  set_config mode '"ssg-with-endpoints"'
  printf '%s\n' 'export function proxy() {}' >proxy.ts
  check static-export
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN  proxy.ts: runs on every request"* ]] || false
}

@test "static-export: app machinery is reported as a warning" {
  printf '%s\n' "import { QueryClient } from '@tanstack/react-query';" 'export const client = new QueryClient();' >app/providers.tsx
  check static-export
  [ "$status" -eq 0 ]
  [[ "$output" == *"imports @tanstack/react-query (a client data cache)"* ]] || false
}

@test "static-export: a project without an app folder is a usage error" {
  rm -rf app
  check static-export
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"no app/ or src/app/ folder"* ]] || false
}
