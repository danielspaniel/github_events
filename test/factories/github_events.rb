FactoryBot.define do
  factory :github_event do
    sequence(:event_id) { |n| n.to_s }
    event_type { "PushEvent" }
    repository_identifier { 507304316 }
    push_identifier { 30474178251 }
    ref { "refs/heads/main" }
    head { "aaaa" }
    before { "bbbb" }
    public { true }
    github_created_at { "2026-02-05T22:20:50Z" }
    data { {} }
  end
end
