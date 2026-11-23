# Testing Ascent

Specs are the executable record of what the app promises. Write one when it is the cheapest way to show a behavior works and to keep it working. A spec that can't fail, or that only repeats another spec, costs run time and reading time and protects nothing.

## Choose the layer

Use the lowest layer that can show the behavior. Each layer up is slower and breaks for more reasons.

| The behavior lives in | Spec type | Directory | Typical speed |
| --- | --- | --- | --- |
| A model, query, policy or service: rules, scopes, consolidation, seed conversion | model, service or lib | `spec/models`, `spec/services`, `spec/lib` | milliseconds |
| A controller action: authorization, redirects, params, what the page or JSON contains | request | `spec/requests` | ~50 ms |
| A Stimulus controller or Turbo behavior: clicks, frames, streams, analytics events, timers | interaction (rails-jsdom) | `spec/interactions` | ~100–300 ms |
| Browser analytics internals that are easier to drive directly | Node unit test | `spec/javascript` | milliseconds |
| Layout and gestures: overflow, sizes, positions, breakpoints, dragging, anything needing real CSS or a real pointer | system (Chrome) | `spec/system/` | seconds |

Some quick rules for choosing:

- If the page works with JavaScript off, a request spec can check it. Use `response.parsed_body` (a Nokogiri document for HTML) and assert on elements, not on raw substrings of `response.body`. When you do check `response.body` for a record's name, compare `ERB::Util.html_escape(name)`: Faker names such as O'Connor are escaped on the page.
- If you need to click something that a Stimulus controller or Turbo handles, write an interaction spec.
- If a page shows different things by role, account, setting or state, record each permutation as an interface snapshot (see below) rather than scattering `include` and `not_to include` checks.
- Write a system spec only when the assertion needs a real browser: geometry, computed style, or pointer and touch gestures such as dragging a candidate on a mountain. System specs live in `spec/system/<area>_layout_spec.rb` (gestures in `<feature>_gestures_spec.rb`) and hold no other behavior checks. They use the helpers in `spec/support/layout.rb`:
  - `phone_viewport`
  - `expect_pages_to_fit(*paths)`, which visits each page, confirms it rendered, and checks for sideways scrolling in light and dark themes
  - `expect_no_horizontal_overflow`
  - `rect(selector)`

## Who is signed in

Specs start signed out. Call `sign_in` with a voter from the factories: `create(:voter)` for an ordinary voter, `create(:admin_voter)`, `create(:moderator_voter)` or `create(:reviewer_voter)` for staff. Records are open to read and closed to change unless a policy in `app/policies` says otherwise; `ApplicationRecordPolicy` lets only administrators add, edit or remove. `spec/requests/policy_catalog_spec.rb` is the worked example of checking a policy from the outside.

## Fixing a bug

1. Find the spec file that owns the behavior. It is usually named for the model, the controller, or the page. Extend that file rather than starting a new one.
2. Write an example that reproduces the bug at the lowest layer that shows it. Run it and watch it fail **for the reason the bug describes**. If it passes, or fails for another reason, you haven't reproduced the bug yet.
3. Fix the code and run the example again, then run the file.
4. Name the example for the rule that was broken ("hides pending posts from other visitors"), not for the bug report ("fixes #123").

## Writing an example

- **One behavior per example.** The name states the rule. If you'd describe it with "and", split it, unless the second half needs the first half's steps (for example, a filter that must survive the next page).
- **Arrange only what the behavior needs.** Use factories, and set only the attributes that matter to the assertion. Use `build` when nothing has to be saved. Use `let` for the subject and `before` for shared setup. Avoid `let!` unless the record must exist before the example runs and isn't referenced.
- **Assert outcomes, not implementation.** Check the record that changed, the response, or what the visitor sees. Don't stub the object under test. Stub only boundaries the test can't own: Rizz, Stripe, LLM providers, outside HTTP.
- **Prefer DAMP to DRY.** An example should read top to bottom without jumping to helpers. Extract a helper only when three or more examples share the same steps.
- **Make sure it can fail.** Before you finish, break the code it covers (flip a condition, change a constant, remove a line) and confirm the example fails. Restore the code. This takes a minute and catches most specs that test nothing.

## Don't write

- Screenshots, `save_screenshot`, or CDP calls in feature specs. Check a UI change in the browser at http://ascent.test instead.
- `sleep`, retries, or `wait:` options. Interaction specs settle the page before every step. For timers, see below.
- One-liner association or validation matchers (`it { is_expected.to belong_to ... }`) unless the validation encodes a product rule. Then test the rule with real records.
- Specs that only check a page returns 200. Assert something the page promises.
- The same behavior at two layers. When an interaction spec covers a flow, its request spec doesn't need to repeat every assertion.
- `allow_any_instance_of`. Inject the dependency, or stub the class method that builds it.
- Scaffold placeholders (`pending "add some examples"`, `skip("Add a hash of attributes")`). Write the example or delete the file.
- Controller specs for new work. Request specs cover the same ground through routing and middleware.

## Interaction specs

