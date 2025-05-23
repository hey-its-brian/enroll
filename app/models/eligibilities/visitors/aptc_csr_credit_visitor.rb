# frozen_string_literal: true

module Eligibilities
  module Visitors
    # Use Visitor Development Pattern to access models and determine Non-ESI
    # eligibility status for a Family Financial Assistance Application's Applicants
    class AptcCsrCreditVisitor < Visitor
      include ::ResourceRegistryHelper

      attr_accessor :evidence, :subject, :evidence_item, :family

      def call
        application = application_instance_for(subject)
        unless application
          @evidence = Hash[evidence_item[:key], {}]
          return
        end

        application.accept(self)
      end

      def visit(applicant)
        return unless applicant.family_member_id == subject.id
        # return if evidence_item[:key].to_s == "income_evidence" && applicant.incomes.blank? comment this as per pivotal-186104816

        current_record = if qhp_application_feature_enabled?
                           applicant.aptc_csr_eligibility.fetch_evidence(evidence_item[:key])
                         else
                           applicant.send(evidence_item[:key])
                         end

        unless current_record
          @evidence = Hash[evidence_item[:key], {}]
          return
        end

        @evidence = evidence_state_for(current_record)
      end

      private

      def application_instance_for(subject)
        if qhp_application_feature_enabled?
          family.latest_application
        else
          subject.family.latest_determined_faa_application
        end
      end

      def evidence_state_for(evidence_record)
        ids = {
          'evidence_gid' => evidence_record.to_global_id.uri,
          'visited_at' => DateTime.now,
          'status' => qhp_application_feature_enabled? ? evidence_record.current_state : evidence_record.aasm_state
        }

        evidence_state_attributes =
          evidence_record
          .attributes
          .slice('is_satisfied', 'verification_outstanding', 'due_on')
          .merge(ids)

        due_on_value = evidence_state_attributes['due_on']
        evidence_state_attributes['due_on'] = due_on_value.to_date if due_on_value.is_a?(DateTime) || due_on_value.is_a?(Time)
        evidence_state_attributes.delete('due_on') if evidence_state_attributes['due_on'].blank?

        Hash[evidence_item[:key].to_sym, evidence_state_attributes.symbolize_keys]
      end
    end
  end
end
