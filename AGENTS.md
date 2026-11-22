# Working on Ascent

This file provides guidance to coding agents working in this repository. `CLAUDE.md` imports it.

## 🚨 READ FIRST: Conventions Directory

**Before starting ANY work, check the relevant convention file:**

- **CSS/Styling** → `doc/llm-assistant/conventions/css-tailwind.md` (UNIQUE approach!)
- **Ruby/Rails/Phlex** → `doc/llm-assistant/conventions/ruby-rails.md`
- **JavaScript** → `doc/llm-assistant/conventions/javascript-stimulus.md`
- **Database** → `doc/llm-assistant/conventions/database-postgresql.md`

See `doc/llm-assistant/README.md` for complete navigation guide.

## Common Development Commands

### Ruby through mise
This app loads Ruby 4.0.9 through mise, pinned in `mise.toml`. A `ruby` already on `PATH` is usually a different version, so check mise before reporting that Ruby is missing.

- `mise install` installs the pinned Ruby if it isn't there yet.
- Prefix Ruby commands with `mise exec --`: `mise exec -- ruby -S bundle install`, `mise exec -- ruby bin/rails db:migrate`, `mise exec -- ruby -S bundle exec rspec`.
- Or activate mise once per shell with `eval "$(mise activate bash)"` (or `zsh`) and run the commands bare.

### Primary Development Cycle
- The development log is the fastest way to review context
- You do not need to start the Rails server or Tailwind watcher
- You can use the Rails console but you also have read access to Postgres
- You can use the browser to navigate to http://ascent.test
- Visit a page after you are almost finished editing it to see if it renders without error
- Always use the format /relative/path/to/file.rb:line_number_or_range when referencing a file
- we have ast-grep


### Development Server
- `bin/rails restart` - Restart Rails server (after adding gems, configs, lib - normal code changes do not require restart)

### Testing
- `bundle exec rspec` - Run all tests
- `bundle exec rspec spec/path/to/file_spec.rb` - Run specific test file
- `bundle exec rspec spec/path/to/file_spec.rb:line_number` - Run specific test

### Database
- `bin/rails db:migrate` - Run migrations
- `bin/rails db:seed` - Seed database

## Architecture Overview

### Core Technology Stack
- **Rails 8.1** with modern Rails conventions
- **Phlex** for view components instead of ERB templates
- **Tailwind CSS** with semantic class approach (NO direct Tailwind in markup)
- **Stimulus** for JavaScript interactions
- **PostgreSQL** with multiple databases (main, jobs, caching, ActionCable)
- **RSpec** with FactoryBot for testing

### View Architecture
The project uses Phlex components instead of traditional ERB views:

```
app/views/
├── components/
│   ├── ui/              # Reusable UI components
│   ├── forms/           # Form-specific components
│   └── layouts/         # Layout components
└── pages/               # Page-specific Phlex views
```

Key Phlex patterns:
- Use initializers to set instance variables from arguments
- yield to render child components

### CSS Architecture
⚠️ **CRITICAL: CUSTOM CSS APPROACH** ⚠️
This project uses a unique four-layer Tailwind approach. **DO NOT** use standard CSS or inline Tailwind classes.

**BEFORE writing ANY CSS, read `doc/llm-assistant/conventions/css-tailwind.md`**

Quick summary:
1. **Layout Layer** (`app/assets/tailwind/layout/`) - Flex, positioning, responsive design
2. **Spacing/Size Layer** (`app/assets/tailwind/sizing/`) - Element spacing, sizing, responsive
3. **Typography/Colors Layer** (`app/assets/tailwind/typography/`, `colors/`) - Fonts, colors via CSS variables
4. **State Layer** (`app/assets/tailwind/situation/`) - Hover, focus, active states

**Critical Rules**:
- Use semantic classnames in HTML (e.g., `main-navigation`, `nav-link`)
- Apply Tailwind classes using `@apply` directive in CSS files
- Never put Tailwind classes directly in markup
- Colors must use CSS variables defined in `tailwind/variables/colors.css` files

### Testing Strategy
- Specs are discretionary; write one when it is the best way to establish the behavior
- Use FactoryBot with highly descriptive data (serves as documentation)
- Use Shoulda Matchers for common Rails validations
- Don't test ActiveRecord macros, focus on compound interactions
- Multiple factory options with descriptive data for domain understanding

### Controller Patterns
- Define domain logic on the relevant models
- Extract a service object only when the behavior needs one

### JavaScript/Stimulus Conventions
- Encapsulate element condition checks in descriptively-named methods
- Encapsulate element modifications in descriptively-named methods  
- Trigger modifications via CSS (adding/removing classes or data attributes)
- Use wrapped console.log method that respects log levels

## Code Style

### Ruby Style
- Minimize parentheses usage as indicator of line complexity
- Call methods directly on results rather than storing in variables for single use
- Create separate methods for complex logic (if/case statements)
- Don't preemptively check for nil or data structure types
- Comments are only needed for logic where the method names are not self-explanatory

### View Helpers
- Make heavy use of view helpers to encapsulate markup structure
- Keep helpers simple and reusable, but don't over-engineer flexibility
- Create helpers even for single-use cases for readability
- Use `safe_join` for arrays when nesting isn't necessary
- Use tag helpers with blocks and concatenation (+ operator)
- All methods in concatenation must use parentheses
- Add `.html_safe` to objects in concatenation when needed

## Important Documentation

Additional context available in `doc/llm-assistant/`:
- `tech-stack.md` - Core technology decisions and anti-patterns
- `project-context/` - Architecture, deployment, testing context
- `approval-voting-prd.md` - Product requirements for the voting features

## Project Context

This is a political science/voting application called "Ascent" focused on approval voting systems. The application follows Rails conventions with modern architectural patterns emphasizing component reusability, mobile-first design, and semantic HTML structure.