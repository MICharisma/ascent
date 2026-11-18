# Citizen identity rename

`Citizen` replaces the public `Person` identity model. Its table is `citizens`, and each Candidacy references it through `citizen_id`. Public profiles and directory pages use `/citizens`; forms use `citizen` and `citizen_id` parameters. The old `/people` routes are removed.

`Voter` remains the account model. The rename adds no nationality, voting eligibility, or verification requirement. Mock-election candidates remain fictional Citizens. Existing profile permissions, name fields, candidate ordering, and primary-candidate deduplication are unchanged.

## Database compatibility

`20261107010000_rename_people_to_citizens.rb` renames the table, candidacy foreign key, and indexes. Historical migrations remain intact. The structural migration is reversible.

`20261110173000_convert_stored_person_types.rb` changes persisted polymorphic class references from `Person` to `Citizen`. It covers channels, endorsements, engagements, image placements, entity codes, Active Storage attachments, jurisdictions, and rule source links.

`20261110173100_reissue_citizen_codes.rb` issues `CITIZEN-` preferred codes and keeps every issued `PERSON-` code as an alias of the same record. It refuses to claim a code that belongs to another record. Its reverse restores legacy preferences for converted records and retains the published Citizen codes as aliases.

Back up an existing database and rehearse the pending migrations against a restored copy before release. Verify citizen IDs, candidacy links, channel owners, account and rating counts, and legacy-code resolution. Run the migrations with application writers stopped because the old and new code require different column names. Resume service with the Citizen build after migration succeeds. A reset and reseed is not required.

## Seed contract

Manifests define `type: Citizen`. Candidacies use `references.citizen` or inherited `scope.citizen`. Local identity codes start with `CITIZEN-`, and qualified codes start with `MIC-ASC-CITIZEN-`. Issued usernames and disambiguators stay unchanged, including usernames that contain the surname Person. Bare-name references retain the existing uniqueness requirement. The importer rejects old `Person` definitions and `person` references.

The simulated-data seeder reads `db/seeds/simulated/data/citizens.yml`. Source ballot rows retain their printed names, party labels, and evidence.

Regenerate ballot manifests through `Seeds::BallotManifestConverter`, then regenerate the importer contract, published schemas, and entity catalog. The data repository's [schema instructions](../db/seeds/ascent_seed_data/schemas/README.md) and [contribution guide](../db/seeds/ascent_seed_data/CONTRIBUTING.md) describe the owning tools. Full catalog validation and an import replay must pass before the seed phase is complete.

## Rizz boundary

Ascent installs the pinned private `rizz-client` gem through its Gemfile. Its adapter is `Rizz::Ascent::CitizenRecord`; Rizz's general person-import API and `person` identity-binding namespace remain unchanged. `RizzCitizenSync` imports real citizens, adopts their Rizz codes, and retains the Ascent codes as aliases. Fictional citizens are excluded, and Voter accounts are not imported.

After deploying the configured consumer, run `bin/rails rizz:sync_citizens`. It imports citizens and fetches names for those successfully placed. Names whose column shapes Rizz cannot read are held until Ascent supplies a current `CitizenNameReading`. Run `bin/rails rizz:read_overflow` with `TYPESAFE_API_KEY` to propose those readings, then `bin/rails rizz:review_names` to send uncertain readings to Rizz reviewers and retrieve their decisions. Rerun synchronization after readings are settled.

`bin/rails rizz:refresh_names` revalidates the complete name cache. Held names, identity reviews, and possible local duplicates remain recorded in `rizz_syncs` for resolution.

The sibling Rizz integration workspace exercises persisted Ascent records and its name projection against a separate Rizz HTTP server. See [Railway staging deployment](railway-staging.md) for service configuration and rollout checks.
