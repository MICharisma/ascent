# The screens

Most of Ascent today is one generic shell applied to every model: a heading such as "Showing race", a card for the record, collapsible sections for its related records, the engagement action bar, and admin controls. It works, but it treats a race the same as a county. The redesign should give the voting screens their own shape and keep the shell for reference data.

Screens are listed in order of importance. Each lists what it shows today and what it has to show after the redesign.

## Everywhere

- **Navigation.** A top bar with the mark and the wordmark "Ascent", sign-in and sign-up links (or a greeting, Saved, Profile and Sign Out when signed in), and six menus: Project, Jurisdictions, Governance, Policy, Elections and Voting. On a phone the menus fold behind a menu button. Six menus of database tables is a lot; a redesign can lead with the voting flow and tuck reference data away.
- **Flash messages** appear once, at the top of the main content.
- **The action bar.** Almost every record has Save, Favorite, Follow, Hide and Share. Each shows its marked state (Saved, Favorited, Following, Unhide) in summit gold. Signed-out visitors see the same buttons, which lead to sign-in. Share uses the system share sheet where there is one, and copies the link otherwise.
- **Admin controls.** Admins also see New, Edit and Delete on reference data, and Simulate on mountains. Every screen needs a visitor state and an admin state, and the visitor state must not leave gaps where the admin controls would be.
- **Status chips** label records: upcoming, active, completed, cancelled; mock and historical elections; party and ballot labels.

## 1. The mountain

The heart of the product, at `/mountains/:race`. Only the signed-in voter whose mountain it is, or an admin, can open it.

- **Today:** a header with the race name and election, followed by a mountain or list view. The chart has a 0 to 500 axis, a draggable baseline, and one column per candidate. New mountains start with a baseline of 200; saved baselines keep their values. Under each column are the candidate's name, their rating when set, and a link to any policy positions. Unrated candidates have no "Not rated" label.
- **Save controls:** Discard and Save mountain appear in the right sidebar when there are unsaved changes. A Saved button shows the saved state. Change details appear on hover or keyboard focus. The page stays editable after saving.
- **Sharing:** a private-by-default Sharing panel lets the voter make this saved mountain public. The public page shows their name, saved ratings, and baseline, with a stored PNG for link previews. Unsaved drafts stay private. Public mountains have Share mountain, View public mountain, and Make private controls. Making one private removes its page and image from Ascent; social sites may retain copies.
- **Ridge:** the mountain connects neighboring candidate ratings directly. It does not drop to zero between rated candidates. The area above the baseline stays lime, and the ridge follows rating changes and resizing.
- **Primary candidates:** when a race's primaries had other candidates, the header says how many, with an Include primary candidates / Remove primary candidates button. Included candidates appear as extra columns labelled "Off the ballot; ran in the Democratic Party primary" (or the top-two primary).
- **Party endorsements:** the Party endorsements button at the bottom left of the mountain panel shows or hides current party endorsements below candidate names in both views. They start hidden. Nonparty and withdrawn endorsements are excluded; ballot designations and primary-race context remain separate.
- **Empty state:** "No candidates yet for this race", with Simulate Data for admins and a link back to the race.
- **It has to:**
  - make the baseline the obvious control, and show which candidates are approved, both as it moves and at rest;
  - handle 2 candidates and 20, on a phone and a desktop, with long names;
  - make the difference between on-ballot and off-ballot candidates clear without making the off-ballot ones look lesser;
  - show unsaved changes, and not lose them (today the primary-candidates button reloads the page and drops unsaved edits, ASC-64);
  - work by keyboard and screen reader, not only by dragging;
  - leave room for further sharing tools such as verified links and QR codes (ASC-58).

## 2. Mountains, the race picker

At `/mountains`. A ranked discovery list, with 25 cards per page. Each card shows the race name, election, current candidate count, saved mountain count, and number of voters active in the last seven days. The race name and View Mountain button open the mountain. Admins also see Simulate Data for mock races. Federal offices and governors receive a National prominence label and ranking boost.

