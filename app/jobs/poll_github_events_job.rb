class PollGithubEventsJob < ApplicationJob
  queue_as :polling

  def perform(schedule_next: true)
    result = GithubEvents::Poller.new.call
    unless schedule_next
      Rails.logger.info("Skipping next PollGithubEventsJob scheduling (schedule_next=false)")
      return
    end

    interval = result.next_interval_seconds.to_i
    PollGithubEventsJob.set(wait: interval.seconds).perform_later
    Rails.logger.info("Scheduled next PollGithubEventsJob in #{ActiveSupport::Duration.build(interval).inspect}")
  end
end
