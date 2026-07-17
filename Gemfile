# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in rails_docs_ingester.gemspec
gemspec

# RDoc 8 changed the formatter APIs the generator subclasses — pin until
# the generator is ported (the plan's "RDoc upgrade breaks ingester"
# risk, realized). The gemspec range stays >= 6.5 for vintage containers.
gem "rdoc", "~> 7.2.0"

gem "irb"
gem "rake", "~> 13.0"

gem "minitest", "~> 5.16"

gem "rubocop", "~> 1.21"
