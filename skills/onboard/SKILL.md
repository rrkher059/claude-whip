---
name: onboard
description: Generate CONTRIBUTING.md from what the repo actually does, with setup commands verified against the code rather than boilerplate.
disable-model-invocation: true
background: false
allowed-tools: Bash(git *)
---

Write `CONTRIBUTING.md` at the repository root, generated from what this repository actually is. Overwrite it if it exists.

**Every command in it must be verified against the code, not assumed.** Read `package.json` scripts, the Makefile, `pyproject.toml`, `docker-compose.yml`, CI workflow files, and the lockfiles. If the repo has a `pnpm-lock.yaml`, the command is `pnpm install`, not `npm install`. If the test script is `vitest run`, say that, not `npm test`, unless `npm test` genuinely maps to it. If CI runs something the README does not mention, CI is the source of truth — it is the thing that actually has to pass.

Do not write a single line of generic open-source boilerplate. No "we welcome contributions of all kinds", no code of conduct boilerplate, no PR etiquette lecture. If you find yourself writing a sentence that would be true of any repository, delete it.

Include, in this order:

**What this is** — one sentence, what the project does for whoever uses it.

**Setup** — the exact commands to go from a fresh clone to a running thing, in order. Include the prerequisites with versions where the repo pins them (engines field, `.nvmrc`, `python_requires`, a toolchain file). Include environment variables that must be set before anything works — read `.env.example` if present, and if it is absent but the code reads env vars, list the ones it reads and say the example file is missing.

**Verify it worked** — the one command that proves the setup is correct, and what a good result looks like. This is the step most contributing guides omit and the one that saves the most time.

**Tests and lint** — the real commands, and which of them CI enforces.

**The layout that matters** — the four or five directories a contributor will actually touch and what lives in each. Not a full tree.

**Conventions this repo actually follows** — inferred from the code and recent commits, not aspirational. Commit message style if there is a consistent one, branch naming if there is one, whether tests live beside the source or in a separate tree, how errors are handled. If there is no consistent convention, say so rather than inventing one.

**Traps** — what will waste a new contributor an hour. The service that must be running. The migration that must be applied. The generated file that must not be edited by hand. The test that fails on a clean checkout for a known reason.

If a command cannot be verified from the repo, mark it clearly as unverified rather than presenting a guess as fact. At the end of your reply, list anything you could not verify, so I can fill it in.