Only active races with at least two contenders still on the ballot qualify. Withdrawn, disqualified, inactive, off-ballot, and carried-over primary candidacies do not count toward that minimum. This filter affects discovery only; the race's own mountain remains accessible. A voter's hidden races stay out of that voter's listing. Ties use race ID in ascending order so pagination is stable.

`MountainDiscovery` ranks races by `ln(1 + saved mountains) + 2 × ln(1 + recently active voters) + 2 × prominence`. Prominence is one for offices in `Office.national` or the coded Governor position, and zero otherwise. The logarithms let recent participation lift a smaller race above one with many older votes. The counts include residents and visitors, once per voter per race. A voter is recently active when their saved baseline or a saved rating was updated at or after the seven-day cutoff. Baseline and rating edits by the same voter count once. Drafts, ratings without a saved baseline, bookmarks, and hides do not contribute. The page exposes aggregate counts, not voters' names or private drafts.

Closeness scoring for races with at least three competitive candidates is deferred. Production already uses Solid Cache. The future closeness calculation can refresh every one or two hours; the first discovery version does not calculate it. Finding races by place remains available in the Races list.

## 3. Home

At `/`. A hero ("Ascent helps communities test richer ways to vote before changing the real world.") with buttons to the mountain demo, About Approval Voting and For Philanthropic Partners; four counts (active elections, offices modeled, topics tracked, issues connected); three cards on what the platform is for; four on its cross-partisan framing; and cards for active races with Open Mountain and See Race Data. It has to explain the mountain in one glance, ideally by showing one.

## 4. Race

At `/races/:id`. Today: "Showing race", then the office and status chips; election, office and election date; a collapsed Candidates section with a count; Results for completed races; a Vote button for active ones; the action bar. It has to lead with the candidates, their ballot labels and parties, and the way to rate them, and show off-ballot primary candidates as a distinct group. For completed races, the approval results.

At `/races/:race_id/results`, two labeled breadcrumb rows place the results. Location follows the election's geographic ancestry and ends with a link to the Election. It uses county, state, and country associations, plus recorded district ancestry for district elections. It does not infer counties from electoral boundaries or invent missing parents. Jurisdiction follows Governance type → Position → Office → Race → Results. The governance type comes from the office's governing body and is omitted when that association is absent. Every ancestor links to its own record page; Results is the only entry marked as the current page. Residents and Pretend voters use the same rows.

## 5. Races list

At `/races`. Filters for search text, state, election year, status and election kind, with Apply and Clear and a count (about 4,700 races today), then one card per race and a pager. It has to make filtering by place quick; most visitors want the races on their own ballot.

Directory dropdown filters apply immediately by default. Text search uses Enter or Apply. Filter submissions use Turbo Drive page navigation, which refreshes dependent dropdown options and result counts.

## 6. Candidacy and citizen

- **Candidacy** (`/candidacies/:id`): the person's name, status and ballot labels, the race and election, policy positions, and rating totals: how many voters rated the candidate, the average rating, and how many approve. Ratings are private, so this page must never show which voter rated the candidate or how.
- **Citizen** (`/citizens/:id`): their candidacies over time, with office, date, status and party.
- They have to present a candidate as a person: stances with their evidence, official channels and communications, endorsements, and room for the multi-dimensional evaluation to come (ASC-59).
- **Images:** images live in a shared library, linked to citizens and candidacies through ordered image placements. A candidacy shows its own images first, followed by the person's images, without duplicates. The first image appears in the header and the rest in Photos. Images retain a description, credit, and source link. Admins can create images, reuse existing images, edit their shared details, order placements, or remove a placement on the citizen and candidacy forms. Removing a placement keeps the image and its other uses. Profiles without an image show initials.
- **Stored image files:** admin forms upload JPEG, PNG, or WebP files up to 10 MB into Active Storage. Named variants are avatar (96×96 crop), thumbnail (within 320×320), portrait (800×1000 crop), and large (within 1600×1600). The header uses portrait and Photos uses thumbnail. Imported external URLs remain usable until a file is attached.
- **AI portraits:** the style selector and Generate portrait button remain disabled pending legal review. Prepared styles are pen and ink, legislative chamber, voting booth, and a randomized American pastime. The service itself also rejects generation while disabled. Generated files retain their reference and prompt metadata and display an AI-generated illustration label.
- **Sites and socials:** official channels distinguish personal accounts from campaign accounts. A candidacy shows its own campaign channels; the citizen page includes their campaigns over time.
- **Videos and statements:** both pages show linked publications with their title, source, date, and summary. YouTube and public Vimeo players load after Play video is clicked. Direct MP4, WebM, and Ogg video links have native playback controls. Unsupported links stay accessible through Open original. Removed publications retain their status and any archive link, with no player.

