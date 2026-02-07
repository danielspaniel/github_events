require "test_helper"

class GithubEvents::EventsProcessorTest < ActiveSupport::TestCase
  test "only PushEvents are retained" do
    push = github_push_event
    events = [push, { "id" => "999", "type" => "WatchEvent", "payload" => {} }]

    result = GithubEvents::EventsProcessor.run(events: events)

    assert_equal 1, result.rows.size
    assert_equal push["id"], result.rows.first[:event][:event_id]
  end

  test "PushEvents with missing payload fields are skipped" do
    incomplete = github_push_event
    incomplete["payload"].delete("ref")
    complete = github_push_event

    result = GithubEvents::EventsProcessor.run(events: [incomplete, complete])

    assert_equal 1, result.rows.size
    assert_equal complete["id"], result.rows.first[:event][:event_id]
  end

  test "non-hash entries are ignored" do
    events = ["not a hash", 42, nil, github_push_event]
    result = GithubEvents::EventsProcessor.run(events: events)

    assert_equal 1, result.rows.size
  end

  test "empty events array returns no rows" do
    result = GithubEvents::EventsProcessor.run(events: [])

    assert_equal 0, result.rows.size
  end

  test "row includes all expected fields from a real event" do
    event = github_push_event(
      ref: "refs/heads/legend-list-alphabetical-sort",
      head: "7c98a1af487ccf269b66d544022230fadd42fc8b",
      before: "a076fed3c63050fa1fd39fa37c286f47c21a4015",
      created_at: "2026-02-07T19:32:17Z"
    )
    result = GithubEvents::EventsProcessor.run(events: [event])

    row = result.rows.first
    assert_equal event["id"], row[:event][:event_id]
    assert_equal "PushEvent", row[:event][:event_type]

    # Actor fields from event payload
    assert_equal 14291370, row.actor[:github_id]
    assert_equal "https://api.github.com/users/jmartasek", row.actor[:url]

    # Repo fields from event payload
    assert_equal 1152169359, row.repo[:github_id]
    assert_equal "https://api.github.com/repos/jmartasek/grafana", row.repo[:url]

    # Push payload fields
    assert_equal 1152169359, row[:event][:repository_identifier]
    assert_equal event["payload"]["push_id"], row[:event][:push_identifier]
    assert_equal "refs/heads/legend-list-alphabetical-sort", row[:event][:ref]
    assert_equal "7c98a1af487ccf269b66d544022230fadd42fc8b", row[:event][:head]
    assert_equal "a076fed3c63050fa1fd39fa37c286f47c21a4015", row[:event][:before]

    assert_equal true, row[:event][:public]
    assert_equal Time.zone.parse("2026-02-07T19:32:17Z"), row[:event][:github_created_at]
    assert_equal event, row[:event][:data]
  end

  test "bot actor enrichment is nil — event still processed" do
    event = github_bot_push_event
    result = GithubEvents::EventsProcessor.run(events: [event])

    assert_equal 1, result.rows.size
    row = result.rows.first
    assert_nil row.actor, "bot actor should be nil so enricher skips it"
    assert_not_nil row.repo, "repo should still be present for enrichment"
    assert_equal event["id"], row[:event][:event_id]
  end
end
