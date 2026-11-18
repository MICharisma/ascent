# Election and Race schema

`SeparateRacesFromElections` follows the jurisdiction migrations. The models and factories now use the split described below. Controllers, routes, views, and seeds use the split. The migration does not create Race records from existing Elections or convert existing references. Existing dependent records require conversion or removal first.

## Ownership

| Election | Race |
| --- | --- |
| Jurisdiction and Year references | Election and Office references |
| Required name and election date | Candidacies, with their ratings and stances |
| Optional kind, such as primary, general, or special | One current baseline per voter, plus baseline history |
| Optional early-voting start and end dates | Race-specific approval totals and results |
| Mock and historical flags | Race-specific description and status |
| Event-wide description and status | |

The existing `elections` table retains Year, status, description, mock and historical flags, and timestamps. It gains a required Jurisdiction reference and name, an optional kind, and optional early-voting dates. Its Office reference is removed. Election date becomes required.

`races` is a new table with required Election and Office references, status defaulting to `upcoming`, an optional description, and timestamps. It has its own status because one Race can be cancelled or completed while other Races in its Election continue. It inherits its calendar and mock/historical context from Election; this schema adds no Race-level overrides.

The schema permits an Election with no Races while its contests are being assembled, or with one Race. Sharing a jurisdiction and date does not merge Elections. There is no uniqueness constraint on that combination, so separate events can occur on the same day. Primary and general events are separate Elections, with their own Races.

## Candidacies and baselines

`candidacies.race_id` replaces `candidacies.election_id`. Citizen, candidacy status, party affiliation, announcement date, and platform summary remain on Candidacy. Ratings, rating archives, and stances retain their Candidacy references. Candidacy exposes its Election and Office through Race. Citizen exposes distinct Races and Elections through candidacies.

`voter_election_baselines` becomes `voter_race_baselines`, and `voter_election_baseline_archives` becomes `voter_race_baseline_archives`. Both receive required Race references in place of Election references. A unique index permits one current baseline per voter and Race. The same voter can set different baselines for different Races within one Election. Archive records can repeat for the same voter and Race.

`Race` now owns approval aggregation, winner selection, and result summaries. Office's current-office-holder lookup uses its most recent completed Race. `Rating.approved?` reads the voter's `VoterRaceBaseline` for its Candidacy's Race. A rating must remain strictly above the baseline to count. `Rating.for_race(race)` filters one contest; `Rating.for_election(election)` includes ratings from every Race in the event.

Baseline value changes and deletions create VoterRaceBaselineArchive records. Destroying a Race removes its candidacies, ratings, baselines, and baseline archives while leaving its Election and sibling Races in place. Removing a voter baseline alone preserves its archive history.

Race aggregation currently includes every participant with a Race baseline, without residency filtering. `results_summary[:total_registered_voters]` counts baseline records, not verified voter registrations. Consumers must account for this until residency and eligibility classification is implemented.

## Calendar boundaries

The early-voting fields store jurisdiction-local dates, not daily opening hours. Either date may remain unknown. When both are present, the start must be on or before the end. Neither may be later than Election date. Equality with Election date is allowed; the constraint does not impose an extra statutory cutoff.

The migration does not add registration deadlines, party eligibility, a general rules document, or per-Race calendar overrides.

## Model boundaries and remaining work

The Race index accepts combined GET filters for search (`q`), State (`state_id`), election year (`year`), Race status (`status`), and Election kind (`kind`). Changing a dropdown submits the filters through Turbo Drive. Text search submits with Enter or Apply. Search matches Office position titles, Election names, Race descriptions, and candidate names. State filtering follows the Office's Jurisdiction through the State's explicitly linked descendants; it requires populated Jurisdiction parent links. Filters remain in pagination URLs. Applying new filters starts at page one, and Clear removes the filters while preserving an Office or Election scope. Hidden Races remain excluded for the current voter. The page shows the filtered result count.

- Race validates that its Office represents its Election's Jurisdiction. Election and Office also reject jurisdiction changes that would invalidate attached Races. Foreign keys alone do not enforce this cross-record match for direct SQL writes.
- Election and Race accept `upcoming`, `active`, `completed`, and `cancelled` statuses independently. Changing one does not propagate a status change to the other. More detailed certification or result states remain undecided.
- Define multi-seat and tied-result behavior before changing the existing single-winner calculation. This migration adds no seat count or tie-breaking rule.
- Implement residency and eligibility classification, including historical participation snapshots, before presenting separate in-district and outside-district totals. Ratings accept outside opinions. The old always-true eligibility method and its Rating validation gate have been removed; this update does not classify opinions or treat them as verified local votes.

The model rename, associations, and model query changes are implemented. Races have their own pages, nested indexes under offices and elections, and the forms for candidacies and baselines select a Race. The mountain voting interface is keyed by Race, because baselines belong to a Race, and lists active Races. The sourced 2026 seeds create one general Election per Jurisdiction on November 3, with a Race for each office and one Candidacy per citizen per Race; fusion party lines are joined in `party_affiliation`. Citizen email, Candidacy announcement date, and Position term length are optional because the official sources do not publish them. Simulated ratings, baselines, and stances attach only to mock elections. The development database has not been migrated.
