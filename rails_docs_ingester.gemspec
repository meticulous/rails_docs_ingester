# frozen_string_literal: true

require_relative "lib/rails_docs_ingester/version"

Gem::Specification.new do |spec|
  spec.name = "rails_docs_ingester"
  spec.version = RailsDocsIngester::VERSION
  spec.authors = ["John Athayde"]
  spec.email = ["jmpa@meticulous.com"]

  spec.summary = "Ingest Rails source documentation into a structured data store for api.rubyonrails.org."
  spec.description = <<~DESC
    RDoc generator that walks a checked-out Rails source tree and emits structured
    JSONL records (modules, classes, methods, constants, attributes, inheritance edges,
    method parameters, source locations) suitable for loading into the rails-docs
    Rails app that powers api.rubyonrails.org.
  DESC
  spec.homepage = "https://github.com/meticulous/rails_docs_ingester"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "rdoc", ">= 6.5"
  spec.add_dependency "json", ">= 2.0"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
