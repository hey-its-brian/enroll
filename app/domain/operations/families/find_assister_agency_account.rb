# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

module Operations
  module Families
    # Operation to find assister agency account for a given family
    class FindAssisterAgencyAccount
      include Dry::Monads[:do, :result]

      def call(params)
        valid_params = yield validate(params)
        assister_agency_account = yield find_assister_agency_account(valid_params)

        Success(assister_agency_account)
      end

      private

      def validate(params)
        if params[:family_id].is_a?(BSON::ObjectId) && params[:assister_account_id].is_a?(BSON::ObjectId)
          Success(params)
        else
          Failure('Invalid params for AssisterAgencyAccount')
        end
      end

      def find_assister_agency_account(valid_params)
        result = ::Operations::Families::Find.new.call(id: valid_params[:family_id])
        return Failure("Unable to find AssisterAgencyAccount with ID #{valid_params[:assister_account_id]} for Family #{valid_params[:family_id]}.") unless result&.success?

        account = result.success.assister_agency_accounts.unscoped.find(valid_params[:assister_account_id])
        account.present? ? Success(account) : Failure("Unable to find AssisterAgencyAccount with ID #{valid_params[:assister_account_id]} for Family #{valid_params[:family_id]}.")
      rescue StandardError
        Failure("Unable to find AssisterAgencyAccount with ID #{valid_params[:assister_account_id]} for Family #{valid_params[:family_id]}.")
      end
    end
  end
end
