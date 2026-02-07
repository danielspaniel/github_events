module GithubEvents
  module Fetch
    class HttpClient
      def initialize(user_agent:, open_timeout:, read_timeout:)
        @user_agent = user_agent
        @open_timeout = open_timeout
        @read_timeout = read_timeout
      end

      def get(url, headers: {})
        request_headers = { "User-Agent" => @user_agent }.merge(headers)
        faraday.get(sanitize_url(url), nil, request_headers)
      end

      private

      # Percent-encode characters that are invalid in URIs (e.g. square brackets
      # in bot usernames like "github-actions[bot]").
      def sanitize_url(url)
        url.gsub("[", "%5B").gsub("]", "%5D")
      end

      def faraday
        @faraday ||= Faraday.new do |f|
          f.options.open_timeout = @open_timeout
          f.options.timeout = @read_timeout
        end
      end
    end
  end
end
