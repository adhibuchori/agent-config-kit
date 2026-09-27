### 3D scenes (agent-fe-threejs)

- Scene code follows `.claude/rules/web/3d.md`. `node scripts/check/3d-budget.mjs` holds models,
  textures and environment maps to `scripts/check/3d-budget.json`; a file that needs more gets an
  exception with its reason, never a budget raised for every file.
- Third-party 3D skills are installed by reference (`docs/3d-skills.md`), never copied in.
