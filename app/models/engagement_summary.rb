# What one voter has marked on a page of records, and how many visitors favorite or follow each,
# loaded with two queries however many records the page shows.
class EngagementSummary
  def initialize(records, voter)
    @records = Array(records)
    @voter = voter
  end

  def engagement(record, kind)
    own[[ record.class.polymorphic_name, record.id, kind.to_s ]]
  end

  def marked?(record, kind)
    engagement(record, kind).present?
  end

  def count(record, kind)
    counts.fetch([ record.class.polymorphic_name, record.id, kind.to_s ], 0)
  end

  private

  def own
    @own ||= own_engagements.index_by { [ it.engageable_type, it.engageable_id, it.kind ] }
  end

  def own_engagements
    return [] unless @voter && @records.any?

    @voter.engagements.for_records(@records).to_a
  end

  def counts
    @counts ||= @records.any? ? Engagement.for_records(@records).where(kind: Engagement::PUBLIC_KINDS).group(:engageable_type, :engageable_id, :kind).count : {}
  end
end
