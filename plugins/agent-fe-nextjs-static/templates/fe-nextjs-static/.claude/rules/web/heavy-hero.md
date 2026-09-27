---
paths:
  - '**/*hero*'
  - '**/*Hero*'
  - '**/*canvas*'
  - '**/*scene*'
  - '**/*video*'
  - '**/app/page.tsx'
  - '**/app/**/page.tsx'
---

# A heavy hero without a slow page

A landing page's first screen is where a video, a WebGL scene or a big animation is most tempting,
and where it costs the most: it becomes the Largest Contentful Paint, blocks the main thread, and
drains a phone's battery before the visitor has read a word.

## The rule

- The LCP element is HTML text or an image, never a `<canvas>`, a WebGL scene or a video that must
  load first. The headline and the call to action render in the first HTML.
- The heavy part is an enhancement over a still: a poster image (sized, with `priority`) shows at
  once, and the scene or video replaces or overlays it later.
- It loads after the first paint: `next/dynamic` with `ssr: false` in a client component, mounted
  when the browser is idle or when the section scrolls into view (`IntersectionObserver`), never
  imported at the top of the page.
- `prefers-reduced-motion: reduce` gets the still, not a slower animation. So does a device that
  says it wants to save data, and a browser without WebGL.
- A background video is muted, `playsInline`, has a `poster`, is short and compressed, and has no
  sound track at all. A video that carries information has captions and controls.
- Pause the scene when it is off screen or the tab is hidden; stop the render loop, do not just
  hide the canvas.

## Measure it

Run Lighthouse CI (`lighthouserc.json`) with the scene on: LCP stays within 2.5 s and Total Blocking
Time within 200 ms in the lab. `bundle-budget.mjs` counts only first-load JavaScript, so a lazily
loaded scene does not count against it, which is the point; the lab run is what shows whether it
still slows the page.

3D work has its own optional plugin, agent-fe-threejs, for the scene itself.
