module GithubEvents
  class PollLogger
    # Logs a structured summary of a poll cycle result.
    # Reads all data from a PollStats object — each pipeline step
    # records into stats, and the logger formats whatever is present.
    def self.log(stats)
      new.log(stats)
    end

    def log(stats)
      lines = []
      lines << build_headline(stats)
      lines << build_rate_limit_line(stats) if stats.has_rate_limit_limit?
      lines << build_events_line(stats) if stats.events_received.to_i > 0 || stats.events_count.to_i > 0
      lines << build_enricher_line("Actors", stats.actor_stats) if stats.actor_stats.any?
      lines << build_enricher_line("Repos", stats.repo_stats) if stats.repo_stats.any?
      lines.concat(build_api_budget_lines(stats)) if stats.has_rate_limit_remaining?
      lines << build_next_poll_line(stats)

      Rails.logger.info(lines.join("\n"))
    end

    private

    def build_headline(stats)
      line = "GitHub events poll #{stats.outcome}"
      details = []
      details << stats.error_message if stats.error_message
      details << stats.reason if stats.reason && stats.error_message.nil?
      details << "status=#{stats.status}" if stats.status && !%w[ok not_modified].include?(stats.outcome)
      details << "request_id=#{stats.headers["x-github-request-id"]}" if stats.headers["x-github-request-id"].present?
      details << "decode_error" if stats.decode_error
      line += ": #{details.join(', ')}" if details.any?
      line
    end

    def build_events_line(stats)
      received = stats.events_received
      kept = stats.events_count
      skipped = received - kept

      parts = [ "#{received} received" ]
      parts << "#{kept} push events" if kept > 0
      parts << "#{skipped} skipped" if skipped > 0
      "  Events:     #{parts.join(', ')}"
    end

    def build_rate_limit_line(stats)
      limit = stats.rate_limit_limit
      threshold = RateLimit::THRESHOLD
      "  Rate limit: #{limit}/hour, threshold=#{threshold}"
    end

    def build_api_budget_lines(stats)
      actor_calls = stats.actor_stats[:attempted] || 0
      repo_calls = stats.repo_stats[:attempted] || 0

      breakdown = [ "events=1" ]
      breakdown << "actors=#{actor_calls}" if actor_calls > 0
      breakdown << "repos=#{repo_calls}" if repo_calls > 0

      [
        "  API avail:  #{stats.rate_limit_before}",
        "  API used:   #{stats.total_api_calls} (#{breakdown.join(', ')})",
        "  API left:   #{stats.rate_limit_remaining}"
      ]
    end

    def build_enricher_line(label, s)
      outcomes = []
      outcomes << "#{s[:fetched]} ok" if s[:fetched].to_i > 0
      outcomes << "#{s[:not_modified]} not_modified" if s[:not_modified].to_i > 0
      outcomes << "#{s[:decode_error]} decode_error" if s[:decode_error].to_i > 0
      outcomes << "#{s[:mismatched]} mismatched" if s[:mismatched].to_i > 0
      outcomes << "#{s[:failed]} failed" if s[:failed].to_i > 0

      attempted = s[:attempted].to_i
      detail = outcomes.any? ? " (#{outcomes.join(', ')})" : ""
      "  #{(label + ':').ljust(12)}#{s[:unique_ids]} unique, #{attempted} fetched#{detail}"
    end

    def build_next_poll_line(stats)
      time = humanize_interval(stats.interval)
      note = next_poll_note(stats)
      suffix = note ? " (#{note})" : ""
      "  Next poll:  in #{time}#{suffix}"
    end

    def next_poll_note(stats)
      if stats.rate_limited
        reset = stats.reset_in.to_i.positive? ? "resets in #{humanize_interval(stats.reset_in.to_i)}" : "near limit"
        "waiting for rate limit, #{reset}"
      elsif stats.outcome == "backoff"
        "backoff"
      elsif stats.server_interval.to_i > NextJobScheduler::DEFAULT_POLL_INTERVAL
        "server requested #{stats.server_interval}s"
      end
    end

    def humanize_interval(seconds)
      ActiveSupport::Duration.build(seconds).inspect
    end
  end
end
