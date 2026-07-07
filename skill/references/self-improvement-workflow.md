# Self-improvement workflow

Use this only after lint finds a repeated structural problem.

## Classify

- One-off problem: fix the vault page or report it in `wiki/log.md`.
- Repeated structural problem: create a skill improvement draft.

Repeated problems include the same reference drift, stale command distribution, unfilled placeholders, broken internal links, or missing cleanup gates appearing more than once.

## Draft output

Write a draft to `wiki/outputs/skill-improvement-YYYYMMDD.md` with:

1. Problem pattern.
2. Evidence from lint results.
3. Proposed change to `SKILL.md`, `references/`, commands, or setup scripts.
4. Risk and validation command.

Do not create GitHub issues or PRs automatically. Ask for explicit approval or wait for a direct command.

## When to use skill-improve

Use `skill-improve` when the draft changes how the skill itself should behave, not when it only fixes one vault page.
