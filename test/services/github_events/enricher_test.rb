require "test_helper"

class GithubEvents::EnricherTest < ActiveSupport::TestCase
  def enricher
    GithubEvents::Enricher.new
  end

  test "fetches and creates actor and repository records" do
    actor_login = "jmartasek"
    actor_github_id = USER_ID_BY_LOGIN.fetch(actor_login)
    repo_full_name = "jmartasek/grafana"
    repo_github_id = REPO_ID_BY_NAME.fetch(repo_full_name)

    event = github_push_event(
      actor_login: actor_login,
      actor_github_id: actor_github_id,
      repo_name: repo_full_name,
      repo_github_id: repo_github_id
    )
    rows = processed_rows_from(event)

    stub_github_user_api(actor_login, id: actor_github_id)
    stub_github_repo_api(repo_full_name, id: repo_github_id)

    enricher.call(rows)

    assert_equal 1, Actor.count
    actor = Actor.first
    assert_equal actor_github_id, actor.github_id
    assert_equal actor_login, actor.login
    assert_equal "https://api.github.com/users/#{actor_login}", actor.url
    assert actor.data.key?("public_repos"), "actor.data should contain full API response"

    assert_equal 1, Repository.count
    repo = Repository.first
    assert_equal repo_github_id, repo.github_id
    assert_equal repo_full_name, repo.name
    assert_equal "https://api.github.com/repos/#{repo_full_name}", repo.url
    assert repo.data.key?("language"), "repo.data should contain full API response"

    row = rows.first
    assert_equal actor.id, row[:event][:actor_id]
    assert_equal repo.id, row[:event][:repository_id]
  end

  test "skips actors and repos already in database — no HTTP calls" do
    existing_actor = create(:actor, :jmartasek)
    existing_repo = create(:repository, :grafana)

    rows = processed_rows_from(github_push_event)
    enricher.call(rows)

    # No HTTP stubs needed — would blow up if it tried to fetch
    assert_equal 1, Actor.count
    assert_equal 1, Repository.count
    assert_equal existing_actor.id, rows.first[:event][:actor_id]
    assert_equal existing_repo.id, rows.first[:event][:repository_id]
  end

  test "deduplicates actors and repos across batch" do
    stub_github_user_api("jmartasek")
    stub_github_repo_api("jmartasek/grafana")

    events = [
      github_push_event(actor_login: "jmartasek", repo_name: "jmartasek/grafana"),
      github_push_event(actor_login: "jmartasek", repo_name: "jmartasek/grafana"),
      github_push_event(actor_login: "jmartasek", repo_name: "jmartasek/grafana")
    ]
    rows = processed_rows_from(*events)

    enricher.call(rows)

    assert_equal 1, Actor.count, "3 events from jmartasek → 1 actor record"
    assert_equal 1, Repository.count, "3 events from jmartasek/grafana → 1 repo record"

    actor_id = Actor.first.id
    repo_id  = Repository.first.id
    rows.each do |row|
      assert_equal actor_id, row[:event][:actor_id]
      assert_equal repo_id, row[:event][:repository_id]
    end
  end

  test "handles multiple distinct actors and repos in one batch" do
    stub_github_user_api("jmartasek")
    stub_github_user_api("torvalds")
    stub_github_repo_api("jmartasek/grafana")
    stub_github_repo_api("torvalds/linux")

    events = [
      github_push_event(actor_login: "jmartasek", repo_name: "jmartasek/grafana"),
      github_push_event(actor_login: "torvalds", repo_name: "torvalds/linux")
    ]
    rows = processed_rows_from(*events)

    enricher.call(rows)

    assert_equal 2, Actor.count
    assert_equal 2, Repository.count
    assert_equal %w[jmartasek torvalds].sort, Actor.pluck(:login).sort
    assert_equal %w[jmartasek/grafana torvalds/linux].sort, Repository.pluck(:name).sort
  end

  test "API failure for actor does not block repo enrichment" do
    stub_request(:get, "https://api.github.com/users/jmartasek").to_return(status: 500)
    stub_github_repo_api("jmartasek/grafana")

    rows = processed_rows_from(github_push_event)
    enricher.call(rows)

    assert_equal 0, Actor.count
    assert_equal 1, Repository.count
    assert_nil rows.first[:event][:actor_id]
    assert_equal Repository.first.id, rows.first[:event][:repository_id]
  end

  test "API timeout for repo does not block actor enrichment" do
    stub_github_user_api("jmartasek")
    stub_request(:get, "https://api.github.com/repos/jmartasek/grafana").to_timeout

    rows = processed_rows_from(github_push_event)
    enricher.call(rows)

    assert_equal 1, Actor.count
    assert_equal 0, Repository.count
    assert_equal Actor.first.id, rows.first[:event][:actor_id]
    assert_nil rows.first[:event][:repository_id]
  end

  test "uses If-None-Match on refresh and handles 304 Not Modified" do
    actor = create(:actor, :jmartasek, etag: "\"etag-actor\"", created_at: 2.days.ago, updated_at: 2.days.ago)
    repo = create(:repository, :grafana, etag: "\"etag-repo\"", created_at: 2.days.ago, updated_at: 2.days.ago)

    actor_stub = stub_request(:get, "https://api.github.com/users/jmartasek")
      .with(headers: { "If-None-Match" => "\"etag-actor\"" })
      .to_return(status: 304, headers: { "ETag" => "\"etag-actor\"" })
    repo_stub = stub_request(:get, "https://api.github.com/repos/jmartasek/grafana")
      .with(headers: { "If-None-Match" => "\"etag-repo\"" })
      .to_return(status: 304, headers: { "ETag" => "\"etag-repo\"" })

    rows = processed_rows_from(github_push_event)
    enricher.call(rows)

    assert_requested(actor_stub)
    assert_requested(repo_stub)
    assert_equal 1, Actor.count
    assert_equal 1, Repository.count
    assert_equal actor.id, rows.first[:event][:actor_id]
    assert_equal repo.id, rows.first[:event][:repository_id]
    assert_equal "\"etag-actor\"", Actor.first.etag
    assert_equal "\"etag-repo\"", Repository.first.etag
  end

  test "decode error on actor does not block repo enrichment" do
    stub_request(:get, "https://api.github.com/users/jmartasek")
      .to_return(status: 200, body: "not-json", headers: { "Content-Type" => "application/json" })
    stub_github_repo_api("jmartasek/grafana")

    rows = processed_rows_from(github_push_event)
    enricher.call(rows)

    assert_equal 0, Actor.count
    assert_equal 1, Repository.count
    assert_nil rows.first[:event][:actor_id]
    assert_equal Repository.first.id, rows.first[:event][:repository_id]
  end

  test "skips mismatched actor id and still enriches repo" do
    mismatch_body = github_user_api_response(id: 999, login: "jmartasek")
    stub_request(:get, "https://api.github.com/users/jmartasek")
      .to_return(status: 200, body: mismatch_body.to_json, headers: { "Content-Type" => "application/json" })
    stub_github_repo_api("jmartasek/grafana")

    rows = processed_rows_from(github_push_event)
    enricher.call(rows)

    assert_equal 0, Actor.count
    assert_equal 1, Repository.count
    assert_nil rows.first[:event][:actor_id]
    assert_equal Repository.first.id, rows.first[:event][:repository_id]
  end

  test "strips transient url keys from rows after enrichment" do
    stub_github_user_api("jmartasek")
    stub_github_repo_api("jmartasek/grafana")

    rows = processed_rows_from(github_push_event)
    enricher.call(rows)

    row = rows.first
    assert_nil row.actor, "actor enrichment should be stripped before persistence"
    assert_nil row.repo, "repo enrichment should be stripped before persistence"
  end

  test "skips enrichment when rate limit budget is exhausted" do
    rows = processed_rows_from(github_push_event)

    # No HTTP stubs: any request would blow up the test
    enricher.call(rows, rate_limit_remaining: 3)

    assert_equal 0, Actor.count
    assert_equal 0, Repository.count
    assert_nil rows.first[:event][:actor_id]
    assert_nil rows.first[:event][:repository_id]
  end

  test "shared rate limit budget applies across actors and repos" do
    rows = processed_rows_from(github_push_event)

    stub_github_user_api("jmartasek")
    # No repo stub: if it tries to fetch the repo, test should fail.

    enricher.call(rows, rate_limit_remaining: 6)

    assert_equal 1, Actor.count
    assert_equal 0, Repository.count
  end

  test "handles empty rows" do
    result = enricher.call([])
    assert_equal [], result.rows
    assert_equal 0, result.api_calls_made
  end

  test "handles nil rows" do
    result = enricher.call(nil)
    assert_nil result.rows
    assert_equal 0, result.api_calls_made
  end

  test "returns api_calls_made for budget tracking" do
    stub_github_user_api("jmartasek")
    stub_github_repo_api("jmartasek/grafana")

    rows = processed_rows_from(github_push_event)
    result = enricher.call(rows)

    assert_equal 2, result.api_calls_made, "1 actor fetch + 1 repo fetch = 2"
    assert_equal rows, result.rows
  end

  test "api_calls_made reflects only actors when repo budget exhausted" do
    stub_github_user_api("jmartasek")
    # No repo stub — budget exhausted after actor fetch

    rows = processed_rows_from(github_push_event)
    result = enricher.call(rows, rate_limit_remaining: 6)

    assert_equal 1, result.api_calls_made, "only 1 actor fetch before budget hit zero"
  end

  test "enrichment_stats includes per-enricher breakdown" do
    stub_github_user_api("jmartasek")
    stub_github_repo_api("jmartasek/grafana")

    rows = processed_rows_from(github_push_event)
    result = enricher.call(rows)

    actor_stats = result.enrichment_stats[:actors]
    assert_not_nil actor_stats, "should have actor stats"
    assert_equal 1, actor_stats[:unique_ids]
    assert_equal 1, actor_stats[:attempted]
    assert_equal 1, actor_stats[:fetched]
    assert_equal 0, actor_stats[:failed]

    repo_stats = result.enrichment_stats[:repos]
    assert_not_nil repo_stats, "should have repo stats"
    assert_equal 1, repo_stats[:unique_ids]
    assert_equal 1, repo_stats[:attempted]
    assert_equal 1, repo_stats[:fetched]
    assert_equal 0, repo_stats[:failed]
  end

  test "enrichment_stats omits repos when budget exhausted after actors" do
    stub_github_user_api("jmartasek")

    rows = processed_rows_from(github_push_event)
    result = enricher.call(rows, rate_limit_remaining: 6)

    assert result.enrichment_stats.key?(:actors), "should have actor stats"
    assert_not result.enrichment_stats.key?(:repos), "repos should be skipped when budget exhausted"
  end

  test "enrichment_stats is empty hash when rows are blank" do
    result = enricher.call([])
    assert_equal({}, result.enrichment_stats)
  end

  test "bot actor events are saved with nil actor_id — no lookup, no actor record" do
    stub_github_repo_api("jmartasek/grafana")

    rows = processed_rows_from(github_bot_push_event)

    # No user API stub — would blow up if it tried to fetch the bot
    enricher.call(rows)

    assert_equal 0, Actor.count, "no actor record for bots"
    assert_nil rows.first[:event][:actor_id], "bot event has nil actor_id"
    assert_equal 1, Repository.count, "repo still enriched normally"
  end

  test "mixed batch — bot events get nil actor_id, human events get actor_id" do
    stub_github_user_api("jmartasek")
    stub_github_repo_api("jmartasek/grafana")

    human_event = github_push_event
    bot_event = github_bot_push_event
    events = [ human_event, bot_event ]
    rows = processed_rows_from(*events)

    result = enricher.call(rows)

    assert_equal 1, Actor.count, "only human actor created"
    assert_equal "jmartasek", Actor.first.login

    human_row, bot_row = rows.partition { |r| r[:event][:data].dig("actor", "login") == "jmartasek" }
                              .map(&:first)
    assert_equal Actor.first.id, human_row[:event][:actor_id]
    assert_nil bot_row[:event][:actor_id], "bot event has nil actor_id"

    assert_equal 2, result.api_calls_made, "1 human actor + 1 repo = 2 (bot is free)"
  end

  test "handles events with missing actor/repo urls gracefully" do
    event = github_push_event
    event["actor"].delete("url")
    event["repo"].delete("url")

    rows = processed_rows_from(event)
    enricher.call(rows)

    assert_equal 0, Actor.count
    assert_equal 0, Repository.count
  end
end
