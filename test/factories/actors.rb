FactoryBot.define do
  factory :actor do
    github_id { 14291370 }
    login { "jmartasek" }
    url { "https://api.github.com/users/jmartasek" }
    data { {} }

    trait :jmartasek do
      # default values — explicit trait for readability
    end

    trait :torvalds do
      github_id { 1024025 }
      login { "torvalds" }
      url { "https://api.github.com/users/torvalds" }
    end
  end
end
