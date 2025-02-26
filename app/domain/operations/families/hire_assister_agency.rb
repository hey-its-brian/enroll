# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

module Operations
  module Families
    # Operation to hire assister agency for a given family.
    class HireAssisterAgency
      include Dry::Monads[:do, :result]

      def call(params)
        valid_params = yield validate(params)
        assister_role = yield find_assister_role(valid_params)
        family = yield find_family(valid_params)
        existing_account = yield find_assister_agency_account(valid_params)
        result = yield hire_assister_agency(existing_account, assister_role, family, valid_params)

        Success(result)
      end

      private

      def validate(params)
        contract_result = Validators::Families::HireAssisterAgencyContract.new.call(params)
        contract_result.success? ? Success(contract_result.to_h) : Failure(contract_result.errors)
      end

      def find_assister_agency_account(params)
        return Success("") if params[:current_assister_account_id].blank?
        ::Operations::Families::FindAssisterAgencyAccount.new.call({assister_account_id: params[:current_assister_account_id], family_id: params[:family_id]})
      end

      def find_assister_role(valid_params)
        ::Operations::AssisterRole::Find.new.call(valid_params[:assister_role_id])
      end

      def find_family(valid_params)
        ::Operations::Families::Find.new.call(id: valid_params[:family_id])
      end

      def idempotency_check?(existing_account, assister_role, valid_params)
        return false unless existing_account.writing_agent.assister_org_id == assister_role.assister_org_id
        existing_account.end_on.blank? && valid_params[:terminate_date] <= valid_params[:start_date].to_date
      end

      def terminate_existing_assister_agency(family, valid_params)
        terminate_params = { family_id: valid_params[:family_id],
                             assister_account_id: valid_params[:current_assister_account_id],
                             terminate_date: valid_params[:terminate_date],
                             new_assister_hired: true,
                             notify_edi: false }
        family.publish_assister_fired_event(terminate_params)
      end

      def hire_assister_agency(existing_account, assister_role, family, valid_params)
        if existing_account.present?
          same_assister_hire = idempotency_check?(existing_account, assister_role, valid_params)
          return Success(true) if same_assister_hire
          terminate_existing_assister_agency(family, valid_params)
        end

        family.assister_agency_accounts.new(benefit_sponsors_assister_agency_profile_id: assister_role.benefit_sponsors_assister_agency_profile_id,
                                            writing_agent_id: assister_role.id,
                                            start_on: valid_params[:start_date] || Time.now,
                                            is_active: true)

        family.save! ? Success(true) : Failure("Unable to HireAssisterAgency")
      end
    end
  end
end
