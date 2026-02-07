module GithubEvents
  class EventsProcessor
    Result = Struct.new(:rows, :events_count)

    def self.run(events:)
      new.call(events)
    end

    def call(events)
      rows = collect_rows(events)
      Result.new(rows, rows.size)
    end

    private

    def collect_rows(events, now = Time.current)
      return [] if !events.is_a?(Array) || events.empty?

      events
        .filter { |e| e.is_a?(Hash) }
        .filter { |e| push_event_valid?(e) }
        .map { |e| build_push_event_row(e, now) }
        .uniq { |row| row[:event][:event_id] }
    end

    def push_event_valid?(e)
      return false unless e["type"] == "PushEvent"
      return false if e["id"].blank?

      payload = e["payload"]
      return false unless payload.is_a?(Hash)

      required = payload.slice("repository_id", "push_id", "ref", "head", "before")
      required.size == 5 && required.values.all?(&:present?)
    end

    def build_push_event_row(e, now)
      payload = e.fetch("payload")

      EnrichmentRow.new(
        event: {
          event_id: e["id"].to_s,
          event_type: "PushEvent",
          actor_id: nil,
          repository_id: nil,
          repository_identifier: payload["repository_id"],
          push_identifier: payload["push_id"],
          ref: payload["ref"].to_s,
          head: payload["head"].to_s,
          before: payload["before"].to_s,
          public: e["public"],
          github_created_at: parse_time(e["created_at"]),
          data: e,
          created_at: now,
          updated_at: now
        },
        actor: build_actor_enrichment(e),
        repo: build_repo_enrichment(e)
      )
    end

    def parse_time(value)
      return if value.blank?
      Time.zone.parse(value)
    rescue ArgumentError, TypeError
      nil
    end

    def build_actor_enrichment(e)
      github_id = e.dig("actor", "id")
      url = e.dig("actor", "url")
      login = e.dig("actor", "login")
      return if github_id.blank? || url.blank?
      return if login.to_s.end_with?("[bot]")

      { github_id:, url: }
    end

    def build_repo_enrichment(e)
      github_id = e.dig("repo", "id")
      url = e.dig("repo", "url")
      return if github_id.blank? || url.blank?

      { github_id:, url: }
    end
  end
end
