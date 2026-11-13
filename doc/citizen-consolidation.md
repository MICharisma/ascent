# Consolidate Citizens already matched by Rizz

Use this task when Rizz assigns several Ascent Citizens to one identity. The task keeps the Citizen with a `synced` RizzSync and moves the `merge_needed` Citizens into it. It does not ask a model to decide identity.

Run the commands in the intended Rails environment. Back up that database before applying a plan. Rehearse against a restored copy first.

1. Generate a preview.

   ```sh
   bin/rails rizz:consolidate_citizens > tmp/citizen-consolidation.json
   ```

   A nonzero exit means preview failed. The JSON contains `groups`, each with a survivor, duplicate IDs, names, and same-race candidacy IDs. An empty `groups` array means there are no pending consolidations.

2. Review the groups and their candidacies. Different offices and primary and general elections remain distinct. Same-race candidacies also retain their IDs and attached records; the report lists them for [separate candidacy consolidation](candidacy-consolidation.md).

3. Apply the saved plan with an operator name.

   ```sh
   APPLY=tmp/citizen-consolidation.json PERFORMED_BY=maintainer bin/rails rizz:consolidate_citizens
   ```

   A nonzero exit means application failed. Each group commits in its own transaction. A changed group is rejected; regenerate its preview after checking the change. Reapplying an unchanged completed plan returns `already_applied` for each group.

4. Sync real Citizens, including the survivors' combined candidacies, and refresh their names. This command scans all real Citizens; unchanged synced records are skipped.

   ```sh
   bin/rails rizz:sync_citizens
   ```

   A nonzero exit or a `failed` or `merge_needed` result requires investigation. Other held or review states may belong to unrelated Citizens.

The merge moves candidacies, channels, endorsements, image placements, and engagements. Identical personal links are combined; conflicting endorsements or engagements reject the group. Conflicting email, birth date, or bio values also reject the group. For a duplicate image placement, the survivor's placement order wins and the original rows remain in the audit. Candidacy IDs, ratings, and ballot lines remain unchanged. Every old code resolves to the surviving Citizen, and old Citizen page URLs redirect to it.

`CitizenMerge` stores the operator, Rizz identity, old Citizen ID, survivor ID, and original rows, including name readings and cached names. Existing Rizz bindings remain attached to the same identity. Apply the consolidation locally before the external Rizz sync so a failed network request can be retried.

## Keep seed imports consistent

The data repository defines confirmed identities in `manifests/contributions/ascent-identity/citizens.yml`. Each entry has one canonical Citizen definition and the earlier issued codes as aliases. Candidacies continue to reference their existing codes.

The ballot converter omits Citizen definitions covered by that file when regenerating ballot manifests. It keeps the candidacy codes and original source rows. After a seed change, validate the manifests, regenerate the data repository's catalog, and replay imports against the rehearsal database. The replay must not recreate merged Citizens or report conflicting attributes for their canonical codes.
