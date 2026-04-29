# frozen_string_literal: true

require_relative "rails_docs_ingester/version"
require_relative "rails_docs_ingester/writer"
require_relative "rails_docs_ingester/generator"

module RailsDocsIngester
  class Error < StandardError; end
end
