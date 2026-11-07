# Issues, stances, and campaign communications

A proposed design, not yet implemented. It extends the [entity-code plan](entity_code_plan.md) to the issue library, candidates' stances, and the campaign platforms and communications (video, social media, websites) that show where those stances come from. Coded records let other organizations donate seeds through pull requests to the seed-data repository: a contribution refers to existing candidacies, races, and citizens by their codes, adds its own records, and is checked before it is merged.

## Current state

- **Topic → Issue → Approach** is the issue library. Each record has only a title and description. This matches the entity-code decision record, which treats an Approach as "a descriptive library concept, not a campaign position." Phase 1 gave these records codes and moved them from Ruby seeders into the seed-data repository.
- **Stance** joins a Candidacy to an Approach with an `explanation`, a free-text `priority_level`, and a free-text `evidence_links`. It has no code, no date, no source, and no constraint against two stances on the same Approach. The seeded stances are fictional and attach only to mock elections; their evidence is prose, not links.
- **Stance shifts** ([stance_shift_implementation.md](stance_shift_implementation.md)) are designed but not built. A shift is a precise intention within a stance, such as narrowing a code or changing enforcement. It sits under Stance and is unaffected by this design.
- **Policy, OfficialCode, and the `Rule` models** cover enacted law. Until Phase 1, `Policy.status` was a string column mapped by an integer enum, so `PolicySeeder` failed and the simulated seed layer stopped there.
- **Campaign communications are not modeled.** The approval-voting PRD calls for ratings of videos, texts, websites, and photos; curated multimedia; and guided stance templates. Only `Candidacy.platform_summary` holds platform text today.

## Design

The entity-code design's sourced claim is the model: a subject, a predicate, an object, and evidence (a URL, a publication date, and a supporting passage). Here a stance claims that a candidacy supports an approach, and each piece of evidence ties the stance to something the campaign said.

| Record | Code | Holds |
| --- | --- | --- |
| Topic | `TOPIC-HOUSING` | A broad subject |
| Issue | `ISSUE-HOUSING-AFFORDABILITY` | A problem within a topic |
| Approach | `APPROACH-HOUSING-AFFORDABILITY-INCLUSIONARY_ZONING`, or with a jurisdiction path when tied to one place: `APPROACH-USA-NY-CRYPTO_MINING-TIME_LIMITED_PERMIT_MORATORIUM` | A proposed response, described without reference to any candidate |
| **Channel** | `CHANNEL-{platform token}-{handle}`, with the tokens `WEB`, `YT`, `IG`, `TT`, `X`, `BSKY`, `FB`, and `THR`: `CHANNEL-IG-{handle}` | One account on one platform (YouTube, Instagram, TikTok, X, Bluesky, Facebook, a campaign website), its owner (a Citizen, Party, or campaign), and whether it is official |
| **Communication** | `COMMUNICATION-{channel path}-{date}-{slug}`, for example `COMMUNICATION-YT-{handle}-2026_10_02-DEBATE_OPENING` | One video, post, ad, speech, debate clip, interview, platform page, or mailer: its kind, publication date, canonical URL, platform ID, an archived copy's URL, and the candidacies it features |
| Stance | `STANCE-{candidacy path}-{approach path}` | A candidacy's position on an approach; one per candidacy and approach |
| **StanceEvidence** | `EVIDENCE-{stance path}-{communication path}` | Which communication supports the stance, a short quote or a timestamp within a video, and its relation: `states`, `clarifies`, or `contradicts` |

Decided October 21, 2026: **each piece of evidence is its own coded record.** Ballot lines are listed inside their Candidacy because one official source supplies them. Evidence comes from many contributors over time. If it were listed inside the Stance, two pull requests adding evidence to the same stance would each redefine the Stance, and the importer would reject the differing definitions as contradictory. Separate records referring to the Stance by its code let contributions accumulate.

Further rules:

