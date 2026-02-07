# github_events

## Requirements

- Ruby `3.4.2` (see `.ruby-version`)
- PostgreSQL (or Docker)
- Redis

## Local development (Docker)

Start the system (runs app + polling services):

```bash
docker compose up --build
```

## One-off commands (Docker)

Run ingestion once (no self-scheduling):

```bash
docker compose run --rm ingest
```

Run tests:

```bash
docker compose run --rm test
```

Note: Continuous polling runs automatically with `docker compose up` (see above).

## How to verify it's working

**How long to wait**: The first poll runs immediately on boot. Expect new rows within seconds. Subsequent polls run every ~60s, but may be longer if GitHub requests a higher `X-Poll-Interval`, you’re near the rate limit, or the poller is backing off after errors.

**What logs to expect**:

```bash
# Follow the polling worker logs
docker compose logs -f polling
```

polling-1  | [ActiveJob] [PollGithubEventsJob] [0917d234-3abe-4a69-9d6d-8ecc978220bf] GitHub events poll ok: request_id=46E4:378E53:5B2A922:186383AC:6988F0AA
polling-1  |   Rate limit: 60/hour, threshold=5
polling-1  |   Events:     100 received, 73 push events, 27 skipped
polling-1  |   Actors:     53 unique, 44 fetched (44 ok)
polling-1  |   Repos:      73 unique, 10 fetched (10 ok)
polling-1  |   API avail:  60
polling-1  |   API used:   55 (events=1, actors=44, repos=10)
polling-1  |   API left:   5
polling-1  |   Next poll:  in 59 minutes and 47 seconds (waiting for rate limit, resets in 59 minutes and 42 seconds)

**What database tables to check**:

```bash
# Connect to Postgres in the db container
docker compose exec db psql -U postgres -d github_events_development

# Then run:
#   SELECT COUNT(*) FROM github_events;
#   SELECT * FROM github_events ORDER BY created_at DESC LIMIT 10;
```

**What cache key to check** (Redis):

```bash
docker compose exec redis redis-cli GET github_events:poll_state:public_events
```

This stores the poll state (ETag, last poll time, error tracking).

## Architecture

See [`ARCHITECTURE.md`](ARCHITECTURE.md).

## Job visibility

In development, Sidekiq Web UI is mounted at `http://localhost:3000/sidekiq` 


