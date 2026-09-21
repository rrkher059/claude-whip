---
name: ship
description: Run tests and lint, then commit and push only if everything passes. Stops dead on failure without fixing anything.
disable-model-invocation: true
allowed-tools: Bash(git *) Bash(npm *) Bash(pnpm *) Bash(yarn *) Bash(pytest *)
---

Ship the current work. Follow this exactly, in order.

**1. Detect the commands.** Look at package.json scripts, Makefile targets, or pyproject.toml for the test and lint commands this repo actually uses. Use the package manager the repo uses — a pnpm-lock.yaml means pnpm, a yarn.lock means yarn. Do not guess a command that is not defined somewhere.

**2. Run the tests.**

If any test fails: STOP. Show me the failing output. Do not fix the failures. Do not commit. Do not push. Do not offer to fix them unless I ask. The run ends here.

**3. Run lint.** Same rule. Any failure means STOP, show the output, no commit.

**4. Commit and push.** Only if steps 2 and 3 were clean:

```
git add -A
git commit -m "<message>"
git push
```

Push to the current branch. Do not switch branches, do not create a branch, do not open a PR.

The commit message is one line, imperative mood, describing what changed. "Add retry backoff to webhook sender." Not "refactor and improve." Not "update code." No emoji. No Co-Authored-By trailer. No body.

**5. Reply.** Your entire response is the commit hash and the message. Nothing else — no summary, no "successfully pushed."

If there is nothing staged and nothing to commit, say there is nothing to commit and stop.
