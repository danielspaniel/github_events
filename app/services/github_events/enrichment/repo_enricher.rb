module GithubEvents
  module Enrichment
    # Pipeline: collect → pick fetchable → fetch → build payloads → upsert → assign FKs.
    # Returns a stats hash for metrics: { unique_ids:, attempted:, fetched:, not_modified:, ... }.
    class RepoEnricher
      EMPTY_STATS = { unique_ids: 0, attempted: 0, fetched: 0, not_modified: 0, mismatched: 0, decode_error: 0, failed: 0 }.freeze

      def initialize
        @api_client = Fetch::RepositoryFetch.new
      end

      def call(rows, budget:)
        id_url_map = collect_urls(rows)
        return EMPTY_STATS.dup if id_url_map.empty?

        now = Time.current
        existing = Repository.where(github_id: id_url_map.keys).index_by(&:github_id)
        to_fetch = EnrichmentSteps.pick_fetchable(id_url_map, existing, budget:)

        fetched, stats = EnrichmentSteps.fetch_all(to_fetch, existing, api_client: @api_client, label: "RepoEnricher")
        payloads = fetched.map { |result| build_payload(result, now:) }
        Repository.upsert_all(payloads, unique_by: :index_repositories_on_github_id) if payloads.any?

        assign_fks(rows, id_url_map.keys)

        stats.merge(unique_ids: id_url_map.size)
      end

      private

      def collect_urls(rows)
        rows.select(&:repo).each_with_object({}) do |row, map|
          map[row.repo[:github_id]] ||= row.repo[:url]
        end
      end

      def build_payload(result, now:)
        data, url, headers = result.values_at(:data, :url, :headers)
        {
          github_id: data["id"],
          name: data["full_name"] || data["name"],
          url:,
          etag: headers["etag"],
          data:,
          created_at: now,
          updated_at: now
        }
      end

      def assign_fks(rows, github_ids)
        fk_map = Repository.where(github_id: github_ids).pluck(:github_id, :id).to_h

        rows.select(&:repo).each do |row|
          row.event[:repository_id] = fk_map[row.repo[:github_id]]
        end
      end
    end
  end
end
