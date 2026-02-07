module GithubEvents
  module Fetch
    class ResourceFetch
      Result = Struct.new(:status, :headers, :json, :decode_error)

      def initialize(user_agent:, open_timeout:, read_timeout:, raise_on_timeout: false)
        @http_client = HttpClient.new(
          user_agent:,
          open_timeout:,
          read_timeout:
        )
        @raise_on_timeout = raise_on_timeout
      end

      def call(url:, headers: {}, etag: nil)
        headers["If-None-Match"] = etag if etag.present?
        response = @http_client.get(url, headers:)
        json = decode_json(response)

        Result.new(
          response.status.to_i,
          response.headers,
          json,
          json.nil? && response.status.to_i == 200
        )
      rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
        raise if @raise_on_timeout

        Rails.logger.warn("#{self.class.name}: timeout fetching #{url}: #{e.message}")
        Result.new(0, {}, nil, false)
      rescue => e
        Rails.logger.warn("#{self.class.name}: error fetching #{url}: #{e.message}")
        Result.new(0, {}, nil, false)
      end

      private

      def decode_json(response)
        return nil unless response.status.to_i == 200

        body = response.body
        return nil if body.blank?
        ActiveSupport::JSON.decode(body)
      rescue => e
        Rails.logger.warn("#{self.class.name}: failed to decode JSON: #{e.message}")
        nil
      end
    end
  end
end
