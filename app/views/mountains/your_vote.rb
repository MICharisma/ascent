# frozen_string_literal: true

# Who the voter approves right now, draft included: the count, the approved candidates highest first,
# everyone else, and any primary candidates above the line.
class Views::Mountains::YourVote < Views::ApplicationView
  prop :mountain, Mountain

  def view_template
    SideCard(heading: "Your vote", modifier: "your-vote", id: "your-vote") do
      p(class: "your-vote-count") do
        span(class: "your-vote-number") { approved.size.to_s }
        span(class: "your-vote-of") { "of #{@mountain.ballot_candidacies_count} approved" }
      end
      if approved.any?
        ul(class: "approved-list") { approved.each { approved_item(it) } }
      else
        p(class: "your-vote-empty") { "No one is above your baseline yet. Lower it, or raise a rating, to approve someone." }
      end
      p(class: "not-approved") do
        strong { "Not approved: " }
        plain not_approved_text
      end
      off_ballot_note if @mountain.approved_off_ballot_candidacies.any?
    end
  end

  private

  def approved
    @approved ||= @mountain.approved_candidacies
  end

  def approved_item(candidacy)
    li(class: "approved-item") do
      span(class: "approved-check") { icon(:check) }
      span(class: "approved-name") { candidacy.citizen.display_name }
      span(class: "approved-rating") { @mountain.ratings[candidacy.id].to_s }
    end
  end

  def not_approved_text
    names = @mountain.not_approved_candidacies.map { it.citizen.display_name }
    names.any? ? names.join(", ") : "no one"
  end

  def off_ballot_note
    p(class: "off-ballot-note") do
      strong { "Also above your line, off the ballot: " }
      plain "#{@mountain.approved_off_ballot_candidacies.map { it.citizen.display_name }.join(", ")}. "
      plain "This doesn't change your ballot; it shows shared support in the results."
    end
  end
end
