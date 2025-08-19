# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

module Operations
  module IndividualMarket
    module Application
      # This class is responsible for transforming an Individual Market Application into a CV3 entity.
      class TransformToEntity
        include Dry::Monads[:do, :result]

        def call(application)
          cv3_application = yield construct_cv3_application(application)
          payload_entity = yield construct_payload_entity(cv3_application)

          Success(payload_entity)
        end

        private

        def construct_cv3_application(application)
          if application.is_a?(::IndividualMarket::Application)

            begin
              Transformers::ApplicationTo::Cv3Application.new.call(application)
            rescue StandardError => e
              Failure(e.message)
            end
          else
            Failure("Could not generate CV3 Application -- wrong object type")
          end
        end

        def construct_payload_entity(cv3_application)
          AcaEntities::IndividualMarket::Operations::Applications::Create.new.call(cv3_application)
        end
      end
    end
  end
end