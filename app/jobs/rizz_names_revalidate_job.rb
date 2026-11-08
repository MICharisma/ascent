# Refetches every real citizen's names once a day, so a lost event can't
# leave a stale name standing. Does nothing unless RIZZ_ENDPOINT is set.
class RizzNamesRevalidateJob < ApplicationJob
  def perform
    RizzNames.new.revalidate if RizzNames.enabled?
  end
end
