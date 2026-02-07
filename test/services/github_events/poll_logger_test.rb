require "test_helper"

class GithubEvents::PollLoggerTest < ActiveSupport::TestCase
  def capture_log
    output = StringIO.new
    old_logger = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(output)
    yield
    Rails.logger = old_logger
    output.string
  end

  test "successful poll with enrichment" do
    stats = GithubEvents::PollStats.new
    stats.record_fetch(
      status: 200,
      headers: { "x-ratelimit-limit" => "60", "x-ratelimit-remaining" => "59", "x-poll-interval" => "60" }
    )
    stats.record_events(received: 100, processed: 64)
    stats.record_enrichment(
      actor_stats: { unique_ids: 12, attempted: 5, fetched: 5, not_modified: 0, decode_error: 0, mismatched: 0, failed: 0 },
      repo_stats:  { unique_ids: 8, attempted: 3, fetched: 2, not_modified: 1, decode_error: 0, mismatched: 0, failed: 0 },
      api_calls_made: 8
    )
    stats.record_schedule(outcome: "ok", interval: 60, server_interval: 60)

    output = capture_log { GithubEvents::PollLogger.log(stats) }

    assert_includes output, "GitHub events poll ok"
    assert_includes output, "Rate limit: 60/hour, threshold=5"
    assert_includes output, "Events:     100 received, 64 push events, 36 skipped"
    assert_includes output, "Actors:     12 unique, 5 fetched (5 ok)"
    assert_includes output, "Repos:      8 unique, 3 fetched (2 ok, 1 not_modified)"
    assert_includes output, "API avail:  60"
    assert_includes output, "API used:   9 (events=1, actors=5, repos=3)"
    assert_includes output, "API left:   51"
    assert_includes output, "Next poll:  in 1 minute"
  end

  test "successful poll near rate limit — extended wait" do
    stats = GithubEvents::PollStats.new
    stats.record_fetch(
      status: 200,
      headers: { "x-ratelimit-limit" => "60", "x-ratelimit-remaining" => "8", "x-poll-interval" => "60" }
    )
    stats.record_events(received: 100, processed: 64)
    stats.record_enrichment(
      actor_stats: { unique_ids: 5, attempted: 2, fetched: 2, not_modified: 0, decode_error: 0, mismatched: 0, failed: 0 },
      repo_stats:  { unique_ids: 3, attempted: 1, fetched: 1, not_modified: 0, decode_error: 0, mismatched: 0, failed: 0 },
      api_calls_made: 3
    )
    stats.record_schedule(outcome: "ok", interval: 3101, server_interval: 60, rate_limited: true, reset_in: 3096)

    output = capture_log { GithubEvents::PollLogger.log(stats) }

    assert_includes output, "GitHub events poll ok"
    assert_includes output, "Rate limit: 60/hour, threshold=5"
    assert_includes output, "API avail:  9"
    assert_includes output, "API used:   4 (events=1, actors=2, repos=1)"
    assert_includes output, "API left:   5"
    assert_includes output, "Next poll:  in 51 minutes and 41 seconds (waiting for rate limit"
  end

  test "304 not modified" do
    stats = GithubEvents::PollStats.new
    stats.record_fetch(
      status: 304,
      headers: { "x-ratelimit-limit" => "60", "x-ratelimit-remaining" => "45", "x-poll-interval" => "60" }
    )
    stats.record_schedule(outcome: "not_modified", interval: 60, server_interval: 60)

    output = capture_log { GithubEvents::PollLogger.log(stats) }

    assert_includes output, "GitHub events poll not_modified"
    assert_includes output, "Rate limit: 60/hour, threshold=5"
    assert_includes output, "API avail:  46"
    assert_includes output, "API used:   1 (events=1)"
    assert_includes output, "API left:   45"
    assert_includes output, "Next poll:  in 1 minute"
    refute_includes output, "Events:"
  end

  test "backoff from exception with partial enrichment" do
    stats = GithubEvents::PollStats.new
    stats.record_fetch(
      status: 200,
      headers: { "x-ratelimit-limit" => "60", "x-ratelimit-remaining" => "59" }
    )
    stats.record_events(received: 100, processed: 77)
    stats.record_enrichment(
      actor_stats: { unique_ids: 70, attempted: 54, fetched: 53, not_modified: 0, decode_error: 0, mismatched: 0, failed: 1 },
      api_calls_made: 54
    )
    stats.record_schedule(
      outcome: "backoff", interval: 30, reason: "exception",
      error_message: "ActiveRecord::StatementInvalid: PG::UndefinedColumn: ERROR: column \"foo\" does not exist"
    )

    output = capture_log { GithubEvents::PollLogger.log(stats) }

    assert_includes output, "GitHub events poll backoff: ActiveRecord::StatementInvalid"
    assert_includes output, "Events:     100 received, 77 push events, 23 skipped"
    assert_includes output, "Actors:     70 unique, 54 fetched (53 ok, 1 failed)"
    refute_includes output, "Repos:"
    assert_includes output, "API avail:  60"
    assert_includes output, "API used:   55 (events=1, actors=54)"
    assert_includes output, "API left:   5"
    assert_includes output, "Next poll:  in 30 seconds (backoff)"
  end

  test "backoff from timeout — no headers" do
    stats = GithubEvents::PollStats.new
    stats.record_schedule(
      outcome: "backoff", interval: 30, reason: "timeout",
      error_message: "Faraday::TimeoutError: execution expired"
    )

    output = capture_log { GithubEvents::PollLogger.log(stats) }

    assert_includes output, "GitHub events poll backoff: Faraday::TimeoutError: execution expired"
    refute_includes output, "Events:"
    refute_includes output, "Rate limit:"
    refute_includes output, "API avail:"
    refute_includes output, "API used:"
    refute_includes output, "API left:"
    assert_includes output, "Next poll:  in 30 seconds (backoff)"
  end

  test "429 rate limited" do
    stats = GithubEvents::PollStats.new
    stats.record_fetch(
      status: 429,
      headers: { "x-ratelimit-limit" => "60", "x-ratelimit-remaining" => "0" }
    )
    stats.record_schedule(outcome: "rate_limited", interval: 125, rate_limited: true, reset_in: 120)

    output = capture_log { GithubEvents::PollLogger.log(stats) }

    assert_includes output, "GitHub events poll rate_limited: status=429"
    assert_includes output, "Rate limit: 60/hour, threshold=5"
    assert_includes output, "API avail:  1"
    assert_includes output, "API used:   1 (events=1)"
    assert_includes output, "API left:   0"
    assert_includes output, "Next poll:  in 2 minutes and 5 seconds (waiting for rate limit, resets in 2 minutes)"
  end

  test "500 server error backoff with headers" do
    stats = GithubEvents::PollStats.new
    stats.record_fetch(
      status: 500,
      headers: { "x-ratelimit-limit" => "60", "x-ratelimit-remaining" => "55" }
    )
    stats.record_schedule(outcome: "backoff", interval: 30, reason: "server_error_500")

    output = capture_log { GithubEvents::PollLogger.log(stats) }

    assert_includes output, "GitHub events poll backoff: server_error_500, status=500"
    assert_includes output, "Rate limit: 60/hour, threshold=5"
    assert_includes output, "API avail:  56"
    assert_includes output, "API used:   1 (events=1)"
    assert_includes output, "API left:   55"
    assert_includes output, "Next poll:  in 30 seconds (backoff)"
  end

  test "successful poll with mixed enrichment failures" do
    stats = GithubEvents::PollStats.new
    stats.record_fetch(
      status: 200,
      headers: { "x-ratelimit-limit" => "60", "x-ratelimit-remaining" => "59" }
    )
    stats.record_events(received: 80, processed: 50)
    stats.record_enrichment(
      actor_stats: { unique_ids: 30, attempted: 20, fetched: 15, not_modified: 2, decode_error: 1, mismatched: 1, failed: 1 },
      repo_stats:  { unique_ids: 25, attempted: 15, fetched: 12, not_modified: 1, decode_error: 0, mismatched: 0, failed: 2 },
      api_calls_made: 35
    )
    stats.record_schedule(outcome: "ok", interval: 60)

    output = capture_log { GithubEvents::PollLogger.log(stats) }

    assert_includes output, "Events:     80 received, 50 push events, 30 skipped"
    assert_includes output, "Actors:     30 unique, 20 fetched (15 ok, 2 not_modified, 1 decode_error, 1 mismatched, 1 failed)"
    assert_includes output, "Repos:      25 unique, 15 fetched (12 ok, 1 not_modified, 2 failed)"
    assert_includes output, "API avail:  60"
    assert_includes output, "API used:   36 (events=1, actors=20, repos=15)"
    assert_includes output, "API left:   24"
  end

  test "all events are push events — no skipped" do
    stats = GithubEvents::PollStats.new
    stats.record_fetch(
      status: 200,
      headers: { "x-ratelimit-limit" => "60", "x-ratelimit-remaining" => "59" }
    )
    stats.record_events(received: 10, processed: 10)
    stats.record_schedule(outcome: "ok", interval: 60)

    output = capture_log { GithubEvents::PollLogger.log(stats) }

    assert_includes output, "Events:     10 received, 10 push events"
    refute_includes output, "skipped"
  end

  test "server requested longer interval" do
    stats = GithubEvents::PollStats.new
    stats.record_fetch(
      status: 200,
      headers: { "x-ratelimit-limit" => "60", "x-ratelimit-remaining" => "50", "x-poll-interval" => "90" }
    )
    stats.record_events(received: 100, processed: 10)
    stats.record_schedule(outcome: "ok", interval: 90, server_interval: 90)

    output = capture_log { GithubEvents::PollLogger.log(stats) }

    assert_includes output, "Next poll:  in 1 minute and 30 seconds (server requested 90s)"
  end
end
