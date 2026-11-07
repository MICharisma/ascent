class PublicMountain < ApplicationRecord
  belongs_to :voter
  belongs_to :race

  validates :race_id, uniqueness: { scope: :voter_id }
  validates :snapshot, :preview_png, presence: true

  def refresh!(mountain)
    candidates = mountain.candidacies.active.includes(:citizen).order(:id).map do |candidacy|
      {
        "name" => candidacy.citizen.full_name,
        "rating" => mountain.saved_ratings[candidacy.id],
        "off_ballot" => candidacy.primary_candidacy_id.present?
      }
    end
    self.snapshot = {
      "voter_name" => voter.name,
      "race_name" => race.name,
      "election_name" => race.election.name,
      "baseline" => mountain.saved_baseline,
      "candidates" => candidates
    }
    unless mountain.saved_baseline && candidates.any? { it["rating"].present? }
      errors.add(:base, "Save a baseline and at least one candidate rating before making your mountain public.")
      raise ActiveRecord::RecordInvalid, self
    end

    self.preview_png = MountainPreview.new(snapshot).png
    save!
  end

  def title
    "#{snapshot.fetch("voter_name")}'s mountain"
  end

  def description
    "#{snapshot.fetch("race_name")} · #{snapshot.fetch("election_name")} · Baseline #{snapshot.fetch("baseline")}"
  end
end
