# rails_docs_ingester

Ingest Rails source documentation into structured records for [api.rubyonrails.org][rails-docs-app].

This gem registers an RDoc generator that walks a checked-out Rails source tree and emits a JSONL stream — one record per module, class, method, constant, attribute, inheritance edge, and method parameter — suitable for loading into the `rails-docs` Rails app.

## Why a separate gem?

`rails_docs_ingester` runs against many historical Rails versions, some of which require old Ruby and old RDoc to parse correctly. Keeping the ingester as a small, dependency-light gem lets it run inside vintage containers (Ruby 1.9.3 + RDoc 3.x for Rails 2.x, etc.) without dragging in modern Rails or modern Postgres clients. The output is plain JSONL, which a separate modern-Ruby loader picks up and writes to Postgres in the `rails-docs` app.

## Status

Pre-alpha. Skeleton only. Part of the [api.rubyonrails.org redesign][project] funded by the Rails Foundation.

## Development

```bash
bin/setup
bundle exec rake test
bin/console
```

## Architecture

Producer side (this gem):

```
git checkout v7.1.3  →  rdoc -f rails_docs_ingester  →  out/v7.1.3.jsonl
```

Consumer side ([rails-docs][rails-docs-app]):

```
out/v7.1.3.jsonl  →  bin/load  →  Postgres (entity_identities, entity_versions, ...)
```

This split means schema iteration costs minutes (re-run the loader), not hours (re-run RDoc on every version).

## License

MIT.

[rails-docs-app]: https://github.com/meticulous/rails-docs
[project]: https://api.rubyonrails.org
