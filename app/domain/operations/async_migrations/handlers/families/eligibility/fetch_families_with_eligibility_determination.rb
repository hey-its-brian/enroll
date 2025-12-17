# frozen_string_literal: true

require "dry/monads"

module Operations
  module AsyncMigrations
    module Handlers
      module Families
        module Eligibility
          # Fetch families with eligibility determinations.
          class FetchFamiliesWithEligibilityDetermination
            include Dry::Monads[:do, :result]

            def call(params)
              created_at = yield validate(params)
              yield families_with_eligibility_determination(created_at)
            end

            private

            def validate(params)
              return Failure("Invalid params provided") if params.empty? || params[:additional_params].nil? || params[:additional_params][:created_at].nil?
              created_at = params[:additional_params][:created_at]

              Success(created_at.to_date)
            end

            # Since the batch requester is expecting an operation, we cannot use the query directly in the mappings file
            def families_with_eligibility_determination(created_at)
              families_on_or_before = HbxEnrollment.where(
                :aasm_state.in => HbxEnrollment::ENROLLED_AND_RENEWAL_STATUSES,
                :created_at.lte => created_at
              ).only(:family_id).distinct(:family_id)

              families_after_cutoff = HbxEnrollment.where(
                :aasm_state.in => HbxEnrollment::ENROLLED_AND_RENEWAL_STATUSES,
                :created_at.gt => created_at
              ).only(:family_id).distinct(:family_id)


              eligible_family_ids = families_on_or_before - families_after_cutoff
              families_ids_with_determination = Family.where(:eligibility_determination.exists => true, :_id.in => eligible_family_ids).only(:_id).pluck(:id)

              Success(families_ids_with_determination)
            end
          end
        end
      end
    end
  end
end