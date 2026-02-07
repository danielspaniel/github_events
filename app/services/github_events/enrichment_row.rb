module GithubEvents
  EnrichmentRow = Struct.new(:event, :actor, :repo, keyword_init: true) do
    def strip_transients!
      self.actor = nil
      self.repo = nil
    end
  end
end
