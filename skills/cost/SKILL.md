---
name: cost
description: Find every paid model call in the repo and estimate the monthly bill at stated usage, naming the most expensive call path.
disable-model-invocation: true
background: false
---

Find what this repository costs to run per month, and say which line of code is responsible for most of it.

**1. Find every paid call.** Search the codebase for calls that bill someone: model and inference APIs, embeddings, vector search, transcription, image generation, OCR, third-party enrichment, SMS and email providers, and anything reached through a billing SDK. Do not stop at the obvious one — the expensive call is usually the one nobody thinks about, in a retry path, a cron job, a webhook handler, or a loop.

For each, record: file and line, which model or endpoint, and what triggers it.

**2. Get the per-call cost right.** For each call, work out the price per invocation from the model and the token counts the code actually sends. Read the prompt construction — if the system prompt is 2,000 tokens and it is sent on every request with no caching, say so, because that is usually the whole bill. Flag any call where the input is unbounded (a whole file, a whole page of results, an entire conversation history with no truncation), because that is a cost with no ceiling.

If you do not know a current price, say which price you need rather than guessing a number. A wrong price stated confidently is worse than a gap.

**3. Estimate the monthly total.** State your usage assumptions explicitly, each on its own line — requests per user per day, active users, average tokens in and out, retry rate. Then give the monthly figure. Put the assumptions above the number so I can correct the one you got wrong instead of discarding the whole estimate.

Break the total down by call path, most expensive first.

**4. Name the most expensive path.** One specific call, by file and function. Say what fraction of the bill it is, why it costs that much, and the single change that would most reduce it — prompt caching, a smaller model for that step, truncating the input, batching, memoising, or not making the call at all. Estimate the saving.

**5. Flag anything that scales badly.** Costs that grow with users but bill per call, costs inside loops, costs in retry paths without a cap, and anything that would let a single user run up an unbounded bill. These are the ones that turn into an incident rather than a line item.

If the repository makes no paid calls at all, say so and stop. Do not invent a cost model to have something to report.