- **Communication codes** are built from the channel, date, and a short slug because many platform IDs are case-sensitive (YouTube video IDs, for example) while codes are uppercase. The platform ID and canonical URL are attributes, and the canonical URL is the natural key that matches an existing record.
- **A campaign platform** is a Communication of kind `platform`, such as a website's issues page or a PDF, which stances cite like any other communication.
- **Verified channels and usernames:** a channel verified as a citizen's own can supply their username. A verified Instagram handle replaces a provisional username, and the old Citizen code becomes an alias.
- **Changing positions:** evidence is dated, and a `contradicts` relation records a later statement that departs from the stance. Whether a reversal becomes a new Stance or an updated one is an open decision.
- **Content ratings are voter data.** Voters' ratings of communications (the PRD's content ratings) are user history, kept apart from seeds like ratings and baselines.

## Concepts, values, beliefs, principles, and stances

Discussed October 21, 2026, while reviewing whether the issue library needs a wider layer to explain why a candidate holds a position. Decision: keep the current design (Topic, Issue, Approach, Stance). These notes record the terms for a later Value layer.

- **Concept:** the broadest term, for anything in the library. Topics, issues, approaches, and values are all concepts. It names a category, not a model.
- **Value:** a shared, abstract good that motivates positions across issues, such as liberty, fairness, environmental protection, or local control. Values cut across the Topic → Issue → Approach hierarchy instead of sitting above it: one value can motivate approaches to mining, zoning, and transit, and an approach can advance some values while trading off others. Two candidates can share a value and choose opposite approaches, a distinction a values layer would let Ascent show. If modeled, a Value would be a small coded library (`VALUE-LIBERTY`), linked to approaches by attributed records, because saying an approach advances or trades off a value is a judgment, not a fact.
- **Belief:** a citizen's own conviction. A belief belongs to someone, so it is not a library record. A candidate's commitment to a value is a sourced fact about that candidate, recorded like a stance.
- **Principle:** a value stated as a rule of conduct ("government closest to the citizens governs best"). It reads as normative, so it suits a candidate's stated rationale better than the shared library.
- **Stance:** a candidacy's position on one approach: concrete, specific to the candidacy, and checkable against evidence. A stance says what a candidate would do, not why. Stance evidence can record the value or principle a candidate invoked, which is the candidate-level link to a future values layer.

Vocabulary caution: labeling an approach with values is where Ascent could look partisan. A future values layer should use an established vocabulary, such as Moral Foundations Theory (care, fairness, loyalty, authority, sanctity, liberty) or Schwartz's basic values; allow several attributed framings; and show trade-offs alongside benefits.

## Topics and areas of concern

Decided October 21, 2026: **AreaOfConcern stays separate from Topic.** Topics organize the campaign issue library; areas of concern classify enacted policy by the domain it regulates (`policy_domain`, `regulatory_scope`). One topic often affects several areas: housing policy touches land use, finance, and public health. Some classifications will be ambiguous, but the library is curated seed content rather than user-generated, so ambiguity is resolved during review.

## Donated seeds

- Contributions are manifests in the seed-data repository that refer to existing codes and add Topics, Issues, Approaches, Channels, Communications, Stances, and StanceEvidence.
- The manifest `source` block records the contributing organization, the source URL, and the capture date. Stances and evidence require a source; reference data in general does not, as the entity-code decision record allows.
- The importer creates missing records, never overwrites reviewed values, and reports differences as conflicts for maintainers.
- Pull requests are checked with `seed_library:validate`, which rejects unknown types and fields, contradictory definitions, and code collisions. A published contract of allowed types and fields, ported from AthleteAce's `Seeds::CatalogContract`, would let contributors validate before submitting.
- **Content policy:** links, short quotes, and timestamps only. No rehosted video or full transcripts. A deleted or edited post keeps its archived copy and is marked as removed or edited.
- Simulated stances remain limited to mock elections, so fictional positions are never attached to real candidates.

## Open decisions

1. How a channel is verified as official: a link from the campaign's website, the platform's verification badge, or a maintainer's review.
2. Whether a reversal of position creates a new Stance or is recorded as `contradicts` evidence on the existing one.
3. Who maintains the issue library, and whether it aligns with an outside taxonomy through aliases.
4. Where contributor attribution is stored beyond the manifest: on each record, or in an import ledger like Spindrift's.
5. How long a quote may be, and which archive service supplies archived copies.

## Phases

