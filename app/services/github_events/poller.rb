module GithubEvents
  class Poller
    Result = Struct.new(:outcome, :next_interval_seconds)

    def call
      stats = PollStats.new
      scheduler = NextJobScheduler.new
      state = scheduler.load_state

      fetch = Fetch::EventsFetch.new.call(etag: state["etag"])
      stats.record_fetch(status: fetch.status, headers: fetch.headers, decode_error: fetch.decode_error)

      process(state, scheduler, fetch, stats)
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
      handle_failure(e, state, scheduler, stats || PollStats.new, reason: "timeout")
    rescue => e
      handle_failure(e, state, scheduler, stats || PollStats.new, reason: "exception")
    end

    private

    def process(state, scheduler, fetch, stats)
      case fetch.status
      when 200
        raw_events = fetch.events || []
        processed = EventsProcessor.run(events: raw_events)
        stats.record_events(received: raw_events.size, processed: processed.events_count)

        enrichment = Enricher.new.call(
          processed.rows,
          rate_limit_remaining: fetch.headers["x-ratelimit-remaining"]
        )
        stats.record_enrichment(
          actor_stats: enrichment.enrichment_stats[:actors],
          repo_stats: enrichment.enrichment_stats[:repos],
          api_calls_made: enrichment.api_calls_made
        )

        upsert_events!(enrichment.rows.map { |row| row[:event] })
        schedule = scheduler.apply_success(state, stats)
        build_result(:ok, schedule)
      when 304
        schedule = scheduler.apply_success(state, stats)
        build_result(:not_modified, schedule)
      when 429
        schedule = scheduler.apply_rate_limit(state, stats)
        build_result(:rate_limited, schedule)
      when 500..599
        schedule = scheduler.apply_backoff(state, stats, reason: "server_error_#{fetch.status}")
        build_result(:backing_off, schedule)
      else
        schedule = scheduler.apply_unexpected(
          state, stats,
          error: "status=#{fetch.status}#{request_id_suffix(fetch.headers)}"
        )
        build_result(:error, schedule)
      end
    end

    def handle_failure(exception, state, scheduler, stats, reason:)
      Rails.error.report(exception, context: { reason: }, handled: true)
      schedule = scheduler.apply_backoff(
        state || scheduler.load_state, stats,
        reason:, exception:
      )
      build_result(reason.to_sym, schedule)
    end

    def upsert_events!(rows)
      return if rows.blank?

      GithubEvent.upsert_all(rows, unique_by: :index_github_events_on_event_id)
    end

    def request_id_suffix(headers)
      request_id = headers["x-github-request-id"]
      request_id.present? ? " request_id=#{request_id}" : ""
    end

    def build_result(outcome, schedule)
      Result.new(outcome, schedule.next_interval_seconds)
    end
  end
end
