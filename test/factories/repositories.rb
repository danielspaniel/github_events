FactoryBot.define do
  factory :repository do
    github_id { 1152169359 }
    name { "jmartasek/grafana" }
    url { "https://api.github.com/repos/jmartasek/grafana" }
    data { {} }

    trait :grafana do
      # default values — explicit trait for readability
    end

    trait :linux do
      github_id { 2325298 }
      name { "torvalds/linux" }
      url { "https://api.github.com/repos/torvalds/linux" }
    end
  end
end
