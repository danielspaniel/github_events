class Actor < ApplicationRecord
  validates :github_id, presence: true, uniqueness: true

  has_many :github_events, dependent: :nullify, inverse_of: :actor
end
