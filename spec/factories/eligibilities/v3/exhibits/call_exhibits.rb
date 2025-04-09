# frozen_string_literal: true

FactoryBot.define do
  factory :call_exhibit, class: 'Eligibilities::V3::Exhibits::CallExhibit' do
    association :evidence, factory: :v3_evidence

    trait :with_document do
      after(:build) do |exhibit|
        exhibit.documents << build(:document)
      end
    end

    trait :with_state_history do
      after(:build) do |exhibit|
        exhibit.state_histories << build(:v3_state_history, status_trackable: exhibit)
      end
    end
  end
end
