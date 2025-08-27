# frozen_string_literal: true

module Operations
  module AsyncMigrations
    module Handlers
      module People
        module BookmarkURL
          # Fetch people without determined financial assistance applications.
          # This operation can be retriggered multiple times, and it will only return people that do not have determined QHP applications.
          class FetchEligiblePersonRecords
            include Dry::Monads[:do, :result]

            def call(_params)
              yield fetch_person_ids
            end

            private

            def fetch_person_ids
              result = Person.where(
                :consumer_role.exists => true,
                '$or' => [
                  { 'consumer_role.identity_validation' => 'valid' },
                  { 'consumer_role.application_validation' => 'valid' }
                ]
              ).only(:_id)


              Success(result.pluck(:id))
            rescue StandardError => e
              Failure("Failed to fetch people: #{e.message}")
            end
          end
        end
      end
    end
  end
end


