---
paths:
  - '**/app/**/page.tsx'
  - '**/components/**/*.tsx'
  - '**/*.css'
---

# Design quality for a marketing site

A company site that looks like a template tells the visitor the company is one too. These rules are
judgement, not checks: review applies them, and `SSOT.md` holds the decisions they refer to.

## Decide before you build

- A visual direction written down in `SSOT.md` (palette, type pairing, spacing scale, radius,
  motion), with a reason tied to the brand. "Clean and minimal" is not a direction.
- Tokens, not literals: colours, spacing and type sizes come from the theme, so a change is one
  edit and dark mode (if the site has one) is designed, not inverted.

## Hierarchy and rhythm

- One clear first read per section: scale, weight and space say what matters most. Uniform cards
  with uniform padding say nothing is.
- Spacing follows the scale and varies with meaning: related items sit closer than unrelated
  ones.
- One primary call to action per view, visibly different from secondary actions.

## Things that make a site look generated

- A centred headline over a gradient blob with a generic button, as the whole hero.
- Library defaults shipped as the design: the default card, the default shadow, the default radius
  on everything.
- Stock icons standing in for content; placeholder copy ("Lorem ipsum", "Your tagline here") in a
  build that is meant to ship.
- Motion that decorates instead of guiding, or that ignores `prefers-reduced-motion`.

## States and details

- Hover, focus-visible and active states are designed for every interactive element; focus is
  never removed without a visible replacement.
- Copy is real, specific and consistent in tone; buttons say what happens ("Book a call"), not
  "Submit".
- Both themes (when there are two) are checked by eye, and contrast meets 4.5:1 for body text and
  3:1 for large text and UI parts in each.

## A design skill, if you use one

A design skill installed separately (by reference, never copied into this repo) can review a page
against these rules. Its product and design notes belong in `SSOT.md` or files it names, not in
this rule.