1. **Issue library codes (done October 21, 2026).**
   - `AddEntityCodesToIssueLibrary` adds `entity_code` to topics, issues, and approaches. The importer accepts all three types, adopting an existing record by its title within its parent.
   - The 10 topics, 40 issues, and 120 approaches formerly written in `TopicSeeder`, `IssueSeeder`, and `ApproachSeeder` are now `manifests/library/issues.yml` in the seed-data repository, coded `TOPIC-{topic}`, `ISSUE-{topic}-{issue}`, and `APPROACH-{topic}-{issue}-{approach}` from their titles. The three seeders are removed, and the library loads with the reference seed layer.
   - `Policy.status` keeps its string column, with an enum whose values are the words `pending`, `enacted`, and `repealed`; an unknown status fails validation instead of raising. The seeder's `active` statuses became `enacted` (each has a past enacted date), and `proposed` and `under_review` became `pending`, as the policy factory already used them. The policy form offers a status menu, and the simulated seed layer now runs to completion with all 19 policies.
2. **Communications and evidence (done October 21, 2026).**
   - `AddCommunicationsAndStanceEvidence` creates `channels` (platform, handle, URL, official flag, and an owner that is a Citizen, Party, or Candidacy), `communications` (kind, title, publication date, canonical URL, platform ID, archived URL, availability of `available`, `edited`, or `removed`, summary, duration, and language), `communication_features` (the candidacies a communication features), and `stance_evidences` (relation, quote, and offset in seconds). Stances gain `entity_code` and a unique index on candidacy and approach; the migration refuses to run while duplicate stances exist.
   - Quotes are limited to 300 characters, provisionally, until open decision 5 is settled.
   - The importer accepts Stance, Channel, Communication, and StanceEvidence. It recognizes existing records by natural key: a stance by candidacy and approach, a channel by platform and handle, a communication by URL, and evidence by stance and communication. A channel's owner is resolved by its registered code or by the code's type marker and must be a Citizen, Party, or Candidacy. A communication lists its `featured_candidacies` as candidacy codes; like ballot lines, they are added and never removed.
   - A two-file fixture with a fictional candidate and `example.com` addresses proves that a second contributor can add evidence to an existing stance without redefining it, and that re-importing both files changes nothing. The manifest `source` block carries the contributing organization as `contributor`.
3. **Contribution workflow (contract and guide done October 21, 2026).**
   - The seed-data repository is public at [MICharisma/ascent_seed_data](https://github.com/MICharisma/ascent_seed_data).
   - `Seeds::CatalogContract`, ported from AthleteAce, lists the importer's types with their attributes, allowed values (from Rails enums and inclusion validations), nested `ballot_lines` and `featured_candidacies`, and references. `bin/rails seed_library:contract` writes it to `schemas/asc.contract.json` in the seed-data repository, and `CHECK=1` reports drift; a spec fails when the published contract no longer matches the importer.
   - The shared `micharisma_seeders` exporter turns the contract into JSON Schema files in `schemas/v1/`, addressed under `https://raw.githubusercontent.com/MICharisma/ascent_seed_data/main/schemas/v1`. An off-the-shelf validator accepts all 221 existing manifests and fixtures and rejects retired fields, unknown values, and lowercase codes, so contributors can validate without the private `micharisma_seeders` repository. The exporter is on that repository's unmerged `codex/published-seed-schemas` branch; `schemas/README.md` describes regeneration.
   - `CONTRIBUTING.md` in the seed-data repository explains where contributions go (`manifests/contributions/<organization>/`), how to write a manifest and refer to existing codes, the source and content rules, validation, and what happens on merge.
   - Remaining: validate pull requests automatically. JSON Schema validation can run in the public repository's CI without credentials; the fuller `seed_library:validate` check needs an Ascent checkout and access to the private `micharisma_seeders`. Ascent's seed-data submodule now points at the GitHub repository.
4. **Presentation.** Show communications and evidence on candidacy and race pages, and let voters rate communications.
5. **Stance shifts**, as designed in [stance_shift_implementation.md](stance_shift_implementation.md).
6. **Values (deferred).** A coded value library, attributed approach-to-value links, and the values candidates invoke, as described under [Concepts, values, beliefs, principles, and stances](#concepts-values-beliefs-principles-and-stances).
