# frozen_string_literal: true

module Operations
  module Eligibilities
    module Evidences
      # Update class handles the verification actions for evidence records
      class Update
        include Dry::Monads[:do, :result]

        # Handles the update of evidence verification status
        #
        # @param params [Hash] update parameters including evidence, admin_action, and update_reason
        # @return [Dry::Monads::Result] Success with message or Failure with error message
        def call(params)
          _validated_params = yield validate(params)
          verification_result = yield process_verification_action
          _persist_result = yield persist_changes

          Success(verification_result)
        end

        private

        def validate(params)
          return Failure("Evidence is required") if params[:evidence].blank?
          return Failure("Admin action is required") if params[:admin_action].blank?
          return Failure("Update reason is required") if params[:update_reason].blank?
          return Failure("Application is required") if params[:application].blank?

          @evidence = params[:evidence]
          @application = params[:application]
          @admin_action = params[:admin_action]
          @update_reason = params[:update_reason]
          @current_user = params[:current_user]

          Success(params)
        end

        # Processes the verification action based on admin_action
        #
        # @param params [Hash] validated parameters
        # @return [Dry::Monads::Result] Success with message or Failure with error message
        def process_verification_action
          actor = @current_user ? @current_user.oim_id : "system"
          evidence_key = @evidence.key.split("_").join(" ").capitalize

          case @admin_action
          when "verify"
            _result = yield verify_evidence(actor)
            Success("#{evidence_key} successfully verified.")
          when "return_for_deficiency"
            _result = yield reject_evidence(actor)
            Success("#{evidence_key} rejected.")
          else
            Failure("Invalid admin action: #{@admin_action}")
          end
        rescue StandardError => e
          Rails.logger.error("Evidence Update - Error processing verification action: #{e.message}")
          Failure("Verification action failed: #{e.message}")
        end

        # Marks evidence as verified and adds history
        #
        # @param actor [String] the actor performing the action
        # @return [Dry::Monads::Result] Success or Failure
        def verify_evidence(actor)
          @evidence.mark_as_verified
          @evidence.build_verification_history(@admin_action, @update_reason, actor)
          Success(@evidence)
        rescue StandardError => e
          Rails.logger.error("Evidence Update - Error verifying evidence: #{e.message}")
          Failure("Evidence verification failed: #{e.message}")
        end

        # Marks evidence as rejected and adds history
        #
        # @param actor [String] the actor performing the action
        # @return [Dry::Monads::Result] Success or Failure
        def reject_evidence(actor)
          @evidence.mark_as_rejected
          @evidence.build_verification_history(@admin_action, @update_reason, actor)
          Success(@evidence)
        rescue StandardError => e
          Rails.logger.error("Evidence Update - Error rejecting evidence: #{e.message}")
          Failure("Evidence rejection failed: #{e.message}")
        end

        # Persists all changes to the application
        #
        # @return [Dry::Monads::Result] Success with application or Failure with error message
        def persist_changes
          Success(@application) if @application.save!
        rescue StandardError => e
          Rails.logger.error("Evidence Update - Application save failed: #{e.message}")
          Failure("Application save failed: #{e.message}")
        end
      end
    end
  end
end
