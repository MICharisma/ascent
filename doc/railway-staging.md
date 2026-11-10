# Deploy Ascent staging with Rizz

Use the Ascent Railway project's `staging` environment and `begin.ascent.ing`.
Deploy the reviewed `codex/railway-staging` branch from `MICharisma/ascent` with
the repository Dockerfile. It fetches the seed catalog and shared importer at
the submodule commits recorded in the Dockerfile.

Keep the existing primary, cache, queue, and cable database URLs and upload
volume. Rails runs with `RAILS_ENV=staging`; the public domain routes to port 80,
and `/up` is the health check.

Store these settings in Doppler `ascent/stg` and copy them to the web service:

| Variable | Value |
|---|---|
| `BUNDLE_GITHUB__COM` | `x-access-token:<read-only Rizz repository token>` |
| `RIZZ_ENDPOINT` | `https://rizz.mikeymicrophone.fun` |
| `RIZZ_SCOPE` | `ascent.staging` |
| `RIZZ_API_TOKEN` | A separate Ascent staging client credential |
| `TYPESAFE_API_KEY` | The configured key for Jev name readings |
| `SKIP_SEEDS` | `1` during deployment |

Provision that client in Rizz using `rizz:provision_client`, with
`RIZZ_SOURCE_KEY=ascent:people`, `RIZZ_CLIENT_NAME=Ascent staging`, and
`RIZZ_PUBLIC_FIGURES=1`. Run `rizz:embed_origins` for the same scope with
`EMBED_ORIGINS=https://begin.ascent.ing`. Keep the identity-authority credential
separate from the consumer credential.

## Migrate existing staging data

Back up the primary database and rehearse the [Citizen compatibility
migrations](citizen-migration.md#database-compatibility) against the backup.
Stop the old web deployment before applying the upgrade. Its writers use the
old table and column names. The new deployment's `./bin/rails db:prepare`
pre-deploy command applies the schema and data migrations.
`SKIP_SEEDS=1` prevents automatic reference imports during database preparation.
Run `SKIP_SEEDS=0 bin/rails db:seed` explicitly when a reference catalog update
is intended.

Require the exact deployment to reach `SUCCESS`, then check `/up`, a Citizen
profile, a candidacy, and the mountain pages. Verify that legacy `PERSON-` codes
resolve to the same Citizen IDs, and that existing channel owners, Voter
accounts, and ratings remain intact.

Run `bin/rails rizz:sync_citizens` to import real citizens and cache their names.
Inspect the reported states: failed imports require repair; held names need a
current reading through `rizz:read_overflow` and, when uncertain,
`rizz:review_names`. Rerun synchronization after settling those readings. Identity reviews
and possible local duplicates require decisions before those records can finish
adopting Rizz codes. Verify a synced Citizen's page and code alias after import.
The recurring jobs poll name changes every five minutes and revalidate names
at 4am each day.
