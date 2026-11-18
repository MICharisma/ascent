# Quality ratings

A signed-in voter can rate a citizen or a policy on a few curated qualities. These ratings
stand apart from the mountain: they never change a ballot, a baseline, a draft or approval.

| Rated | Key | Question | Low | High |
|---|---|---|---|---|
| Citizen | `ascent.citizen.familiarity` | How well do you know this person? | Unfamiliar | Very familiar |
| Citizen | `ascent.citizen.trustworthiness` | How much do you trust this person? | Distrust | Fully trust |
| Citizen | `ascent.citizen.competence` | How capable is this person at public service? | Incapable | Highly capable |
| Policy | `ascent.policy.effectiveness` | Will this policy achieve its aim? | Ineffective | Very effective |
| Policy | `ascent.policy.fairness` | How fair is this policy to the people it affects? | Unfair | Very fair |
| Policy | `ascent.policy.affects_me` | How much does this policy affect you personally? | Not at all | A great deal |

Each quality uses the shared standard scale from the `shared-ratings` package: −100 to +500,
neutral zero, coarse steps of 10 and fine steps of 1, at definition version 1. `Citizen` and
`Policy` declare their catalogs with `rating_dimension` from the `DimensionRated` concern. A
change in what a quality measures needs a new key or version and a decision about earlier scores.

`dimension_ratings` holds each voter's current score, one per voter, rated record and quality.
The model rejects a quality from another catalog and a score off the scale, and the database
checks the range too. `dimension_rating_revisions` records each rating, change and clearing with
the definition in force at the time. Revisions outlive the rated citizen or policy and are
deleted with the voter. Removing a citizen or policy removes its current ratings without adding
revisions.

## On the page

The citizen and policy pages show a **Your ratings** section. A visitor sees a sign-in prompt and
no scores or averages. A signed-in voter sees a row for each quality they have rated, and opens
the others from the suggestions or the full **Choose a quality** list below. Each row shows the
voters' average and count, visible to signed-in voters only, and individual scores are never shown
to anyone else.

Drag the thumb across for coarse steps, then drag down 32 pixels while holding to switch to fine
steps; moving back within 16 pixels returns to coarse. Release saves once. Escape, a cancelled
pointer or lost capture restores the row. The Coarse and Fine buttons set the step for keys and
drags, and arrows, Page Up, Page Down, Home and End save as they change. An unrated row offers
**Rate neutral** to save zero explicitly, and a rated row offers **Clear**.

`DimensionRatingsController` answers `POST` and `DELETE` on
`/citizens/:citizen_id/dimension_ratings` and `/policies/:policy_id/dimension_ratings` with a Turbo
Stream that redraws the row. It only reaches the signed-in voter's own ratings.

## Suggestions

The picker starts with the voter's unrated qualities in catalog order. **Suggest for me** posts to
`.../dimension_ratings/suggestions`, and `DimensionSuggestions` asks the shared ranker which
unrated qualities to offer, at most three. The provider receives each candidate's key, short name
and question, the record's type and public name, and how many times this voter has chosen each of
those qualities elsewhere in Ascent. Scores, ballots, votes, baselines, account IDs and email
addresses stay out of the request. The answer is rechecked against the voter's current ratings,
and unknown or duplicate keys are dropped. A suggestion request writes nothing.

`SharedRatings::LLMProvider.from_env` configures the model from `RATINGS_SUGGESTION_PROVIDER`
(`openai` or `openrouter`), `RATINGS_SUGGESTION_MODEL`, and `RATINGS_SUGGESTION_API_KEY` or the
provider's usual key, such as the `OPENAI_API_KEY` Ascent already uses for portraits. Without that
configuration, or when the model times out, fails or answers badly, the picker shows the curated
order labelled **Showing default suggestions**. A model's answer is labelled **AI suggestions**.
Specs supply a fake provider through `Rails.configuration.x.shared_ratings.suggestion_provider`.

## Checks

`spec/models/dimension_rating_spec.rb`, `spec/requests/dimension_ratings_spec.rb`,
`spec/requests/dimension_suggestions_spec.rb` and `spec/system/dimension_ratings_spec.rb` cover the
catalog, validation, history, access, averages, the suggestion payload and fallbacks, and the
browser gesture and picker. The integration workspace's `bin/check` runs all four.
