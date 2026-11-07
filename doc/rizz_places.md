# Rizz place codes

Rizz, MICharisma's naming service, defines the shared codes for countries, states, counties and towns. `bin/rails rizz:sync_places` adopts them in Ascent: each matched record's `entity_code` becomes its Rizz code (such as `MIC-RZZ-SUBDIV-US-IN-ADAMS`), and its Ascent code (`COUNTY-USA-IN-ADAMS`) stays bound in `EntityCode` as an alias. Seed files and links that use the Ascent code keep resolving, and `Seeds::LibraryImporter` keeps an adopted code when it replays them, without binding the Rizz code in Ascent's own catalog.

Seeding never calls Rizz; run the sync as its own step. It needs the `rizz-client` gem from the Rizz repository (`clients/rizz-client`), `RIZZ_ENDPOINT` and `RIZZ_API_TOKEN`.

Every match is by identifier, never by name:

| Ascent record | Matched by | Rizz tier |
| --- | --- | --- |
| Country | ISO 3166-1 code; Ascent's `UK` is ISO `GB` | `CTRY` |
| State | ISO 3166-2 code from country and state (`US-IN`, `CA-ON`) | `DIV` |
| County | FIPS code | `SUBDIV` |
| Municipality | Census place GEOID on its jurisdiction, for incorporated places (class G4110) only | `LOC` |

A municipality's GEOID comes from the TIGER boundary import (`gis:import_tiger` on the PLACE layer), so import boundaries first. Townships, wards and other municipalities without an incorporated-place GEOID keep their Ascent codes, as do districts.

Rizz holds a county and a city on the same land as one place, with the lower tier as an alias. Richmond city, Virginia, the county equivalent, takes `MIC-RZZ-SUBDIV-US-VA-RICHMOND_CITY`, and the municipality takes `MIC-RZZ-LOC-US-VA-RICHMOND`; both name one Rizz place. The task lists places Rizz does not know, and Rizz codes another Ascent record already holds, and leaves them unchanged. A second run changes nothing.
