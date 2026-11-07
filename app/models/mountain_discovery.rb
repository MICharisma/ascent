class MountainDiscovery
  RECENT_ACTIVITY_WINDOW = 7.days

  def initialize(races, now: Time.current)
    @races = races
    @recent_since = now - RECENT_ACTIVITY_WINDOW
  end

  def races
    candidates = Candidacy.not_from_primaries.still_running.where(participation: "active")
      .group(:race_id).having("COUNT(DISTINCT citizen_id) >= 2").select(:race_id, "COUNT(DISTINCT citizen_id) AS candidate_count")
    votes = VoterRaceBaseline.group(:race_id).select(:race_id, "COUNT(*) AS vote_count")
    recent_saves = VoterRaceBaseline.where(updated_at: @recent_since..).select(:race_id, :voter_id)
    recent_ratings = Rating.joins(:candidacy)
      .joins("INNER JOIN voter_race_baselines ON voter_race_baselines.voter_id = ratings.voter_id AND voter_race_baselines.race_id = candidacies.race_id")
      .where(updated_at: @recent_since..).select("candidacies.race_id", "ratings.voter_id")
    activity = VoterRaceBaseline.from("mountain_recent_activity AS voter_race_baselines").group(:race_id)
      .select(:race_id, "COUNT(DISTINCT voter_id) AS voter_count")
    prominent_offices = Office.national.or(Office.where(position_id: Position.where(entity_code: "POSITION-GOVERNOR")))
    prominence = "CASE WHEN mountain_prominent_offices.id IS NOT NULL THEN 1 ELSE 0 END"
    score = "LN(1 + COALESCE(mountain_votes.vote_count, 0)) + 2 * LN(1 + COALESCE(mountain_activity.voter_count, 0)) + 2 * (#{prominence})"

    @races.with(mountain_candidates: candidates, mountain_votes: votes,
      mountain_recent_activity: [ recent_saves, recent_ratings ], mountain_activity: activity,
      mountain_prominent_offices: prominent_offices.select(:id))
      .joins("INNER JOIN mountain_candidates ON mountain_candidates.race_id = races.id")
      .joins("LEFT JOIN mountain_votes ON mountain_votes.race_id = races.id")
      .joins("LEFT JOIN mountain_activity ON mountain_activity.race_id = races.id")
      .joins("LEFT JOIN mountain_prominent_offices ON mountain_prominent_offices.id = races.office_id")
      .select("races.*, mountain_candidates.candidate_count AS mountain_candidate_count",
        "COALESCE(mountain_votes.vote_count, 0) AS saved_mountain_count",
        "COALESCE(mountain_activity.voter_count, 0) AS recent_mountain_count",
        "(#{prominence}) = 1 AS nationally_prominent")
      .reorder(Arel.sql("#{score} DESC, races.id ASC"))
  end
end
