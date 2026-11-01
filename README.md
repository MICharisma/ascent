# Ascent
## Approval Voting with Expressive Ballot Control

Election Reform is a popular topic, but one that is complex and difficult to test.  This Rails application, Ascent, is designed to make many types of experiments possible.

### Ascend: Multi-Vote Elections (with conditional votes)

Some people believe that the spoiler effect is basically dominating every aspect of our election system.  By removing the spoiler effect, we might have a less dramatic process, and it might lead to a better government.

The primary goal of this project is therefore to familiarize voters with the possibilities created by a multi-vote approach.

### The Scent: Simulating Complex Preferences

When voters have access to multiple votes, and multiple candidates, you can start to see a lot of detail about their preferences.  The candidates can see those preferences, and factor them into a sophisticated approach of the role they can play.

If we can use the Ascent system to simulate how many groups of voters with different preferences can combine to create a result, it may be useful.

### Assent: Coherence in Policy Conceptualization

Since we give voters a way to opine about specific policy proposals, it is a nudge towards emphasizing the powers that each particular office is truly responsible for.  Perhaps, not every municipal public servant will need to weigh in on the latest "culture war".

A pretty interesting side benefit would be if we established a decent way for citizens to understand what is legal for them, as well as what services they can access.

## Database requirements

The pending [jurisdiction schema](doc/jurisdiction_schema.md) uses PostGIS within PostgreSQL. Install the PostGIS server extension and GEOS before applying it. The subsequent [Election and Race split](doc/election_race_schema.md) separates shared voting events from office contests. Models and factories now use these schemas. The migrations do not convert existing data; controllers, routes, views, and seeds still need updates before applying them to the working application.

## Page copy

Public page copy lives in `config/content`: `home.yml`, `approval_voting.yml`, `faq.yml`, `glossary.yml`, and `supporters.yml`. `PageContent.load` reads these files; the page views retain layout, live metrics, and race previews. Preserve the content keys and interpolation placeholders when editing copy. The Supporters page uses placeholders such as `%{active_elections}` in `footprint.copy`.

Terms of Service text remains in `app/views/pages/terms_of_service.html.erb`.

## Account access

Signup, login, confirmation resend, and password reset share a MICharisma account layout. The design uses plum and cream, Bricolage Grotesque, and Ascent's mountain mark. The form partials live in `app/views/devise/shared`, with scoped `authentication.css` files in the existing Tailwind folders. Accounts remain specific to Ascent.

Google sign-in uses `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET`, or Rails credentials at `google.client_id` and `google.client_secret`. Both values must exist when Rails boots for the Google button to appear. Restart Rails after changing them. Verified Google emails link to an existing Ascent voter with that email; otherwise Google sign-in creates a confirmed voter.

Register the exact callback URL in the Google OAuth web client's authorized redirect URIs:

- Local Rails server on port 3000: `http://localhost:3000/voters/auth/google_oauth2/callback`
- Staging: `https://ascent-staging-staging.up.railway.app/voters/auth/google_oauth2/callback`
- Production: the production HTTPS origin followed by `/voters/auth/google_oauth2/callback`.

