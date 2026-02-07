require "test_helper"

class GithubEvents::EventsProcessorTest < ActiveSupport::TestCase
  test "only PushEvents are retained" do
    push_event = github_push_event(id: "push_1")
    non_push_event = { "id" => "watch_1", "type" => "WatchEvent", "payload" => {} }
    events = [ push_event, non_push_event ]

    result = GithubEvents::EventsProcessor.run(events: events)

    assert_equal 1, result.rows.size
    assert_equal push_event["id"], result.rows.first[:event][:event_id]
  end

  test "PushEvents with missing payload fields are skipped" do
    incomplete_event = github_push_event(id: "push_incomplete")
    incomplete_event["payload"].delete("ref")
    complete_event = github_push_event(id: "push_complete")

    result = GithubEvents::EventsProcessor.run(events: [ incomplete_event, complete_event ])

    assert_equal 1, result.rows.size
    assert_equal complete_event["id"], result.rows.first[:event][:event_id]
  end

  test "non-hash entries are ignored" do
    valid_event = github_push_event(id: "push_1")
    events = [ "not a hash", 42, nil, valid_event ]
    result = GithubEvents::EventsProcessor.run(events: events)

    assert_equal 1, result.rows.size
  end

  test "empty events array returns no rows" do
    result = GithubEvents::EventsProcessor.run(events: [])

    assert_equal 0, result.rows.size
  end

  test "row includes all expected fields from a real event" do
    actor_login = "jmartasek"
    actor_github_id = USER_ID_BY_LOGIN.fetch(actor_login)
    repo_full_name = "jmartasek/grafana"
    repo_github_id = REPO_ID_BY_NAME.fetch(repo_full_name)

    event = github_push_event(
      actor_login: actor_login,
      actor_github_id: actor_github_id,
      repo_name: repo_full_name,
      repo_github_id: repo_github_id,
      ref: "refs/heads/legend-list-alphabetical-sort",
      head: "7c98a1af487ccf269b66d544022230fadd42fc8b",
      before: "a076fed3c63050fa1fd39fa37c286f47c21a4015",
      created_at: "2026-02-07T19:32:17Z"
    )
    result = GithubEvents::EventsProcessor.run(events: [ event ])

    row = result.rows.first
    assert_equal event["id"], row[:event][:event_id]
    assert_equal "PushEvent", row[:event][:event_type]

    # Actor fields from event payload
    assert_equal actor_github_id, row.actor[:github_id]
    assert_equal "https://api.github.com/users/#{actor_login}", row.actor[:url]

    # Repo fields from event payload
    assert_equal repo_github_id, row.repo[:github_id]
    assert_equal "https://api.github.com/repos/#{repo_full_name}", row.repo[:url]

    # Push payload fields
    assert_equal repo_github_id, row[:event][:repository_identifier]
    assert_equal event["payload"]["push_id"], row[:event][:push_identifier]
    assert_equal "refs/heads/legend-list-alphabetical-sort", row[:event][:ref]
    assert_equal "7c98a1af487ccf269b66d544022230fadd42fc8b", row[:event][:head]
    assert_equal "a076fed3c63050fa1fd39fa37c286f47c21a4015", row[:event][:before]

    assert_equal true, row[:event][:public]
    assert_equal Time.zone.parse("2026-02-07T19:32:17Z"), row[:event][:github_created_at]
    assert_equal event, row[:event][:data]
  end

  test "bot actor enrichment is nil — event still processed" do
    bot_event = github_bot_push_event
    event = bot_event
    result = GithubEvents::EventsProcessor.run(events: [ event ])

    assert_equal 1, result.rows.size
    row = result.rows.first
    assert_nil row.actor, "bot actor should be nil so enricher skips it"
    assert_not_nil row.repo, "repo should still be present for enrichment"
    assert_equal bot_event["id"], row[:event][:event_id]
  end
end
