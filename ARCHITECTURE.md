# Architecture

## Problem

GitHub's public events API exposes a real-time stream of activity, but it is
rate-limited, returns overlapping windows of data, and provides only shallow
event payloads. The goal is to poll this API reliably, enrich events with full
actor and repository details, and persist everything to Postgres — without
exceeding rate limits, creating duplicates, or losing data on restarts.

## Data Flow

```
PollGithubEventsJob (Sidekiq, single worker)
  → Poller
    → EventsFetch (GET /events with ETag)
    → EventsProcessor (filter to PushEvents, build rows)
    → Enricher (fetch actor/repo details, assign FKs)
    → GithubEvent.upsert_all (persist)
  → NextJobScheduler (decide when to poll next via perform_in)
```

Sidekiq with `-c 1` instead of Solid Queue because the poll interval is dynamic
(60s normally, minutes after rate limit, hours if budget exhausted). Each poll
decides when the next one runs. One worker prevents competing for the same budget.

## Extension A: Rate Limiting & Fan-Out Control

**The problem:** one poll returns up to 100 events. Enriching every unique actor
and repo could fan out into many follow-up API calls, burning the rate limit budget.

**How we control it:**

1. **Budget cap per batch.** `pick_fetchable` limits fetches to the rate limit
   budget, or `MAX_FETCH_PER_BATCH` (50) if no header is present. Already-known
   actors/repos are skipped — no API call.
2. **Shared budget across enrichers.** `Enricher` starts with
   `x-ratelimit-remaining - 5` (safety threshold). Passes it to `ActorEnricher`,
   subtracts calls made, passes remainder to `RepoEnricher`. Budget hits zero →
   next enricher is skipped. Plain integer, no shared mutable state.
3. **Scheduler awareness.** `NextJobScheduler` subtracts `api_calls_made` from
   the header to get *true* remaining. If at or below threshold, the next poll
   waits until after the rate limit window resets.

**Bot actors:** Actors with logins ending in `[bot]` (e.g. `github-actions[bot]`)
are skipped during enrichment. The Users API returns 404 for these accounts, so
fetching them wastes budget. Events from bots are still saved with `actor_id: nil`.

**Behavior when rate-limited:**

- **429 response** → next poll delayed to `reset_in + 5` seconds. No events processed.
- **Low remaining budget** → enrichment partially/fully skipped. Events still
  saved without actor/repo FKs; filled in on later polls.
- **Budget exhausted mid-enrichment** → current enricher stops, next is skipped.

**Background processing:** all polling runs in Sidekiq. The web process is never
blocked. At most one pending poll job exists at any time — no queue buildup.

## Extension B: Idempotency & Restart Safety

**Duplicate events:** the events API returns overlapping windows across polls.
All writes use database-level unique indexes:

- **Events:** `upsert_all` by `event_id` — same event twice → update, not duplicate.
- **Actors/Repos:** upserted by `github_id` unique index.

Polling the same page twice or restarting mid-cycle never creates duplicates.

**Restart safety:** poll state (ETag, interval, backoff) lives in Redis cache.

- Redis available → resumes with stored ETag (gets 304 if nothing changed).
- Redis lost → state resets to defaults. Re-fetches the page, but `upsert_all`
  prevents duplicates. Cost: one extra API call.
- On startup we clear the `polling` Sidekiq queue and scheduled `polling` jobs (see `bin/jobs`) and enqueue exactly one `PollGithubEventsJob`.

No in-memory state exists. The Sidekiq job is the only entry point.

**Preventing unbounded growth:**

- One page per poll (max 100 events). Enrichment capped at 50 fetches.
- `pick_fetchable` only fetches missing or stale (>24h) records.

**Tradeoffs:**

- **Eventual consistency.** Events may be saved before their actor/repo exists.
  FK columns are nullable; filled in on later polls. We chose this because
  dropping events to wait for enrichment would mean data loss.
- **Cache loss is cheap, not free.** Losing Redis re-fetches one page and
  re-processes already-saved events. Upserts make it safe but not zero-cost.
- **Single-threaded.** Sacrifices throughput for simplicity — no race conditions,
  no distributed locks, no duplicate enrichment calls.

## Extension D: Testing Strategy

**Unit tests** (30 tests across `EnricherTest`, `EventsProcessorTest`,
`EventsFetchTest`, `NextJobSchedulerTest`) cover edge cases exhaustively —
API failures, timeouts, decode errors, budget exhaustion, 304 handling,
deduplication, malformed input, backoff math. Each service is isolated with
WebMock stubs, so these tests are fast and cheap. Pushing edge-case coverage
into unit tests means we need fewer expensive integration tests.

**Integration tests** (`PollerTest`, 6 tests) run the full cycle with real DB
writes: 200 with FK assertions, 304, ETag passthrough, timeout/500/429. Only
HTTP is stubbed. These prove the components wire together — if the Poller test
passes with real DB writes and FK links, the system works end-to-end.

**Test Clarity** Spent time on making sure the tests were clear, with factories, and by creating data as simply as possible but only what was needed for that test. This is an art in itself, and I could have done even more, but got about 85% there.

## What We Intentionally Did Not Build

- **Enrichment priority queue.** When budget is limited, `pick_fetchable` treats
  never-fetched and stale records equally. It does not prioritize actors/repos
  with no data over ones that are simply due for a refresh. A priority system
  would improve first-fetch coverage under tight budgets but adds complexity
  we didn't need for the current scale.
  
- **Unauthenticated rate budget.** Without an API token, GitHub allows **60 requests/hour**.
  The events API offers up to 3 pages of 100, but fetching all three pages plus enrichment is
  impossible within that budget. We fetch **one page per poll** and spend the remaining budget
  on enrichment. This keeps the system simple and makes the most of a tight constraint.

  - **Ideal future**: use webhooks (events pushed to our server) or add an API token to increase the rate limit.

## What I went overboard on 
- **Logging stats.** For showing what is going on clearly. See [`poll_logger_test.rb`](test/services/github_events/poll_logger_test.rb).

## Conclusions
 This proves that a simple idea to "get some data from api" becomes very complex when you have to factor in rate limits, robustness, resilience, and observability.
