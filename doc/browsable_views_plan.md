# Browsable views: bringing them up to the new design

October 27, 2026, on `voting-flow`.

## Where things stand

Already in the new style, and the patterns to copy:

| Page | File | Patterns worth reusing |
| --- | --- | --- |
| Municipality | `app/views/municipalities/show_view.rb` | breadcrumb, eyebrow, display title, lede, primary/secondary pill actions, ActionBar, StatTiles, main + aside layout, SideCards, "See all N" links, timeline |
| Election | `app/views/elections/show_view.rb` | hero with countdown, ballot sheet of contests, at-a-glance side card, sibling elections |
| Elections list | `app/views/elections/index_view.rb` | tabs with counts, filter strip, "where you live" cards, day-grouped rows, empty state |
| Ballot, mountains, results, saved | `ballots/`, `mountains/`, `race_results/`, `engagements/` | |

Still on the generic shell (`ResourceIndex` / `ResourceShow`, "Showing race", collapsible sections, `status-indicator`, raw pagy HTML): every other index and show page. By size of the data behind them:

| Area | Records | Index | Show |
| --- | --- | --- | --- |
| Races | 4,743 | shell + filter form | shell |
| Candidacies / citizens | 6,835 each | shell | shell |
| Offices / positions | 4,891 / 1,311 | shell | shell |
| Municipalities | 35,640 | shell + state filter | **done** |
| Counties / districts / states / countries | 3,144 / 7,335 / 61 / few | shell | shell + `HierarchicalNavigation` |
| Topics → issues → approaches → stances | 10 / 40 / 120 / 18 | shell | shell |
| Governing bodies, policies, official codes | 29 / 19 / few | shell | shell |
| Years, governance types, areas of concern, voters, residences, ratings, baselines | | shell | shell |

Problems the shared pieces carry today:

- `Pagination` dumps `pagy.series_nav` HTML, styled by `plugins/pagy.tailwind.css` in raw grays with no brand tokens; no prev/next labels, no compact phone form, and every page change reloads the whole page and jumps to the top.
- `ItemPreview#view_all_path` builds `"#{class.name.downcase}_id"`, which is wrong for multi-word models (`governingbody_id`).
- `ResourceShow` titles every page "Showing race"; the record's own name never leads.
- `RacePartial`'s "View full results" goes to the race, not `race_results_path`; its "Vote" button is the only call to action.
- Status and entity colors still come straight from Tailwind's palette (see `doc/design/03-brand.md`).

## Approach

Build a small kit first, then move pages onto it in order of importance (`doc/design/02-screens.md`), then upgrade the generic shell itself so the reference tables improve without bespoke pages. Each page gets its own CSS file per layer (`race`, `citizen`, `place`, `policy`, …), which keeps the phases from colliding.

### Phase 0: the kit (everything else depends on it)

1. **`PageHeader`**: breadcrumb, eyebrow, display title, lede, a slot for pill actions, and the ActionBar. Lifted from `place_header` and `election_hero`; the municipality and election pages move onto it so there is one header.
2. **Breadcrumbs everywhere**: a `breadcrumb_for(record)` helper that builds the trail from `Hierarchicable#build_hierarchy_chain` for places, and from the record's parents elsewhere (race → election, candidacy → race → election, approach → issue → topic). Index pages get a one-step trail to their section. `HierarchicalNavigation`, `QuickStats`, `GeographicSummary` and `ChildrenPreview` retire once places stop using them.
3. **`RelatedList`** replaces `ItemPreview` + `ExpandableSection` on show pages: a section heading with a count, the first N records as compact rows, and a "See all N" link to the filtered index. The parent key comes from `model_name.param_key`, which fixes the multi-word bug. Empty lists render nothing, or one quiet line when the absence is itself information ("No candidates have filed yet").
4. **`ListRow`**: the one row shape for indexes and related lists: entity icon, title link, a meta line, status chips, and a trailing chevron. The whole row is the link target; secondary links inside stay separately focusable.
5. **Entity icons**: one `entity_icon(record_or_model)` map onto Lucide, used in rows, headers, breadcrumbs and the navigation: race `vote`, election `calendar`, candidacy `badge-check`, citizen `user-round`, office `landmark`, position `briefcase`, state `map`, county `map-pinned`, municipality `building-2`, district `layout-grid`, country `globe`, topic `tag`, issue `circle-help`, approach `route`, stance `quote`, governing body `columns-3`, policy `scroll-text`.
6. **Pagination, rebuilt** as a Phlex component over the pagy object, not its HTML:
   - "Showing 26–50 of 4,743 races" on the left; prev and next pills with chevrons, a window of page numbers with gaps, and the current page marked, on the right. On a phone: prev, "Page 2 of 190", next.
   - The list and the pager sit in a Turbo frame that advances the URL, so a page change swaps only the list, keeps the filters, and scrolls to the top of the list rather than the page.
   - `rel="prev"`/`rel="next"`, `aria-current="page"`, and a `nav` labelled "Pagination".
   - Related lists on show pages use "See all N", not pagers.
   - `plugins/pagy.tailwind.css` is deleted.
