# Realistic GitHub API payloads based on actual responses.
# Include in test classes via `include GithubFixtures`.
#
# Event data matches the public events API: https://api.github.com/events
# Actor data matches the users API: https://api.github.com/users/:login
# Repo data matches the repos API: https://api.github.com/repos/:owner/:name

module GithubFixtures
  USER_ID_BY_LOGIN = {
    "jmartasek" => 14291370,
    "torvalds" => 1024025
  }.freeze

  REPO_ID_BY_NAME = {
    "jmartasek/grafana" => 1152169359,
    "torvalds/linux" => 2325298
  }.freeze

  # -- Raw event (as returned by GET /events) ----------------------------------

  @@event_sequence = 0 # rubocop:disable Style/ClassVars

  def next_event_id
    @@event_sequence += 1
  end

  def github_push_event(
    id: next_event_id.to_s,
    actor_login: "jmartasek",
    actor_github_id: nil,
    repo_name: "jmartasek/grafana",
    repo_github_id: nil,
    push_id: next_event_id,
    ref: "refs/heads/legend-list-alphabetical-sort",
    head: "7c98a1af487ccf269b66d544022230fadd42fc8b",
    before: "a076fed3c63050fa1fd39fa37c286f47c21a4015",
    created_at: "2026-02-07T19:32:17Z"
  )
    actor_github_id ||= USER_ID_BY_LOGIN.fetch(actor_login, 14291370)
    repo_github_id  ||= REPO_ID_BY_NAME.fetch(repo_name, 1152169359)

    {
      "id" => id.to_s,
      "type" => "PushEvent",
      "actor" => {
        "id" => actor_github_id,
        "login" => actor_login,
        "display_login" => actor_login,
        "gravatar_id" => "",
        "url" => "https://api.github.com/users/#{actor_login}",
        "avatar_url" => "https://avatars.githubusercontent.com/u/#{actor_github_id}?"
      },
      "repo" => {
        "id" => repo_github_id,
        "name" => repo_name,
        "url" => "https://api.github.com/repos/#{repo_name}"
      },
      "payload" => {
        "repository_id" => repo_github_id,
        "push_id" => push_id,
        "ref" => ref,
        "head" => head,
        "before" => before
      },
      "public" => true,
      "created_at" => created_at
    }
  end

  # -- Bot event helper --------------------------------------------------------

  def github_bot_push_event(
    id: next_event_id.to_s,
    actor_github_id: 41898282,
    actor_login: "github-actions[bot]",
    repo_github_id: 1152169359,
    repo_name: "jmartasek/grafana",
    push_id: next_event_id,
    ref: "refs/heads/main",
    head: "abc123",
    before: "def456",
    created_at: "2026-02-07T20:00:00Z"
  )
    github_push_event(
      id:,
      actor_github_id:,
      actor_login:,
      repo_github_id:,
      repo_name:,
      push_id:,
      ref:,
      head:,
      before:,
      created_at:
    )
  end

  # -- GitHub Users API response (GET /users/:login) ---------------------------

  def github_user_api_response(id: 14291370, login: "jmartasek")
    {
      "login" => login,
      "id" => id,
      "node_id" => "MDQ6VXNlcjE0MjkxMzcw",
      "avatar_url" => "https://avatars.githubusercontent.com/u/#{id}?v=4",
      "gravatar_id" => "",
      "url" => "https://api.github.com/users/#{login}",
      "html_url" => "https://github.com/#{login}",
      "followers_url" => "https://api.github.com/users/#{login}/followers",
      "following_url" => "https://api.github.com/users/#{login}/following{/other_user}",
      "gists_url" => "https://api.github.com/users/#{login}/gists{/gist_id}",
      "starred_url" => "https://api.github.com/users/#{login}/starred{/owner}{/repo}",
      "subscriptions_url" => "https://api.github.com/users/#{login}/subscriptions",
      "organizations_url" => "https://api.github.com/users/#{login}/orgs",
      "repos_url" => "https://api.github.com/users/#{login}/repos",
      "events_url" => "https://api.github.com/users/#{login}/events{/privacy}",
      "received_events_url" => "https://api.github.com/users/#{login}/received_events",
      "type" => "User",
      "user_view_type" => "public",
      "site_admin" => false,
      "name" => nil,
      "company" => nil,
      "blog" => "",
      "location" => nil,
      "email" => nil,
      "hireable" => nil,
      "bio" => nil,
      "twitter_username" => nil,
      "public_repos" => 14,
      "public_gists" => 0,
      "followers" => 4,
      "following" => 2,
      "created_at" => "2015-09-15T09:42:15Z",
      "updated_at" => "2026-01-05T07:37:45Z"
    }
  end

  # -- GitHub Repos API response (GET /repos/:owner/:name) ---------------------

  def github_repo_api_response(
    id: 1152169359,
    name: "grafana",
    full_name: "jmartasek/grafana",
    description: "The open and composable observability and data visualization platform. " \
                 "Visualize metrics, logs, and traces from multiple sources like Prometheus, " \
                 "Loki, Elasticsearch, InfluxDB, Postgres and many more. "
  )
    owner_login = full_name.split("/").first

    {
      "id" => id,
      "node_id" => "R_kgDORKy1jw",
      "name" => name,
      "full_name" => full_name,
      "private" => false,
      "owner" => {
        "login" => owner_login,
        "id" => 14291370,
        "node_id" => "MDQ6VXNlcjE0MjkxMzcw",
        "avatar_url" => "https://avatars.githubusercontent.com/u/14291370?v=4",
        "gravatar_id" => "",
        "url" => "https://api.github.com/users/#{owner_login}",
        "html_url" => "https://github.com/#{owner_login}",
        "type" => "User",
        "user_view_type" => "public",
        "site_admin" => false
      },
      "html_url" => "https://github.com/#{full_name}",
      "description" => description,
      "fork" => true,
      "url" => "https://api.github.com/repos/#{full_name}",
      "forks_url" => "https://api.github.com/repos/#{full_name}/forks",
      "keys_url" => "https://api.github.com/repos/#{full_name}/keys{/key_id}",
      "branches_url" => "https://api.github.com/repos/#{full_name}/branches{/branch}",
      "tags_url" => "https://api.github.com/repos/#{full_name}/tags",
      "commits_url" => "https://api.github.com/repos/#{full_name}/commits{/sha}",
      "git_commits_url" => "https://api.github.com/repos/#{full_name}/git/commits{/sha}",
      "issues_url" => "https://api.github.com/repos/#{full_name}/issues{/number}",
      "pulls_url" => "https://api.github.com/repos/#{full_name}/pulls{/number}",
      "releases_url" => "https://api.github.com/repos/#{full_name}/releases{/id}",
      "created_at" => "2026-02-07T13:21:51Z",
      "updated_at" => "2026-02-07T13:21:51Z",
      "pushed_at" => "2026-02-07T19:37:14Z",
      "git_url" => "git://github.com/#{full_name}.git",
      "ssh_url" => "git@github.com:#{full_name}.git",
      "clone_url" => "https://github.com/#{full_name}.git",
      "svn_url" => "https://github.com/#{full_name}",
      "homepage" => "https://grafana.com",
      "size" => 1504614,
      "stargazers_count" => 0,
      "watchers_count" => 0,
      "language" => nil,
      "has_issues" => false,
      "has_projects" => true,
      "has_downloads" => true,
      "has_wiki" => false,
      "has_pages" => false,
      "has_discussions" => false,
      "forks_count" => 0,
      "mirror_url" => nil,
      "archived" => false,
      "disabled" => false,
      "open_issues_count" => 0,
      "license" => {
        "key" => "agpl-3.0",
        "name" => "GNU Affero General Public License v3.0",
        "spdx_id" => "AGPL-3.0",
        "url" => "https://api.github.com/licenses/agpl-3.0",
        "node_id" => "MDc6TGljZW5zZTE="
      },
      "allow_forking" => true,
      "is_template" => false,
      "web_commit_signoff_required" => false,
      "topics" => [],
      "visibility" => "public",
      "forks" => 0,
      "open_issues" => 0,
      "watchers" => 0,
      "default_branch" => "main",
      "network_count" => 0,
      "subscribers_count" => 0
    }
  end

  # -- WebMock stubs with visible URLs -----------------------------------------
  #
  #   stub_github_user_api("jmartasek", id: 14291370)
  #     → stubs GET https://api.github.com/users/jmartasek
  #
  #   stub_github_repo_api("jmartasek/grafana", id: 1152169359)
  #     → stubs GET https://api.github.com/repos/jmartasek/grafana

  def stub_github_user_api(login, id: nil)
    id ||= USER_ID_BY_LOGIN.fetch(login, 14291370)
    url  = "https://api.github.com/users/#{login}"
    body = github_user_api_response(id: id, login: login)

    stub_request(:get, url)
      .to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })
  end

  def stub_github_repo_api(full_name, id: nil, description: nil)
    id ||= REPO_ID_BY_NAME.fetch(full_name, 1152169359)
    url  = "https://api.github.com/repos/#{full_name}"
    name = full_name.split("/").last
    desc = description || "The open and composable observability and data visualization platform."
    body = github_repo_api_response(id: id, full_name: full_name, name: name, description: desc)

    stub_request(:get, url)
      .to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })
  end

  # -- Process events through EventsProcessor ---------------------------------
  # Ensures enricher tests use rows that match real processor output,
  # not hand-crafted hashes.
  #
  #   rows = processed_rows_from(github_push_event, github_push_event(id: "2"))

  def processed_rows_from(*events)
    GithubEvents::EventsProcessor.run(events: events).rows
  end
end
