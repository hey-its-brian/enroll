# frozen_string_literal: true

FactoryBot.define do
  factory :eligibilities_determination, class: '::Eligibilities::Determination' do
    effective_date { Date.today }
    outstanding_verification_status { 'pending' }
    outstanding_verification_earliest_due_date { Date.today + 30.days }
    outstanding_verification_document_status { 'outstanding' }

    transient do
      subject_count { 2 }
      subjects_with_outstanding { 1 }
    end

    after(:build) do |determination, evaluator|
      # Build subjects with outstanding verification requirements
      evaluator.subjects_with_outstanding.times do |_|
        determination.subjects << build(:eligibilities_subject, :with_outstanding_verification)
      end

      # Build subjects without outstanding verification requirements
      (evaluator.subject_count - evaluator.subjects_with_outstanding).times do |_|
        determination.subjects << build(:eligibilities_subject)
      end
    end
  end
end