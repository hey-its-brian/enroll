# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

# Syntax:
# Operations::FinancialAssistance::ExtendEvidenceDueOn.new.call({evidence: income_evidence, extension_days: 66})
module Operations
  module FinancialAssistance
    # Bulk ExtendEvidenceDueOn for evidence
    class ExtendEvidenceDueOn
      include Dry::Monads[:do, :result]

      # {evidence: income_evidence, extension_days: 66}
      def call(params)
        evidence, extension_days = yield validate(params)
        yield can_extend_due_on?(evidence)
        message = yield extend_due_on(evidence, extension_days)

        Success(message)
      end


      private

      def validate(params)
        return Failure('No evidence provided') unless params[:evidence].present?
        return Failure('No extension_days provided') unless params[:extension_days].present?

        Success([params[:evidence], params[:extension_days]])
      end

      def can_extend_due_on?(evidence)
        return Failure("evidence is not in outstanding state") unless ['outstanding', 'rejected'].include?(evidence.aasm_state)
        return Failure("evidence due date is blank or greater than today") if evidence.due_on.blank? || evidence.due_on > Date.today

        if evidence.key == :income
          auto_extend_verification_history = evidence.verification_histories.where(action: "auto_extend_due_date").order_by("date_of_action DESC").first

          if auto_extend_verification_history.present?
            verified_state_transition = evidence.workflow_state_transitions.where(:to_state => "verified", :transition_at.gt => auto_extend_verification_history.date_of_action).order_by("transition_at DESC").first
            return Failure("Income evidence is not eligible for extension") unless verified_state_transition.present?
          end
        end

        Success(true)
      end

      def extend_due_on(evidence, extension_days)
        current_due_on = evidence.due_on
        manually_extended_due_on = Date.today + extension_days.days
        evidence.assign_attributes(due_on: manually_extended_due_on)
        evidence.add_verification_history('manually_extend_due_date', "Manually extended due date from #{current_due_on.strftime('%m/%d/%Y')} to #{manually_extended_due_on.strftime('%m/%d/%Y')}", "Admin")

        Success("#{evidence.key} due date extended from #{current_due_on.strftime('%m/%d/%Y')} to #{manually_extended_due_on.strftime('%m/%d/%Y')}")
      end
    end
  end
end
