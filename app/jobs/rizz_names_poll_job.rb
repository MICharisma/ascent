# Reads Rizz's event feed every few minutes and refetches the names it
# changed. Does nothing unless RIZZ_ENDPOINT is set.
class RizzNamesPollJob < ApplicationJob
  def perform
    RizzNames.new.poll if RizzNames.enabled?
  end
end
