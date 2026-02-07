require "test_helper"

class GithubEvents::NextJobSchedulerTest < ActiveSupport::TestCase
  def scheduler
    GithubEvents::NextJobScheduler.new
  end

  def build_stats(status:, headers: {}, decode_error: false, api_calls_made: 0)
    stats = GithubEvents::PollStats.new
    stats.record_fetch(status:, headers:, decode_error:)
    stats.record_enrichment(api_calls_made:) if api_calls_made > 0
    stats
  end

  def setup
    Rails.cache.clear
  end

  test "apply_success respects server interval floor" do
    stats = build_stats(status: 200, headers: { "x-poll-interval" => "90" })

    result = scheduler.apply_success({}, stats)

    assert_equal 90, result.next_interval_seconds
    assert_equal 90, result.state["poll_interval_seconds"]
  end

  test "apply_success extends interval when rate limit reset is near" do
    reset_at = Time.current.to_i + 300
    stats = build_stats(
      status: 200,
      headers: {
        "x-ratelimit-remaining" => "5",
        "x-ratelimit-reset" => reset_at.to_s
      }
    )

    result = scheduler.apply_success({}, stats)

    assert_includes 300..306, result.next_interval_seconds
  end

  test "apply_success accounts for enrichment api_calls_made in rate limit check" do
    reset_at = Time.current.to_i + 300

    # Header says 15 remaining, but enrichment used 10 → effective remaining = 5
    stats = build_stats(
      status: 200,
      headers: {
        "x-ratelimit-remaining" => "15",
        "x-ratelimit-reset" => reset_at.to_s
      },
      api_calls_made: 10
    )

    result = scheduler.apply_success({}, stats)

    # 5 effective remaining <= threshold of 5 → should extend interval to reset_in + 5
    assert_includes 300..306, result.next_interval_seconds
  end

  test "apply_success does not extend interval when remaining is sufficient after api_calls_made" do
    reset_at = Time.current.to_i + 300

    # Header says 15 remaining, enrichment used 2 → effective remaining = 13
    stats = build_stats(
      status: 200,
      headers: {
        "x-ratelimit-remaining" => "15",
        "x-ratelimit-reset" => reset_at.to_s
      },
      api_calls_made: 2
    )

    result = scheduler.apply_success({}, stats)

    # 13 effective remaining > threshold of 5 → normal interval
    assert_equal 60, result.next_interval_seconds
  end

  test "apply_rate_limit uses x-ratelimit-reset when present" do
    reset_at = Time.current.to_i + 120
    stats = build_stats(status: 429, headers: { "x-ratelimit-reset" => reset_at.to_s })

    result = scheduler.apply_rate_limit({}, stats)

    assert_includes 120..126, result.next_interval_seconds
    assert_equal 429, result.state["last_status"]
    assert stats.rate_limited, "stats.rate_limited should be true after apply_rate_limit"
  end

  test "apply_rate_limit defaults to 60s when x-ratelimit-reset missing" do
    stats = build_stats(status: 429, headers: {})

    result = scheduler.apply_rate_limit({}, stats)

    assert_equal 60, result.next_interval_seconds
  end

  test "apply_backoff doubles on consecutive failures and caps" do
    stats = build_stats(status: 500, headers: {})

    first = scheduler.apply_backoff({}, stats, reason: "timeout")
    assert_equal 30, first.next_interval_seconds

    second = scheduler.apply_backoff(first.state, stats, reason: "timeout")
    assert_equal 60, second.next_interval_seconds

    capped_state = { "poll_interval_seconds" => 900, "last_status" => 500 }
    capped = scheduler.apply_backoff(capped_state, stats, reason: "server_error_500")
    assert_equal 900, capped.next_interval_seconds
  end
end
