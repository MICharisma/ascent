# Citizen identity rename

`Citizen` replaces the public `Person` identity model. Its table is `citizens`, and each Candidacy references it through `citizen_id`. Public profiles and directory pages use `/citizens`; forms use `citizen` and `citizen_id` parameters. The old `/people` routes are removed.

`Voter` remains the account model. The rename adds no nationality, voting eligibility, or verification requirement. Mock-election candidates remain fictional Citizens. Existing profile permissions, name fields, candidate ordering, and primary-candidate deduplication are unchanged.

## Database compatibility

`20261107010000_rename_people_to_citizens.rb` renames the table, candidacy foreign key, and indexes. Historical migrations remain intact. The structural migration is reversible.

The migration does not convert stored polymorphic types or existing entity codes. A migrated database can still contain `Person` in channels, endorsements, engagements, image placements, and entity codes. Existing `PERSON-` codes also require conversion before using the new seed contract.

Development and test databases can be rebuilt with the Citizen schema and seeds. Before releasing to an existing staging or production database, choose an explicit reset and reseed or prepare a data conversion. The structural migration alone is insufficient for those databases. Run the schema migration while application writers are stopped because the old and new code require different column names.

## Seed contract

Manifests define `type: Citizen`. Candidacies use `references.citizen` or inherited `scope.citizen`. Local identity codes start with `CITIZEN-`, and qualified codes start with `MIC-ASC-CITIZEN-`. Issued usernames and disambiguators stay unchanged, including usernames that contain the surname Person. Bare-name references retain the existing uniqueness requirement. The importer rejects old `Person` definitions and `person` references.

The simulated-data seeder reads `db/seeds/simulated/data/citizens.yml`. Source ballot rows retain their printed names, party labels, and evidence.

Regenerate ballot manifests through `Seeds::BallotManifestConverter`, then regenerate the importer contract, published schemas, and entity catalog. The data repository's [schema instructions](../db/seeds/ascent_seed_data/schemas/README.md) and [contribution guide](../db/seeds/ascent_seed_data/CONTRIBUTING.md) describe the owning tools. Full catalog validation and an import replay must pass before the seed phase is complete.

## Rizz boundary

The Ascent adapter and integration tests live in the sibling Rizz workspace. Its Ruby adapter becomes `Rizz::Ascent::CitizenRecord`. Rizz's general person-import API and `person` identity-binding namespace remain unchanged. Ascent has no application-owned sync or Rizz-code adoption step.

Rizz's integration checkout uses a locked Ascent revision containing the Citizen schema, models, and regression fixtures. Its isolated integration suite loads that schema and exercises `Rizz::Ascent::CitizenRecord` against the Rizz HTTP server. The Citizen rename requires no Ascent integration patch.
