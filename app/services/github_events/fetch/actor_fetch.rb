module GithubEvents
  module Fetch
    class ActorFetch < ResourceFetch
      USER_AGENT = "github_events/ActorFetch".freeze
      OPEN_TIMEOUT = 5
      READ_TIMEOUT = 10

      def initialize(open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT)
        super(
          user_agent: USER_AGENT,
          open_timeout:,
          read_timeout:
        )
      end
    end
  end
end
