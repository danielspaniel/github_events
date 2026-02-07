module GithubEvents
  module Fetch
    class EventsFetch < ResourceFetch
      GITHUB_EVENTS_URL = "https://api.github.com/events?per_page=100".freeze
      USER_AGENT = "github_events/PushEvents".freeze
      OPEN_TIMEOUT = 5
      READ_TIMEOUT = 15
      HEADER_WHITELIST = %w[
        etag
        x-poll-interval
        x-ratelimit-limit
        x-ratelimit-remaining
        x-ratelimit-reset
        retry-after
        x-github-request-id
      ].freeze
      Result = Struct.new(:status, :headers, :events, :decode_error)

      def initialize(open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT)
        super(
          user_agent: USER_AGENT,
          open_timeout:,
          read_timeout:,
          raise_on_timeout: true
        )
      end

      def call(etag: nil)
        response = super(url: GITHUB_EVENTS_URL, etag:)
        headers = extract_headers(response)
        events = response.json

        Result.new(
          response.status.to_i,
          headers,
          events,
          response.decode_error
        )
      end

      private

      def extract_headers(response)
        response.headers.slice(*HEADER_WHITELIST).compact
      end
    end
  end
end
