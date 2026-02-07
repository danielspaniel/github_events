module GithubEvents
  class Enricher
    Result = Struct.new(:rows, :api_calls_made, :enrichment_stats, keyword_init: true)

    # Enriches rows with actor/repo FK references.
    # Each row is an EnrichmentRow with :event, :actor, and :repo.
    # After enrichment, :actor and :repo are stripped; :event has actor_id/repository_id set.
    # Returns a Result with :rows, :api_calls_made, and :enrichment_stats.
    def call(rows, rate_limit_remaining: nil)
      return Result.new(rows:, api_calls_made: 0, enrichment_stats: {}) if rows.blank?

      budget = compute_budget(rate_limit_remaining)
      total_calls = 0
      enrichment_stats = {}

      enrichers = [
        [Enrichment::ActorEnricher.new, :actors],
        [Enrichment::RepoEnricher.new, :repos]
      ]

      enrichers.each do |enricher, key|
        break if budget&.zero?

        begin
          stats = enricher.call(rows, budget:)
          calls_made = stats[:attempted]
          enrichment_stats[key] = stats
          total_calls += calls_made
          budget -= calls_made if budget
        rescue => e
          Rails.error.report(e, context: { enricher: enricher.class.name }, handled: true)
          budget = 0 if budget # assume worst case — next enricher skips
        end
      end

      rows.each(&:strip_transients!)
      Result.new(rows:, api_calls_made: total_calls, enrichment_stats:)
    end

    private

    # nil = unlimited, 0 = exhausted, N = N calls left.
    def compute_budget(rate_limit_remaining)
      return nil if rate_limit_remaining.blank?

      [rate_limit_remaining.to_i - RateLimit::THRESHOLD, 0].max
    end
  end
end
