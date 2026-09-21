---
name: secure
description: Full-repo security sweep ordered by what gets exploited first — findings with file, line, severity, exploit, and fix.
disable-model-invocation: true
background: false
---

Security sweep of the entire repository. Not just the current diff — read the whole codebase, including config, CI workflows, infrastructure files, and anything in `.env*`.

Check for all of the following:

- **Secrets in the repo** — API keys, tokens, private keys, passwords, connection strings committed to git or sitting in a `.env` file that is not gitignored. Check git history, not just the working tree. A rotated key still in history is still a finding.
- **Missing authentication** — endpoints, routes, handlers, or functions that reach data without establishing who the caller is.
- **Missing authorization** — authenticated but not checked against ownership. Can user A pass user B's ID and get user B's data? Look specifically for IDs taken from the request and used in a query without a scoping clause.
- **Client-side-only authorization** — a check in the frontend with no matching check on the server. The UI hiding a button is not a permission.
- **Injection** — SQL built by string concatenation or f-string, shell commands built from input, template injection, NoSQL query objects taken from user input.
- **Unescaped output** — user input rendered into HTML, `dangerouslySetInnerHTML`, `innerHTML`, unescaped template output.
- **Dependencies with known advisories** — flag outdated or known-vulnerable packages you recognize in the lockfile.
- **CORS wildcards** — a `*` origin, especially combined with credentials.
- **Missing rate limiting** — on login, signup, password reset, token endpoints, and anything expensive (model calls, exports, search).
- **PII in logs** — emails, tokens, full request bodies, auth headers written to stdout or a logging service.

For each finding give exactly: file, line, severity (critical / high / medium / low), the exploit in one sentence, and the fix.

Order the list by what gets exploited first in the real world — internet-reachable and unauthenticated beats theoretical and local, always. Do not order by severity label.

If you find nothing, say you found nothing. Do not manufacture findings to look thorough. An honest empty report is a useful report.
