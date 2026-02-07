ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "webmock/minitest"
require_relative "support/github_fixtures"

module ActiveSupport
  class TestCase
    include FactoryBot::Syntax::Methods
    include GithubFixtures

    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Add more helper methods to be used by all tests here...
  end
end
