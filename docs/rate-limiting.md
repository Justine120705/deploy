# Rate limiting (SEC-04, issue #91)

## Decision

A Vercel Firewall rule, not a shared store (Upstash). Reasons: the Hobby plan allows a custom rate-limit
rule, it needs no code, no new account and no secret, and the limit is enforced before the request reaches
the app. Recorded 2026-10-12.

## The rule (Vercel dashboard, project `sv-student-portal`, Firewall, Rules)

| Field | Value |
| --- | --- |
| Name | Limit POST requests per IP |
| If | Method equals `POST` |
| Rate limit | Fixed window, 60 seconds, 20 requests, key: IP address |
| Then | Too Many Requests (429) |

Why one rule on all POST requests: the sign-in form and every write action in the app (clearance, approvals,
payments, grades, documents, enrollment) are POST requests, so one rule covers them. Page views (GET) are not
limited.

## Setup steps (the Project Manager can repeat them)

1. Vercel dashboard, open the project, left menu **Firewall**.
2. **Add New**, then **Rule**.
3. Name it `Limit POST requests per IP`. Set **If**: Request Method, Equals, `POST`.
4. In **Then**, choose **Rate Limit**. Set Fixed Window, 60 seconds, 20 requests, key IP Address, and the
   action Too Many Requests (429).
5. Save the rule, then use **Review changes** and **Publish**. Changes apply without a redeploy.
6. Check that **Custom Rules** shows 1 active on the Firewall overview.

To change the limit later, edit the rule on the same page. To switch it off, use the rule's toggle.

## Test (2026-10-12, run by Claude with curl from the Project Manager's computer; the Project Manager created the rule)

Target: `https://sv-student-portal-beta.vercel.app/login`, bare POST requests with no credentials.

| Run (UTC) | Requests | Result |
| --- | --- | --- |
| 11:16:11 | 25 in 9 s | All 405 (the app's answer to a bare POST). No 429: the rule was not enforcing yet |
| 11:18:15 | 25 in 8 s | All 405. Same: the rule had only just been published |
| 11:18:34 to 11:18:54 | 60 in 20 s | First 24 returned 405, from request 25 on the answers were 429 mixed with some 405. Then 3 more after 5 s: 405, 429, 405 |
| 11:18:54 | 1 GET `/login` | 200: page views are not limited |

Reading: the limit works. The first requests of a window pass, then HTTP 429 is returned. The count is
approximate (a few requests over 20 got through and 429 and 405 alternate near the limit), which is expected
because Vercel counts across its edge servers. The first two runs found nothing because the rule was not yet
enforcing; they are kept here on purpose.

## Limits of this control (stay honest)

- It protects only requests to the Vercel app. Someone who calls the Supabase Auth endpoint directly bypasses
  it (see the residual risks of the login lockout in `docs/database/login_lockout.sql`).
- The limit is per IP. People behind one shared IP (for example a classroom network) share the same count.
- 20 POST requests per minute is not a separate, stricter limit for sign-in. If more rules are allowed, add
  one for path `/login`, 10 per minute.
- The server actions of the app were not tested one by one; only the sign-in route was flooded.
- The test was run once; it was not repeated from a second IP.
