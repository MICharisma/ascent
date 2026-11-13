# Consolidate same-race candidacies after a Citizen merge

This task finds repeated candidacies for the same Citizen and race among Citizens already consolidated through `CitizenMerge`. It preserves different races and primary and general-election candidacies.

Run the commands in the intended Rails environment. Back up the database and rehearse against a restored copy before applying a plan.

1. Generate a preview.

   ```sh
   bin/rails rizz:consolidate_candidacies > tmp/candidacy-consolidation.json
   ```

   A nonzero exit means preview failed. The JSON `groups` list identifies each race, Citizen, survivor, and duplicate IDs. An empty list means no repeated candidacies remain in this scope.

2. Check the survivors. An active on-ballot candidacy takes precedence over a primary-derived off-ballot copy. Otherwise, the task prefers a coded record and then the lowest ID. Conflicting status, announcement date, platform summary, or unsupported participation differences reject the group.

3. Apply the saved plan with an operator name.

   ```sh
   APPLY=tmp/candidacy-consolidation.json PERFORMED_BY=maintainer bin/rails rizz:consolidate_candidacies
   ```

   A nonzero exit means application failed. The entire batch commits in one transaction so primary and general links can move together. Records changed since preview reject the batch. Reapplying a completed plan returns `already_applied` for every group.

4. Sync the combined Citizen records with Rizz.

   ```sh
   bin/rails rizz:sync_citizens
   ```

   This scans all real Citizens and skips unchanged synced records. A nonzero exit or a `failed` result requires investigation.

   Each changed snapshot gets a new revision, including a return to an earlier candidacy list. Retries reuse that revision; a version-conflict retry uses a transport key for its updated request body.

The task moves ratings, rating archives, stances, communication features, official results, channels, engagements, and image placements. Existing stance evidence keeps its stance ID. General-election links to a retired primary candidacy move to the survivor. Draft rating keys move to the survivor, including null values that remove saved ratings.

Identical duplicate child rows are combined. Duplicate image placement order follows the survivor, while the original order stays in the audit. Conflicting ratings, draft values, ballot-line kinds or parties, endorsements, results, or other duplicate child data reject the batch. Two stances for the same approach require separate reconciliation even if their text agrees.

`CandidacyMerge` stores each old ID, survivor ID, operator, and the original records. Old page URLs redirect permanently, and issued entity codes resolve to the survivor. Race result caches are invalidated after application. Existing Rizz bindings remain attached to the same identity.

## Keep seed imports consistent

The data repository defines consolidated seed candidacies in `manifests/contributions/ascent-identity/candidacies.yml`, with old codes as aliases. Candidacies that were created only by an earlier import need no new seed declaration. Derived off-ballot copies need no declaration either: the primary-candidate collector already recognizes the surviving on-ballot candidacy.

The ballot converter omits candidacy definitions covered by the curated file. It retains issued usernames so generated candidacy codes stay stable, and leaves the original sourced ballot rows intact. Validate the seed library, regenerate its catalog, and replay it against the rehearsal database. A successful replay creates no replacement candidacies or primary-derived copies and reports no conflicts.