Interaction specs use [rails-jsdom](https://github.com/jakehow/rails-jsdom). Rails renders real pages, the app's real Stimulus controllers and Turbo run in jsdom, and every request is answered by Rails in the test process. No browser and no server are involved. `spec/support/interactions.rb` adapts the gem's Minitest test case to RSpec, so every file under `spec/interactions/` gets the following:

- Navigation and forms: `visit`, `click`, `click_on`, `click_link`, `click_button`, `fill_in`, `select`, `check`, `choose`, `within`, `find`, `all`, `first`, `send_keys`, `evaluate_script`, `using_session`, `accept_confirm`.
- Matchers on `page` or on a found element: `have_css`, `have_content`, `have_field`, `have_button`, `have_link`, `have_current_path`, `have_title`. Each has a `have_no_` form.
- `sign_in voter` from Devise.
- A virtual clock. Ruby time is frozen when the example starts and pages share it. A timer due within a second runs before the next step. For a longer one, `travel 2.seconds` moves the page clock and runs it.

The gem has limits:

- There is no layout. Every element measures 0×0, so layout checks go in the feature's layout system spec.
- `matchMedia` never matches, observers never fire, and scrolling does nothing.
- CSS never applies, so text is the HTML source text: a heading styled uppercase still reads "Pacific Basketball League".
- Only the `hidden` attribute, inline `display: none`, closed `<dialog>`s and similar markup hide an element. A Tailwind `hidden` class doesn't, so assert the class (`have_css(".panel.hidden")`). In new code, toggle the `hidden` attribute instead.
- An element styled for one screen size is still on the page. A link shown only at one width still matches, so scope it with `within` or pass `match: :first`.
- `find` takes CSS, not XPath. To reach a field's container, use `:has`, as in `find(".tagging-rating:has(#tagging-strength-1)")`.
- Images neither load nor fail. To exercise a fallback, fire the event yourself: `find("img", visible: :all).execute_script("this.dispatchEvent(new Event('error'))")`.
- `sign_in` applies to the next request in any session. With `using_session`, sign each user in inside their own block, after the other sessions are done making requests.
- A record the page must list has to exist before the `visit`. A lazy `let` that the example never mentions creates nothing, so use `let!` or touch it in `before`.
- Browser-owned behavior doesn't happen: Escape doesn't close a `<dialog>`, closing one doesn't return focus, and clicking a heading doesn't blur a field. Call `close()` or `blur()` in the test and assert what the app does next.
- Requests to other hosts fail. After the page loads, stub them with `stub_fetch`.
- A JavaScript error, an unhandled rejection, or an unexpected `confirm` fails the step. Wrap an expected dialog in `accept_confirm { ... }`.
- More than one element matching a locator raises. Scope with `within`, or pass `match: :first`.
- Run `npm install` once per checkout. The gem needs Node 22.22+, 24.15+, or 26+.

## Interface snapshots

A page that changes with who is looking or what exists (role, own account or someone else's, settings, empty states, tabs) gets an interface snapshot for each permutation. The snapshot is an outline of what a visitor can read and do on the page. It lists headings, text, links (with record ids replaced by `:id`), buttons, form fields and their flags, and the regions that group them. It leaves out styling and markup, so restyling a page doesn't change its snapshots, but adding, removing or rewording anything a visitor sees does.

```ruby
it "shows an administrator the race's management tools" do
  sign_in create(:admin_voter)
  get race_path(race)
  expect(response.body).to match_snapshot(serializer: :interface)
end
```

`spec/requests/race_page_interface_spec.rb` is the worked example. A few rules:

- Write one example per permutation, named for who sees what. When one example records several snapshots (for example, a tab loop), name each one. Names must be unique within the file's `describe`, because they share one directory under `spec/snapshots/`.
- Make the page deterministic. Freeze time with `travel_to`, and give records fixed, realistic names instead of factory sequences.
- A snapshot records only the permutations you list. A rule that only shows up in a permutation you didn't list goes untested, so cover each role and state the page branches on.
- Snapshot what the page shows. Keep behavior (what a click or a submission changes) in ordinary request or interaction examples.

A snapshot that changes fails the example with a side-by-side diff and writes a `.snap.new` file beside it. A new snapshot fails until it is accepted.

- `bin/insta review` steps through pending snapshots so you can accept or reject each one. `bin/insta accept` accepts them all, and `bin/insta status` lists what's pending. Use `bin/insta`, not `bundle exec insta`: the binstub points the CLI at `spec/snapshots`.
- Read every diff before accepting it. Accept only the changes your work intended, and say in the commit message which snapshots changed and why. An unexpected change is a bug report.
- `INSTA_FORCE_PASS=true bundle exec rspec <file>` writes pending snapshots without failing, which is useful for a first run.

## Running specs

- `bundle exec rspec path/to/file_spec.rb` while working, then the related directory.
- `bundle exec rspec` before committing. The whole suite takes about a minute and a half.
- `node --experimental-vm-modules --test spec/javascript/` for the analytics unit test.
- `COVERAGE=1 bundle exec rspec` writes line and branch coverage to `coverage/index.html`.
- `bundle exec rspec --only-failures` to rerun what failed.

When you run a filtered set, confirm the summary line shows the examples actually ran.
