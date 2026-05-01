# frozen_string_literal: true

module ActiveRecord
  # Base class for Active Record models.
  class Base
    DEFAULT_PER_PAGE = 25

    include Persistence

    attr_accessor :name
  end
end
