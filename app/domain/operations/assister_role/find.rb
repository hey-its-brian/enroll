# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

module Operations
  module AssisterRole
    # Operation to find assister role.
    class Find
      include Dry::Monads[:do, :result]

      def call(obj_id)
        assister_role_id = yield validate(obj_id)
        assister = yield find_assister(assister_role_id)

        Success(assister)
      end

      private

      def validate(id)
        if id.present? && id.is_a?(BSON::ObjectId)
          Success(id)
        else
          Failure('id is nil or not in BSON format')
        end
      end

      def find_assister(assister_role_id)
        assister_role = ::AssisterRole.find(assister_role_id)

        assister_role.present? ? Success(assister_role) : Failure("Unable to find AssisterRole with ID #{assister_role_id}.")
      rescue StandardError
        Failure("Unable to find AssisterRole with ID2 #{assister_role_id}.")
      end
    end
  end
end