7. **`IndexPage`**: the header, an optional tab strip with counts (from the elections list), a filter bar, the result count, `ListRow`s, an empty state with an icon and a way out (clear filters), and the pager. Admin "New" becomes a pill in the header.
8. **Tokens**: status colors (upcoming, active, completed, cancelled, mock, historical) and the entity accents become role variables in `variables/colors.css` pointing at brand colors. `StatusChip` replaces `status-indicator` everywhere.
9. **Motion**, small and consistent, all off under `prefers-reduced-motion`:
   - Turbo page changes through the View Transitions API (`<meta name="view-transition" content="same-origin">`), with the page title as a shared element so a row's title appears to carry into the header.
   - A `reveal` Stimulus controller that fades and lifts list rows and cards in with a short stagger on first render and after a pager swap (CSS transitions driven by a data attribute, per the Stimulus conventions; GSAP stays for the mountain and results).
   - Hover: rows tint to glacier and the chevron nudges right; cards lift one step. Lives in the situation layer.
   - Stat tiles count up once when they enter the viewport.

### Phase 1: the voting records

These are the pages a voter reaches from a ballot or a mountain.

- **Race** (`races/show_view.rb`, new view replacing `ResourceShow`): breadcrumb (state / election / race), eyebrow "Office · Place · date", status chips, and the call to action that fits (Build your mountain, Pretend vote, See results). Then candidates first, with ballot labels and party, each opening the candidate card popover the ballot already uses; off-ballot primary candidates as their own group, same weight. Completed races show the approval results inline (reusing the results bars) with a link to the full results. Aside: the office (current holder, link), the election (date, countdown, how many other races), the place.
- **Races list**: the elections list's shape. Tabs for open, upcoming, completed with counts; place first in the filters (the voter's own places as chips when signed in, then state, then year and kind); search kept. Compact `ListRow`s showing office, place, date, candidate count, and the voter's progress chip. New pager.
- **Candidacy**: a candidate as a citizen: name, ballot labels, status, the race and election in the header; stances grouped by topic, each linking along topic → issue → approach, with evidence; endorsements; official channels and featured communications; rating totals only (never who rated or how); other candidates in the race. Room left for multi-dimensional evaluation (ASC-59).
- **Citizen** and **citizens list**: their candidacies as a timeline (office, date, party, status, result), the latest candidacy's stances, and links to each race. The list gets search, a state filter, and rows with the current or latest office.
- **Office** and **offices list**: current holder card, next election with a countdown, a race history timeline with winners, then jurisdiction, governing body, chamber and position as links. The list filters by place and position.

### Phase 2: places

State, county, district and country show pages on the municipality page's pattern: breadcrumb, fact tiles, "On the ballot here", seats elected here, elections timeline, then `RelatedList`s of the places below (counties, municipalities, districts) with See all. Their indexes: search plus a state filter, grouped by state where unfiltered. Municipalities (35,640) also get a letter jump. This is mainly how a voter finds their own races, so each place page ends at the ballot.

### Phase 3: policy

Topics, issues, approaches and stances read as one path: a breadcrumb along the chain on every page, the topic page listing its issues as cards with approach and stance counts, the issue page its approaches, the approach page the candidates who take it, and the stance page its evidence and communications. Governing bodies, policies and official codes get the same treatment one level quieter: governing body → its offices and policies, policy → its codes.

### Phase 4: the generic shell

Upgrade `ResourceIndex` and `ResourceShow` themselves onto the kit: the record's name as the title, a breadcrumb to its section, `ListRow`s, the new pager, icons, and the actions in the header. Years, positions, governance types, areas of concern, voters, residences, ratings and baselines then match without their own views. Partials that still use `info-grid` / `info-item` get a `FactRow` pass.

## Every page, before it is done

- Signed out, signed in, and admin states, with no gaps where admin controls would be.
- Phone (375px) and desktop, checked in the browser at http://ascent.test.
- No N+1 queries in the development log; related lists use `includes` and counts come from one query.
- Keyboard: rows and pager reachable in order, focus visible; icon-only controls labelled.
- Request specs that the page renders for each state, and a component spec for `Pagination` and `RelatedList`.

## Order for today

1. Phase 0, items 1–7 (header, breadcrumb, related list, row, icons, pager, index page), proven on the races list and race page.
2. The rest of phase 1.
3. Phase 2 and phase 3 can run side by side once the kit lands, since they touch separate views and CSS files.
4. Phase 0 items 8–9 (tokens, motion) and phase 4 as a sweep at the end.

Before starting: the uncommitted mountain CSS and `candidate_column.rb` changes in the working tree belong to other work and should be committed or set aside first.

## Status, end of October 27

All five phases are done, one commit each on `voting-flow`.

- **Phase 0**: the kit (`PageHeader`, `ListRow`, `RelatedList`, `IndexPage`, `Pagination`, icons, motion), the races list and the race page.
- **Phase 1**: candidacy, citizen and office pages and their lists, with `FilterForm`, `StanceList` and `OfficialChannels`.
- **Phase 2**: state, county, district and country pages through `Views::PlaceSections`, which the municipality page shares, and their lists.
- **Phase 3**: the policy path (`PolicyPath`, `StanceRow`), and governing body, policy and official code pages.
- **Phase 4**: `ResourceIndex` and `ResourceShow` rebuilt on the kit for the remaining reference data, the hierarchy and preview components and their CSS removed, status and entity colors on brand tokens, the election header on `PageHeader`, and stat tiles that count up.

Left for later: a letter jump on the municipalities list and the forms (`ResourceFormPage`), which still use the older scaffold styles. Signup, login, password reset, and confirmation resend now use the MICharisma account layout described in `design/02-screens.md`.
