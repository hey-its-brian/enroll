# frozen_string_literal: true

# rubocop:disable Lint/UselessAssignment, Style/DocumentDynamicEvalDefinition
module BenefitSponsors
  module ModelEvents
    #Model events for AssisterAgencyAccount to address observer pattern
    module AssisterAgencyAccount
      REGISTERED_EVENTS = [
        :assister_hired,
        :assister_fired
      ].freeze

      def notify_on_save
        if is_active_changed? && !is_active.nil?
          is_assister_hired = true if is_active

          is_assister_fired = true unless is_active
        end

        REGISTERED_EVENTS.each do |event|
          next unless (event_fired = instance_eval("is_#{event}", __FILE__, __LINE__))

          event_options = {}
          notify_observers(ModelEvent.new(event, self, event_options))
        rescue StandardError => e
          Rails.logger.info { "AssisterAgencyAccount REGISTERED_EVENTS: #{event} unable to notify observers" }
          raise e if Rails.env.test? # RSpec Expectation Not Met Error is getting rescued here
        end
      end
    end
  end
end

# rubocop:enable Lint/UselessAssignment, Style/DocumentDynamicEvalDefinition
