# frozen_string_literal: true

module Operations
  module AsyncMigrations
    module Handlers
      module IndividualMarketEligibility
        # This class is responsible for creating QHP applications.
        class CreateApplication
          include Dry::Monads[:do, :result]

          def call; end
        end
      end
    end
  end
end