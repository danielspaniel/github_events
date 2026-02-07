class GithubEvent < ApplicationRecord
  belongs_to :actor, optional: true
  belongs_to :repository, optional: true

  validates :event_id, presence: true, uniqueness: true
  validates :event_type, presence: true
  validates :data, presence: true

  validates :event_type, inclusion: { in: %w[PushEvent] }
  validates :repository_identifier, presence: true
  validates :push_identifier, presence: true
  validates :ref, presence: true
  validates :head, presence: true
  validates :before, presence: true
  
end

