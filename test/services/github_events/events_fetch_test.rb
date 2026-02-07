require "test_helper"

class GithubEvents::Fetch::EventsFetchTest < ActiveSupport::TestCase
  EVENTS_URL = GithubEvents::Fetch::EventsFetch::GITHUB_EVENTS_URL

  def fetcher
    GithubEvents::Fetch::EventsFetch.new
  end

  test "returns headers and events for 200 responses" do
    body = [ { "id" => "1", "type" => "PushEvent" } ].to_json
    stub_request(:get, EVENTS_URL)
      .to_return(
        status: 200,
        body: body,
        headers: {
          "Content-Type" => "application/json",
          "ETag" => '"abc"',
          "X-Poll-Interval" => "90"
        }
      )

    result = fetcher.call

    assert_equal 200, result.status
    assert_equal '"abc"', result.headers["etag"]
    assert_equal "90", result.headers["x-poll-interval"]
    assert_equal 1, result.events.size
    assert_equal false, result.decode_error
  end

  test "flags decode_error when JSON is invalid" do
    stub_request(:get, EVENTS_URL)
      .to_return(status: 200, body: "not-json", headers: { "Content-Type" => "application/json" })

    result = fetcher.call

    assert_equal 200, result.status
    assert_nil result.events
    assert_equal true, result.decode_error
  end
end
