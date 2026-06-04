# rails_docs_ingester

Ingest Rails (and Rails-ecosystem) source documentation into structured records for the [api.rubyonrails.org][rails-docs-app] redesign.

This gem registers an RDoc generator that walks a checked-out source tree and emits a JSONL stream — one record per module, class, method, constant, attribute, inheritance edge, method parameter, and more — for the `rails-docs` Rails app to load into Postgres.

## Why a separate gem?

`rails_docs_ingester` runs against many historical Rails versions, some of which need old Ruby and old RDoc to parse correctly. Keeping the ingester small and dependency-light lets it run inside vintage toolchains (older Ruby + RDoc for Rails 2.x, etc.) without dragging in modern Rails or a Postgres client. The output is plain JSONL, which a separate modern-Ruby loader writes to Postgres in the `rails-docs` app — so schema iteration costs minutes (re-run the loader), not hours (re-run RDoc on every version).

## Status

Working. Part of the [api.rubyonrails.org redesign][project] funded by the Rails Foundation.

Drives the full dataset behind the docs app today: Rails 2.2 → 8.1 plus the official ecosystem gems (turbo-rails, stimulus-rails, kamal, the Solid trio, propshaft, importmap-rails, jbuilder, globalid). RDoc 7 on Ruby 3.4 parses the whole Rails range cleanly — no per-version vintage container needed in practice.

## Usage

```bash
bundle exec exe/rails_docs_ingester \
  --output out/8.1.2.jsonl \
  --source-root /path/to/rails-checkout \
  --channel 8.1.2 --git-ref v8.1.2 --git-sha <sha> --ord 8001002 \
  --source-slug rails --source-display-name "Ruby on Rails" \
  --source-github-repo rails/rails \
  --quiet \
  activesupport/lib activerecord/lib actionpack/lib   # …source dirs
```

Options: `--output` (required), `--source-root`, `--channel`, `--git-ref`, `--git-sha`, `--ord`, `--source-slug`, `--source-display-name`, `--source-github-repo`, `--quiet`, `--debug`.

In practice you drive it through the docs app's `script/backfill`, `script/refresh_all`, `script/ingest_gem`, and `script/refresh_ecosystem` wrappers, which handle worktrees, ords, and loading.

## What it extracts

A header record, then a `package_version`, `framework` rows, and per entity:

| Record | Notes |
|---|---|
| `entity_identity` | one per logical entity (fqn, kind, scope, parent) |
| `entity_version` | per-version snapshot: docs, signature, source path/line, visibility, deprecated |
| `method_version` | yields, return doc, alias, ghost flag |
| `method_param` | reified per parameter (kind, default, doc) for signature rendering + structured diffs |
| `class_version` | superclass |
| `constant_version`, `attribute_version` | lightweight extensions |
| `inheritance_edge` | superclass / include / extend / prepend, with position for MRO |

### Notable extraction behavior

- **Private methods are kept.** RDoc defaults to `--visibility=protected`, dropping privates before the generator sees them; we run at `--visibility=private` so every method is captured. Visibility flows through on `entity_version.visibility`, and the docs app separates/deranks/`noindex`es privates downstream. (Rails uses private methods as template/override points, so they're worth documenting.)
- **Markdown comments render as Markdown.** Comments under a `# :markup: markdown` directive (and README content pulled in via `:include:`) are parsed with the Markdown parser rather than RDoc's default — so `# Heading` becomes a heading, not a literal `#`. When `:include:` doesn't propagate the directive, the text is sniffed for ATX headers / `[label](url)` links and treated as Markdown. This keeps `doc_markdown` clean for the docs app's `.md` / `text/markdown` AI-readable output.
- **Boilerplate trimmed.** The duplicated `## Support` and `## License` blocks that most framework READMEs repeat are stripped (the app renders curated versions), as are the empty `---`-separated segments RDoc emits when a class/module is reopened across many files.

## Architecture

Producer side (this gem):

```
git checkout v8.1.2  →  rdoc -f rails_docs_ingester  →  out/8.1.2.jsonl
```

Consumer side ([rails-docs][rails-docs-app]):

```
out/8.1.2.jsonl  →  bin/load  →  Postgres (entity_identities, entity_versions, …)
```

## Development

```bash
bin/setup
bundle exec rake          # default: Minitest + RuboCop
bundle exec rake test     # tests only
bin/console
```

## License

MIT.

[rails-docs-app]: https://github.com/meticulous/rails-docs
[project]: https://api.rubyonrails.org
