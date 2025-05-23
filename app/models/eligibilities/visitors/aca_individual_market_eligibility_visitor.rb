# frozen_string_literal: true

module Eligibilities
  module Visitors
    # Individual market eligibility visitor
    class AcaIndividualMarketEligibilityVisitor < Visitor
      include ::ResourceRegistryHelper

      attr_accessor :evidence, :subject, :evidence_item, :family

      OUTSTANDING_STATES = %w[outstanding review rejected].freeze
      PENDING_STATES = %w[pending unverified negative_response_received].freeze

      def call
        if qhp_application_feature_enabled?
          application = application_instance_for(subject)
          unless application
            @evidence = Hash[evidence_item[:key], {}]
            return
          end

          application.accept(self)
        else
          person = subject.person
          person.accept(self)
        end
      end

      def visit(applicant_or_verification_type)
        if qhp_application_feature_enabled?
          applicant_visitor(applicant_or_verification_type)
        else
          verification_type_visitor(applicant_or_verification_type)
        end
      end

      private

      def applicant_visitor(applicant)
        return unless applicant.family_member_id == subject.id
        # return if evidence_item[:key].to_s == "income_evidence" && applicant.incomes.blank? comment this as per pivotal-186104816

        current_record = applicant.individual_market_eligibility.fetch_evidence(evidence_item[:key])

        unless current_record
          @evidence = Hash[evidence_item[:key], {}]
          return
        end

        @evidence = evidence_state_for(current_record)
      end

      def evidence_state_for(evidence_record)
        ids = {
          'evidence_gid' => evidence_record.to_global_id.uri,
          'visited_at' => DateTime.now,
          'status' => evidence_record.current_state
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

      def verification_type_visitor(verification_type)
        evidence_key = evidence_item.key.downcase == "residency" ? "#{site_key}_residency" : evidence_item.key
        return unless verification_type.type_name.downcase == evidence_key.titleize.downcase

        status_for = status_for(verification_type)
        evidence_state_attributes = {
          status: status_for,
          visited_at: DateTime.now,
          evidence_gid: verification_type.to_global_id.uri
        }

        if OUTSTANDING_STATES.include?(verification_type.validation_status)
          evidence_state_attributes[:is_satisfied] = false
          evidence_state_attributes[:verification_outstanding] = true
          evidence_state_attributes[:due_on] = verification_type.due_date
        elsif verification_type.type_verified? || PENDING_STATES.include?(status_for)
          evidence_state_attributes[:is_satisfied] = true
          evidence_state_attributes[:verification_outstanding] = false
          evidence_state_attributes[:due_on] = nil
        end

        @evidence =
          Hash[
            evidence_item[:key].to_sym,
            evidence_state_attributes.symbolize_keys
          ]
      end

      def application_instance_for(subject)
        if qhp_application_feature_enabled?
          family.latest_application
        else
          subject.family.latest_determined_faa_application
        end
      end

      def status_for(verification_type)
        return verification_type.validation_status if (['review'] + PENDING_STATES).include?(verification_type.validation_status)

        verification_type.type_verified? ? 'determined' : 'outstanding'
      end
    end
  end
end