## 7. Office and election

- **Office** (`/offices/:id`): the current holder and party, then an election history and timeline with results, winners, and days until the next election.
- **Election** (`/elections/:id`): name, status, kind, mock or historical chips, date, and its races with candidate counts. A statewide primary can hold dozens of district nominations.

Organizations, Parties, and Endorsements have public directories and detail pages, linked from the Elections menu. Organizations includes parties and filters by name or abbreviation, state, and kind. Parties lists state parties with name or abbreviation search and a state filter. Organization and party profiles show current endorsements, nominating offices, and official channels. All endorsements opens that organization's full endorsement history.

Endorsements searches endorser and candidate names and filters by kind and current or withdrawn status. Details link to the endorser, candidacy, and election and show recorded dates and notes. Candidacy pages and candidate cards link endorser names to organization, party, or person profiles. Dropdown changes apply immediately; search uses Apply or Enter. Pagination retains filters, and Clear resets them.

Endorsements also filters by the race's State, County, and Race level, independently of where the endorser is based. State includes races in its jurisdiction and descendants. County includes county races, municipalities assigned to the county, and their nested districts; it does not infer overlapping state or congressional districts. State narrows County choices and clears an incompatible county. National includes country and congressional district races and the catalog's President, Senator, and Representative positions, including their nomination races. State covers other state races and districts nested directly under a state. Local covers county, municipal, and nested district races. All filters combine, apply on dropdown changes, and persist while paging, including within an organization's endorsement history.

## 8. Places

States, counties, municipalities and districts. A breadcrumb trail up the hierarchy, quick stats, and previews of the places below, each with a View all link. These are reference pages; they matter mainly as the way a voter finds their own races.

Counties filter by State; Municipalities by State and County; Districts by State and Kind of district. Dropdown changes apply immediately. A selected state narrows the county or district-kind choices and clears an incompatible selection. Name search combines with the dropdowns and uses Apply or Enter. Pagination retains filters, and Clear resets them.

## 9. Policy

Topics, issues, approaches and stances: a chain from a public problem to a candidate's position on a way of solving it. Each is a list and a detail page today. It has to read as a path a voter can follow, not four separate tables.

The Approaches list has title search, Topic, and Issue filters with Apply and Clear. Changing Topic or Issue applies the filters immediately. Changing Topic refreshes Issue options and clears a selected issue from another topic. Issue options include their topic to distinguish similar titles. Title search can use Apply or Enter. The filters combine and stay selected while paging. An issue's nested Approaches list stays within that issue and offers title search; Clear keeps the issue context.

## 10. Saved

At `/saved`, for signed-in voters: sections titled Saved, Favorites, Following and Hidden, with an empty state that explains the buttons.

## 11. Explainers

About Approval Voting (`/approval-voting`), the Glossary (`/glossary`, the schema's terms grouped as places and offices, people and participation, and policy and governance), and For Supporters (`/supporters`). Long-form reading pages.

## 12. Sign-in and sign-up

Signup, login, password reset, and confirmation resend use the shared MICharisma account card. Desktop has a plum story panel with Ascent's mountain mark beside a white form; phones show the form and MICharisma credit. The form has persistent labels, inline errors, autocomplete attributes, and visible keyboard focus. Google appears above email access when configured. Sign-up asks for first and last name too. CTA labels keep Devise's wording. Account settings retain the main application layout.

## Reference data and forms

Countries, positions, governance types, governing bodies, areas of concern, official codes, years, voters, residences, ratings and baselines all use the generic list, detail and form shells. They can stay generic; a consistent, quiet shell is enough. Forms are admin-only.
