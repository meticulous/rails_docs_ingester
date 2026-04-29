# frozen_string_literal: true

require "rdoc"
require_relative "writer"

module RDoc::Generator
  # RDoc generator that emits structured JSONL records (one per line) describing
  # the parsed source tree. The companion Loader in the rails-docs Rails app
  # consumes the JSONL and upserts the records into Postgres.
  #
  # The generator does not write HTML, CSS, or any of the visual artifacts a
  # documentation generator usually produces. Its only output is the JSONL file
  # at --rails-docs-output.
  class RailsDocsIngester
    # Add accessors directly to RDoc::Options so they survive across the
    # parse/document lifecycle.
    module OptionsExtension
      attr_accessor :rails_docs_output, :rails_docs_channel, :rails_docs_git_ref,
                    :rails_docs_git_sha, :rails_docs_ord, :rails_docs_source_slug,
                    :rails_docs_source_display_name, :rails_docs_source_github_repo
    end
    RDoc::Options.prepend(OptionsExtension)

    RDoc::RDoc.add_generator(self)
    # The default key derived from the class name is `railsdocsingester`; we
    # override it with the snake_case form so `-f rails_docs_ingester` works.
    RDoc::RDoc::GENERATORS["rails_docs_ingester"] = self

    def self.setup_options(options)
      op = options.option_parser
      op.separator nil
      op.separator "rails_docs_ingester options:"
      op.separator nil

      op.on("--rails-docs-output PATH", "JSONL output file path") do |path|
        options.rails_docs_output = path
      end
      op.on("--rails-docs-channel CHANNEL", "Package channel (e.g. 8.1.3, edge)") do |channel|
        options.rails_docs_channel = channel
      end
      op.on("--rails-docs-git-ref REF", "Git ref this snapshot represents (e.g. v8.1.3)") do |ref|
        options.rails_docs_git_ref = ref
      end
      op.on("--rails-docs-git-sha SHA", "Resolved git SHA") do |sha|
        options.rails_docs_git_sha = sha
      end
      op.on("--rails-docs-ord N", Integer, "Monotonic ord for cross-version sort") do |n|
        options.rails_docs_ord = n
      end
      op.on("--rails-docs-source-slug SLUG", "Source slug (default: rails)") do |slug|
        options.rails_docs_source_slug = slug
      end
      op.on("--rails-docs-source-display-name NAME") do |name|
        options.rails_docs_source_display_name = name
      end
      op.on("--rails-docs-source-github-repo REPO") do |repo|
        options.rails_docs_source_github_repo = repo
      end
    end

    def initialize(store, options)
      @store = store
      @options = options
    end

    def generate
      output_path = @options.rails_docs_output ||
        raise(ArgumentError, "--rails-docs-output is required")

      File.open(output_path, "w") do |file|
        ::RailsDocsIngester::Writer.new(file, @store, @options).write_all
      end
    end

    # RDoc calls these to determine output paths; we have neither, so return nil.
    def class_dir; nil; end
    def file_dir; nil; end
  end
end
