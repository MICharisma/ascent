# Which of a citizen's or policy's unrated qualities a voter would likely rate next.
# The provider sees only the curated catalog, the record's public name and type, and how often this
# voter has chosen each quality in Ascent. Ballots, votes, baselines and scores stay out of the request.
class DimensionSuggestions
  def self.provider
    Rails.configuration.x.shared_ratings.suggestion_provider || SharedRatings::LLMProvider.from_env
  end

  def initialize(voter:, rated:)
    @voter, @rated = voter, rated
  end

  def defaults
    eligible
  end

  def call
    result = SharedRatings::Suggestions.new(provider: self.class.provider)
      .call(candidates: candidates, subject: subject, preferences: preferences, defaults: eligible.map(&:key))
    current = eligible.index_by(&:key)
    { suggestions: result.keys.filter_map { { key: it, label: DimensionRated.quality_name(current[it]) } if current.key?(it) }, source: result.source }
  end

  private

  # Rechecked after the provider answers, so a quality rated meanwhile drops out.
  def eligible
    answered = @voter.dimension_ratings.where(rated: @rated).pluck(:dimension_key)
    @rated.class.rating_dimensions.reject { answered.include? it.key }
  end

  def candidates
    eligible.map { { key: it.key, label: DimensionRated.quality_name(it), question: it.question } }
  end

  def subject
    { type: @rated.class.name, name: @rated.name }
  end

  def preferences
    @voter.dimension_ratings.where(dimension_key: eligible.map(&:key)).group(:dimension_key).count
      .map { |key, times| { key: key, times_chosen: times } }
  end
end
