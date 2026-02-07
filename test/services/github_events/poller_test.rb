require "test_helper"

class GithubEvents::PollerTest < ActiveSupport::TestCase
  EVENTS_URL = GithubEvents::Fetch::EventsFetch::GITHUB_EVENTS_URL

  def stub_events_api(status:, body: "[]", headers: {})
    default_headers = { "Content-Type" => "application/json" }
    stub_request(:get, EVENTS_URL)
      .to_return(status: status, body: body, headers: default_headers.merge(headers))
  end

  def poller
    GithubEvents::Poller.new
  end

  def write_state(attrs)
    Rails.cache.write(GithubEvents::NextJobScheduler::STATE_CACHE_KEY, attrs)
  end

  def setup
    Rails.cache.clear
  end

  test "200 upserts events with actor and repo enrichment" do
    actor_login = "jmartasek"
    actor_github_id = USER_ID_BY_LOGIN.fetch(actor_login)
    repo_full_name = "jmartasek/grafana"
    repo_github_id = REPO_ID_BY_NAME.fetch(repo_full_name)

    event_1 = github_push_event(
      id: "event_1",
      actor_login: actor_login,
      actor_github_id: actor_github_id,
      repo_name: repo_full_name,
      repo_github_id: repo_github_id
    )
    event_2 = github_push_event(
      id: "event_2",
      actor_login: actor_login,
      actor_github_id: actor_github_id,
      repo_name: repo_full_name,
      repo_github_id: repo_github_id
    )

    events = [ event_1, event_2 ]
    stub_events_api(status: 200, body: events.to_json)
    stub_github_user_api(actor_login, id: actor_github_id)
    stub_github_repo_api(repo_full_name, id: repo_github_id)

    result = poller.call

    assert_equal :ok, result.outcome
    assert_equal 2, GithubEvent.count
    assert_equal [ event_1["id"], event_2["id"] ].sort, GithubEvent.pluck(:event_id).sort
    assert_equal 60, result.next_interval_seconds

    # Enrichment created actor with correct attributes
    assert_equal 1, Actor.count
    actor = Actor.first
    assert_equal actor_github_id, actor.github_id
    assert_equal actor_login, actor.login
    assert_equal "https://api.github.com/users/#{actor_login}", actor.url
    assert actor.data.key?("public_repos"), "actor.data should contain full API response"

    # Enrichment created repo with correct attributes
    assert_equal 1, Repository.count
    repository = Repository.first
    assert_equal repo_github_id, repository.github_id
    assert_equal repo_full_name, repository.name
    assert_equal "https://api.github.com/repos/#{repo_full_name}", repository.url
    assert repository.data.key?("language"), "repo.data should contain full API response"

    # Persisted event has correct structured fields
    event = GithubEvent.find_by!(event_id: event_1["id"])
    assert_equal event_1["id"], event.event_id
    assert_equal "PushEvent", event.event_type
    assert_equal "refs/heads/legend-list-alphabetical-sort", event.ref
    assert_equal "7c98a1af487ccf269b66d544022230fadd42fc8b", event.head
    assert_equal "a076fed3c63050fa1fd39fa37c286f47c21a4015", event.before
    assert_equal repo_github_id, event.repository_identifier
    assert event.push_identifier.present?, "push_identifier should be set"
    assert event.data.key?("payload"), "event.data should retain full raw payload"

    # Events linked to enriched records via FK
    assert_equal actor.id, event.actor_id
    assert_equal repository.id, event.repository_id
  end

  test "304 returns not_modified and does not insert events" do
    stub_events_api(status: 304, headers: { "ETag" => '"same"' })

    result = poller.call

    assert_equal :not_modified, result.outcome
    assert_equal 0, GithubEvent.count
    assert_equal 60, result.next_interval_seconds
  end

  test "uses If-None-Match when etag is present" do
    write_state(
      "etag" => '"old_etag"',
      "poll_interval_seconds" => 0,
      "last_polled_at" => 1.hour.ago.iso8601
    )

    stub = stub_request(:get, EVENTS_URL)
      .with(headers: { "If-None-Match" => '"old_etag"' })
      .to_return(status: 304, headers: { "Content-Type" => "application/json" })

    poller.call

    assert_requested(stub)
  end

  test "timeout returns :timeout with backoff" do
    stub_request(:get, EVENTS_URL).to_raise(Faraday::TimeoutError)

    result = poller.call

    assert_equal :timeout, result.outcome
    assert_equal 30, result.next_interval_seconds
  end

  test "500 returns :backing_off with backoff" do
    stub_events_api(status: 500)

    result = poller.call

    assert_equal :backing_off, result.outcome
    assert_equal 30, result.next_interval_seconds
  end

  test "200 with mixed human and bot events upserts all rows" do
    human_event = github_push_event(actor_login: "jmartasek", repo_name: "jmartasek/grafana")
    bot_event   = github_bot_push_event(repo_name: "jmartasek/grafana")

    stub_events_api(status: 200, body: [ human_event, bot_event ].to_json)
    stub_github_user_api("jmartasek")
    stub_github_repo_api("jmartasek/grafana")

    result = poller.call

    assert_equal :ok, result.outcome
    assert_equal 2, GithubEvent.count, "both human and bot events should be persisted"

    human_record = GithubEvent.find_by(event_id: human_event["id"])
    bot_record   = GithubEvent.find_by(event_id: bot_event["id"])

    assert_not_nil human_record.actor_id, "human event should have actor_id"
    assert_nil bot_record.actor_id, "bot event should have nil actor_id"

    # Both should have repository_id since they share the same repo
    assert_not_nil human_record.repository_id
    assert_not_nil bot_record.repository_id
  end

  test "429 returns :rate_limited using x-ratelimit-reset" do
    reset_at = Time.current.to_i + 120
    stub_events_api(status: 429, headers: { "x-ratelimit-reset" => reset_at.to_s })

    result = poller.call

    assert_equal :rate_limited, result.outcome
    assert_includes 120..126, result.next_interval_seconds
  end
end
