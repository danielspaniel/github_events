module GithubEvents
  class NextJobScheduler
    DEFAULT_POLL_INTERVAL = 60
    MAX_BACKOFF = 900
    INITIAL_BACKOFF = 30
    STATE_CACHE_KEY = "github_events:poll_state:public_events".freeze

    Result = Struct.new(:state, :next_interval_seconds)

    def load_state
      raw = Rails.cache.read(STATE_CACHE_KEY)
      data = raw.is_a?(Hash) ? raw : {}
      data.transform_keys(&:to_s)
    end

    def apply_success(state, stats, now: Time.current)
      headers = stats.headers
      server_interval = headers["x-poll-interval"].to_i
      interval = server_interval.positive? ? [ server_interval, DEFAULT_POLL_INTERVAL ].max : DEFAULT_POLL_INTERVAL
      remaining = stats.rate_limit_remaining
      reset_in = rate_limit_reset_in(headers, now)

      rate_limited = false
      if remaining <= RateLimit::THRESHOLD && reset_in.to_i.positive?
        interval = [ interval, reset_in + 5 ].max
        rate_limited = true
      end

      updated = state.merge(
        "etag" => headers["etag"].presence || state["etag"],
        "poll_interval_seconds" => interval,
        "last_polled_at" => now.iso8601,
        "last_success_at" => now.iso8601,
        "last_status" => stats.status,
        "last_error" => stats.decode_error ? "invalid_json" : nil
      )

      stats.record_schedule(
        outcome: stats.status == 304 ? "not_modified" : "ok",
        interval:, server_interval:, rate_limited:, reset_in:
      )
      PollLogger.log(stats)

      write_state(updated, interval)
    end

    def apply_rate_limit(state, stats, now: Time.current)
      headers = stats.headers
      reset_in = rate_limit_reset_in(headers, now)
      interval = reset_in.to_i.positive? ? reset_in + 5 : DEFAULT_POLL_INTERVAL

      updated = state.merge(
        "etag" => headers["etag"].presence || state["etag"],
        "poll_interval_seconds" => interval,
        "last_polled_at" => now.iso8601,
        "last_status" => 429,
        "last_error" => "rate_limited: reset_in=#{reset_in.to_i}s"
      )

      stats.record_schedule(outcome: "rate_limited", interval:, rate_limited: true, reset_in:)
      PollLogger.log(stats)

      write_state(updated, interval)
    end

    def apply_backoff(state, stats, reason:, exception: nil, now: Time.current)
      headers = stats.headers
      interval = next_backoff_seconds(state)

      updated = state.merge(
        "poll_interval_seconds" => interval,
        "last_polled_at" => now.iso8601,
        "last_error" => [ reason, exception&.class, exception&.message ].compact.join(": ")
      )
      updated["last_status"] = stats.status if stats.status
      updated["etag"] = headers["etag"].presence || state["etag"] if headers.present?

      error_message = [ exception&.class, exception&.message ].compact.join(": ").presence
      stats.record_schedule(outcome: "backoff", interval:, reason:, error_message:)
      PollLogger.log(stats)

      write_state(updated, interval)
    end

    def apply_unexpected(state, stats, error:, now: Time.current)
      headers = stats.headers
      interval = effective_poll_interval(state)

      updated = state.merge(
        "etag" => headers["etag"].presence || state["etag"],
        "poll_interval_seconds" => interval,
        "last_polled_at" => now.iso8601,
        "last_status" => stats.status,
        "last_error" => error
      )

      stats.record_schedule(outcome: "unexpected", interval:)
      PollLogger.log(stats)

      write_state(updated, interval)
    end

    private

    def write_state(state, interval)
      Rails.cache.write(STATE_CACHE_KEY, state)
      Result.new(state, interval)
    end

    def effective_poll_interval(state)
      interval = state["poll_interval_seconds"].to_i
      interval.positive? ? interval : DEFAULT_POLL_INTERVAL
    end

    def next_backoff_seconds(state)
      if in_backoff?(state)
        prev = effective_poll_interval(state)
        [ (prev <= 0 ? INITIAL_BACKOFF : prev) * 2, MAX_BACKOFF ].min
      else
        INITIAL_BACKOFF
      end
    end

    def in_backoff?(state)
      return true if state["last_status"].to_i.between?(500, 599)
      return true if state["last_error"].to_s.include?("timeout")

      false
    end

    def rate_limit_reset_in(headers, now = Time.current)
      reset_at = headers["x-ratelimit-reset"].to_i
      return if reset_at <= 0
      [ reset_at - now.to_i, 0 ].max
    end
  end
end
