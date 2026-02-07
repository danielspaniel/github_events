module GithubEvents
  class PollStats
    # --- Fetch phase ---
    attr_accessor :status, :headers, :decode_error

    # --- Processing phase ---
    attr_accessor :events_received, :events_count

    # --- Enrichment phase ---
    attr_accessor :api_calls_made, :actor_stats, :repo_stats

    # --- Scheduling phase (written by NextJobScheduler) ---
    attr_accessor :outcome, :interval, :server_interval, :rate_limited, :reset_in, :reason, :error_message

    def initialize
      @headers = {}
      @events_received = 0
      @events_count = 0
      @api_calls_made = 0
      @actor_stats = {}
      @repo_stats = {}
      @decode_error = false
      @rate_limited = false
      @server_interval = 0
    end

    def record_fetch(status:, headers:, decode_error: false)
      @status = status
      @headers = headers || {}
      @decode_error = decode_error
    end

    def record_events(received:, processed:)
      @events_received = received
      @events_count = processed
    end

    def record_enrichment(actor_stats: nil, repo_stats: nil, api_calls_made: 0)
      @actor_stats = actor_stats || {}
      @repo_stats = repo_stats || {}
      @api_calls_made = api_calls_made
    end

    def record_schedule(outcome:, interval:, server_interval: 0, rate_limited: false, reset_in: nil, reason: nil, error_message: nil)
      @outcome = outcome
      @interval = interval
      @server_interval = server_interval
      @rate_limited = rate_limited
      @reset_in = reset_in
      @reason = reason
      @error_message = error_message
    end

    # Total API calls allowed this window (from x-ratelimit-limit header).
    def rate_limit_limit
      headers["x-ratelimit-limit"].to_i
    end

    # What we had available before this poll cycle started.
    def rate_limit_before
      rate_limit_after_fetch + 1
    end

    # Remaining after the events fetch (before enrichment).
    def rate_limit_after_fetch
      headers["x-ratelimit-remaining"].to_i
    end

    # Remaining after all API calls (events fetch + enrichment).
    def rate_limit_remaining
      rate_limit_after_fetch - api_calls_made
    end

    # Total API calls we made this cycle: 1 for events fetch + enrichment calls.
    def total_api_calls
      1 + api_calls_made
    end

    def has_rate_limit_limit?
      headers.present? && headers["x-ratelimit-limit"].present?
    end

    def has_rate_limit_remaining?
      headers.present? && headers["x-ratelimit-remaining"].present?
    end
  end
end
