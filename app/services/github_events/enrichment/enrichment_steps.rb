module GithubEvents
  module Enrichment
    # Shared pipeline steps used by both ActorEnricher and RepoEnricher.
    # Pure module functions — no state, no instances.
    module EnrichmentSteps
      # How long before a previously-fetched resource is re-fetched.
      REFRESH_AFTER = 24.hours

      # Max API calls per enrichment pass (when no rate limit header is present).
      MAX_FETCH_PER_BATCH = 50

      # Returns a hash of github_id → url that need fetching (missing or stale).
      def self.pick_fetchable(id_url_map, existing, budget:)
        missing = id_url_map.reject { |id, _| existing.key?(id) }
        stale   = id_url_map.select { |id, _| refresh_due?(existing[id]) }
        limit   = budget || MAX_FETCH_PER_BATCH

        missing.merge(stale).first(limit).to_h
      end

      # Fetches each resource via api_client. Returns [fetched, stats].
      # fetched = array of { data:, url:, headers: } for successful responses.
      def self.fetch_all(to_fetch, existing, api_client:, label:)
        stats   = { attempted: 0, fetched: 0, not_modified: 0, mismatched: 0, decode_error: 0, failed: 0 }
        fetched = []

        to_fetch.each do |github_id, url|
          stats[:attempted] += 1
          result = api_client.call(url:, etag: existing[github_id]&.etag)

          if result.decode_error
            stats[:decode_error] += 1
            next
          end

          if result.status == 304
            stats[:not_modified] += 1
            next
          end

          if result.status != 200 || result.json.nil?
            stats[:failed] += 1
            next
          end

          data = result.json
          unless data["id"].to_i == github_id.to_i
            Rails.logger.warn("#{label}: id mismatch expected=#{github_id} actual=#{data["id"]}")
            stats[:mismatched] += 1
            next
          end

          fetched << { data:, url:, headers: result.headers }
          stats[:fetched] += 1
        rescue => e
          Rails.logger.warn("#{label}: failed to fetch #{github_id}: #{e.message}")
          stats[:failed] += 1
        end

        [ fetched, stats ]
      end

      def self.refresh_due?(record)
        record&.updated_at.present? && record.updated_at < Time.current - REFRESH_AFTER
      end
      private_class_method :refresh_due?
    end
  end
end
