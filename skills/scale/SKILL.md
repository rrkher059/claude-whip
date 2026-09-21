---
name: scale
description: What breaks and what it costs at 100x current traffic, specific to the code in front of us — named files, estimated dollars, one highest-leverage fix.
disable-model-invocation: true
background: false
---

Take the code we are working on right now and run it at 100x current traffic. Everything below must be specific to this code. Generic scaling advice is worthless to me — I can read a blog post. Name files, functions, queries, and endpoints.

**1. First thing to break**

Which specific query, endpoint, loop, or lock gives out first, and at roughly what load. Name the file and the line. Then the second and third thing, briefly. Include the boring ones people forget: connection pool exhaustion, a single-threaded worker, an unindexed column that is fine at 10k rows and fatal at 1M, an in-memory cache that is per-process, a cron job whose runtime grows linearly with table size until it overlaps itself.

**2. Cost**

What runs per request that bills someone money: model and inference calls, egress, third-party API calls, per-row reads and writes, storage growth, log ingestion.

Give me an estimated cost per 1,000 users per month. State every assumption explicitly on its own line — requests per user per month, tokens per call, bytes per response — so I can correct the ones you got wrong. A wrong number with a visible assumption is useful; a confident number with hidden assumptions is not.

Flag anything that scales with users but bills per call. That is where the surprise invoice comes from.

**3. Cheapest fix that buys the most headroom**

One change. Not a roadmap. What it is, roughly how much runway it buys (10x? 3x?), and roughly how long it takes to do.

If you need a number you do not have — current RPS, row counts, average payload size, the actual traffic today — say which number you need and why it changes the answer. Do not invent it and do not quietly assume one.
