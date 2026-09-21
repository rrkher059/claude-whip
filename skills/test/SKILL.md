---
name: test
description: Write the one regression test that would have caught the bug we just fixed, matching existing conventions, then run it.
disable-model-invocation: true
allowed-tools: Bash(git *) Bash(npm *) Bash(pytest *)
---

Write the regression test that would have caught the bug we just fixed.

**Read a neighboring test first.** Before writing anything, open an existing test file near the code that changed. Match its framework, its file naming, its directory, its import style, its assertion style, its setup and teardown pattern, and its naming convention for test cases. Do not introduce a new testing library, a new helper, or a new fixture pattern. If this repo writes plain asserts, write a plain assert.

**The test must actually be a regression test.** It has to fail against the old behavior and pass against the new one. If you cannot articulate why it would have failed before the fix, you have written a test that documents the implementation rather than catching the bug — throw it away and write a different one.

**Cover the actual edge case.** The specific input, state, or timing that triggered the bug. Not the happy path — the happy path was already working, that is why the bug shipped. If the bug was an empty array, test the empty array. If it was a null in the third field, test a null in the third field. If it was two requests arriving together, test that.

**One test.** Not a suite, not a table of twelve cases, not a describe block full of variations. One test, unless the bug genuinely had distinct cases that fail for different reasons — in which case one test per distinct cause and no more.

**Then run it** and show me the actual output. If it passes, say so plainly. If it fails, show the failure and tell me whether the test is wrong or the fix is incomplete — do not silently adjust the test until it goes green.
