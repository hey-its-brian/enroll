# frozen_string_literal: true

module Exchanges
  # Helper makes the view helper methods available views.
  module AssisterApplicantsHelper
    def sort_by_latest_transition_time(assister_applicants)
      assister_applicants.sort_by { |applicant| applicant.assister_role.workflow_state_transitions.last&.created_at }.reverse
    end
  end
end
