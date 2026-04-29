module ActiveRecord
  # Persistence module — stores and updates the record.
  #
  # This is a fixture used to exercise the ingester end-to-end.
  module Persistence
    # Saves the record to the database.
    #
    # Returns true on success, false on validation failure.
    def save(**options)
      true
    end

    # Saves the record or raises an error.
    def save!(**options)
      true
    end

    # Class-level helper — creates a new persisted record.
    def self.create(attributes = {})
      new(attributes)
    end
  end
end
