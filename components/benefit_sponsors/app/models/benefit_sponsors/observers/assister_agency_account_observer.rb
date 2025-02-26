# frozen_string_literal: true

module BenefitSponsors
  module Observers
    # Observer class to handle assister hire and fire events.
    class AssisterAgencyAccountObserver
      include ::Acapi::Notifiers

      attr_accessor :notifier

      def assister_hired?(account, _options = {})
        return unless !account.persisted? && account.valid? && account.benefit_sponsorship?

        profile = account.benefit_sponsorship.profile
        notify(
          "acapi.info.events.employer.assister_added",
          {
            employer_id: profile.hbx_id,
            event_name: "assister_added"
          }
        )
      end

      def assister_fired?(account, _options = {})
        return unless account.persisted? && account.changed? && account.changed_attributes.include?("end_on") && account.benefit_sponsorship.present?

        profile = account.benefit_sponsorship.profile
        notify(
          "acapi.info.events.employer.assister_terminated",
          {
            employer_id: profile.hbx_id,
            event_name: "assister_terminated"
          }
        )
      end

      private

      def initialize
        @notifier = BenefitSponsors::Services::NoticeService.new
      end

      def deliver(recipient:, event_object:, notice_event:, notice_params: {})
        notifier.deliver(recipient: recipient, event_object: event_object, notice_event: notice_event, notice_params: notice_params)
      end
    end
  end
end
