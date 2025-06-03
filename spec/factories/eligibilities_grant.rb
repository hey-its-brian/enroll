# frozen_string_literal: true

FactoryBot.define do
  factory :eligibilities_grant, class: '::Eligibilities::Grant' do
    key {'AdvancePremiumAdjustmentGrant'}
    start_on { TimeKeeper.date_of_record.beginning_of_month }
    end_on { TimeKeeper.date_of_record.end_of_month }
    title { 'Advance Premium Adjustment Grant' }
    assistance_year { TimeKeeper.date_of_record.year }
    value { '0' }
    member_ids { [] }
  end
end
