# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

module Operations
  module Families
    # Operation to terminate assister agency for a given family.
    class TerminateAssisterAgency
      include Dry::Monads[:do, :result]

      def call(params)
        valid_params = yield validate(params)
        agency_account = yield find_assister_agency_account(valid_params)
        _family = yield find_family(valid_params)
        _assister_role = agency_account.writing_agent
        result = yield terminate_assister_agency(agency_account, valid_params)
        Success(result)
      end

      private

      def validate(params)
        contract_result = Validators::Families::TerminateAssisterAgencyContract.new.call(params)
        contract_result.success? ? Success(contract_result.to_h) : Failure(contract_result.errors)
      end

      def find_assister_agency_account(params)
        ::Operations::Families::FindAssisterAgencyAccount.new.call(params)
      end

      def terminate_assister_agency(account, params)
        result = account.update_attributes!(end_on: (params[:terminate_date].to_date - 1.day).end_of_day, is_active: false)
        result ? Success(true) : Failure("Unable to TerminateAssisterAgency")
      end

      def find_family(valid_params)
        ::Operations::Families::Find.new.call(id: valid_params[:family_id])
      end
    end
  end
end