Google rejects `.test` callback hosts under its [redirect URI validation rules](https://developers.google.com/identity/protocols/oauth2/web-server#uri-validation). For local OAuth, run Rails on `localhost` and start sign-in on that same origin, or use a registered public development hostname. Ordinary page previews can still use `https://ascent.test`.

Outbound account email uses PostShiba with `POSTSHIBA_API_KEY`. Production uses the sender `Ascent <no-reply@were.ascent.ing>`, reply-to `support@ascent.ing`, and `https://ascent.ing` for account links. The production key is managed in Doppler's `ascent` project, `prd` configuration, and must also be supplied to the Railway app service. Delivered email and account links need verification after DNS is configured. Automated account tests use the test mailer and mocked Google responses. See [ASC-112](https://linear.app/ascent-approval/issue/ASC-112/configure-transactional-email-for-account-confirmation-and-password).

## Staff roles and moderation

Voters have no staff role by default. The `role` field accepts `admin`, `moderator`, or `reviewer`. The migration preserves existing admins when it replaces the `admin` boolean. Staff roles cannot be assigned through signup or profile forms.

Admins retain access to account management and reference-data edits. Moderators can list voters and hide or unhide other voters' influencer profiles. Private voting activity, ratings, and baselines remain visible only to their voter and admins. Hidden profiles stay visible to their owner, while their ratings and baselines still count in race results.

Reviewers, moderators, and admins can open **Moderation > Channel reviews** to approve or reject social account links. Approval marks a channel as official. Rejection removes it from public official-channel lists. Deleting a reviewer account preserves its channel decisions and review timestamps, and clears the reviewer reference.

Run `bin/rails db:migrate` before serving these changes. The Docker entrypoint runs `db:prepare` before the default Rails server command starts.

## Invite links

Each voter has a generated invite URL, shown on their Profile edit page as `/invite/:token`. Existing voters receive tokens during migration. Run `bin/rails db:migrate` before serving the updated app.

Opening a valid link stores the inviter in the visitor's browser session and redirects to signup. The most recently opened valid link wins. Email signup and new Google accounts create an `Invite` with `inviter_id` and `invitee_id` in the same transaction as the voter. Failed signup attempts retain the pending invite. Successful registration, sign-in, or sign-out clears it. Existing accounts do not gain or change an inviter through a link.

Voters can connect to multiple influencers, once per influencer. `voter.invites` returns their outgoing connections, `voter.invited_voters` returns the voters connected to them, and `voter.received_invites` and `voter.inviters` return their incoming connections. Self-connections are rejected. Deleting either account removes the connection. Run the follow-up migration to replace the unique invitee index with a unique inviter and invitee pair index.

The public `/invites` leaderboard lists influencers with at least one connected voter, ordered by connection count. Private influencers appear as "Anonymous influencer" with a count. Their names, account IDs, profile links, and connect controls are omitted. Signed-in voters can use **Connect** for currently public influencers on either a leaderboard row or a public influencer page. Existing connections to public influencers show **Connected**. Connecting always applies to the signed-in voter and preserves their other connections. Connection requests for private influencers are rejected, including requests from a page opened before they turned visibility off.

Influencer visibility defaults to private. Only the voter can opt in through **Save visibility** on their Profile. Opting in shows their name on the leaderboard and enables `/influencers/:token` once they have at least one connection. Turning visibility off removes their name and disables that page. Public pages show a name, a connection count, and the connect control. They do not list connected voters. The leaderboard is linked from the Voting menu and Profile.

Every voter can open **Edit influencer links and statements** from their Profile, even before inviting anyone or going public. The editor at `/profile/influencer` supports labelled HTTP or HTTPS links and plain-text statements. Each collection has its own order. New items appear last, **Move up** and **Move down** change their order, and the **Active** checkbox controls visibility. Inactive items remain editable in their saved position. Only the voter can edit or reorder their content. The two collections live in `voter_links` and `voter_statements`; run `bin/rails db:migrate` before using them.

Public influencer pages show active links and statements inside collapsed **Links** and **Statements** sections below the heading and above Connect. Statements preserve line breaks and display HTML as text. Inactive content is excluded from the page HTML.

Custom invite phrases, profile code entry, registration opt-out, profile unlinking, and further referral reports are deferred. Phrase matching must be case insensitive. Jev moderation must permit mild insults such as "trash those garbage idiots" while rejecting vulgar or violent phrases beyond the agreed threshold. This step does not call Jev or require a Jev API key.

## Inquiries

The public inquiry form at `/inquiries` accepts an email address, subject, and message. Subject buttons fill the subject field, which remains editable. Signed-in voters start with their account email; visitors can submit without an account. The form is linked from Reference and the footer.

Valid submissions enqueue `InquiryMailer.inquiry_email` through Active Job. The recipient is `INQUIRY_RECIPIENT_EMAIL`, defaulting to `support@ascent.ing`, and Reply-To is the submitted email. Messages from signed-in voters also include their name and voter ID. Delivery uses the existing application mail configuration and requires a running job worker. Invalid submissions display errors and retain the entered values.

## Seed Data

The seed repository's [entity catalog](db/seeds/ascent_seed_data/catalog/README.md) lists existing codes by type and state. Its [contributor guide](db/seeds/ascent_seed_data/CONTRIBUTING.md#find-existing-records) documents offline lookup and catalog regeneration.

County geographic identifiers use `fips`, a five-digit string such as `"01001"`. Run `bin/rails db:migrate` before importing the updated county manifests. Replace County `attributes.code` with `attributes.fips` in other seed files; top-level entity codes and Country and State code attributes keep their existing meanings. The migration preserves county values and fills missing FIPS from recorded county Census GEOIDs. It stops if existing values disagree. The boundary importer uses FIPS for county matching and fills missing county FIPS when it records a boundary.

Ascent has two explicit seed layers:

- **Reference data** is the factual geographic and election-calendar foundation. Its YAML is sourced from the Git submodule at `db/seeds/ascent_seed_data`, and `bin/rails db:seed` (including `bin/setup`) loads only this layer.
- **Simulated data** is the intentionally fictitious demo experience: people, voters, generated offices/elections, policies, ratings, and Mountain baselines. It never runs as part of normal setup. Load it explicitly with `bin/rails seed_data:simulated`.

The simulated people and voters live in `db/seeds/simulated/data`, outside the reference-data submodule. Future sourced 2026 races belong in the reference layer; they should not be generated by the simulated election or candidacy seeders.

To compare Mountain rating patterns in development, run `bin/rails dev:mountains`. It creates six mock races with saved ratings and baselines, then prints their Mountain URLs. Sign in as an admin to open the generated voters' Mountains. Each run creates new records. The factories in `spec/factories/mountain_scenarios.rb` also work in specs.

Manifest imports treat upcoming races as active so they appear in the Mountain index. Reference seeding also activates existing upcoming races. Election calendar statuses remain separate. Completed and cancelled race statuses are preserved.

For a focused person and candidacy preview in development, run `bin/rails seed_data:profile_scenario`. It adds the mock New York Civic Forum 2026, with three fictional candidates sharing six approaches but giving different explanations. Marisol Vega has a generated portrait, a locally generated narrated introduction, and an embedded-player example. Her social handle is illustrative. Repeating the command updates the same scenario. It does not run in production or as part of ordinary setup.

Run this after seeding reference data, with the app served at `https://ascent.test`. The scenario uses the New York State jurisdiction and that hostname for its local images, video, and campaign-page links.

Profile images are `Image` records shared through `ImagePlacement` records for people and candidacies. The migration moves existing person portraits into that library. For seed files, replace the former Person portrait attributes with Image attributes and explicit ImagePlacement references; see the data repository's `CONTRIBUTING.md` and `examples/profile_images.yml`. Admin profile forms can add images or reuse existing ones. Image details are shared; display order and removal belong to each placement.

Image files use Active Storage. Admin forms accept JPEG, PNG, and WebP uploads up to 10 MB. Uploaded files use the configured storage service, and the development scenario attaches its existing generated portrait. Source URLs from seed files remain valid external image links; importing a URL does not download it. Upload or attach the file to use stored variants. The named variants use libvips through `image_processing`: `avatar` crops to 96×96, `thumbnail` fits within 320×320, `portrait` crops to 800×1000, and `large` fits within 1600×1600. The header uses `portrait`; additional photos use `thumbnail` and link to `large`. The Docker image already includes libvips; local development needs it too.

OpenAI portrait generation is implemented in `PortraitGenerator`, but remains disabled pending legal review. `config/initializers/portrait_generation.rb` sets `enabled = false`; an API key alone cannot enable it. The admin style selector and Generate portrait button are disabled, and there is no generation route or background trigger. Do not enable the service or wire a trigger until the legal review is complete and activation is approved.

The prepared styles are pen and ink, an imagined legislative-chamber scene, a voting-booth scene, and a randomized American pastime such as driving, volunteering, or a picnic. The service requires an attached reference image from the person or candidacy and uses the [OpenAI image edits API](https://developers.openai.com/api/reference/resources/images/methods/edit). It expects `OPENAI_API_KEY` only after activation. The configured model is `gpt-image-2.5-sunburst`, requesting one 1024×1536 PNG. Generated files retain the prompt, model, style, chosen pastime, timestamp, and reference image/blob IDs in Active Storage metadata. Profiles label them AI-generated illustrations. Automated tests use mocked provider responses; no live API call is part of setup or verification.

The initial 2026 race collection is one file per U.S. state's gubernatorial general election in `races/2026/governor/`. Each record includes its primary date and a source URL. U.S. territories will be added only after their jurisdictions are represented in the reference geography.

The New York 2026 general-election ballot lines live under `races/2026/new_york/`, split by office level and then by office or county. `conflicts.csv` in that directory records disagreements between sources. A seeder reads every YAML file in a directory, including files in nested directories, so a dataset can stay split without a code change.

For local setup, run `bin/setup` so the submodule is initialized before `db:prepare`.

During the transition, the app still falls back to the legacy `db/seeds/data` directory if the submodule is missing.
To copy the current legacy YAML into the submodule working tree, run:

```bash
bin/rails seed_data:copy_legacy_to_submodule
```
