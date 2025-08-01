# frozen_string_literal: true

FactoryBot.define do
  factory :individual_market_application, class: 'IndividualMarket::Application' do
    family do
      FactoryBot.create(
        :family,
        :with_primary_family_member,
        person: FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role)
      )
    end

    _type { 'IndividualMarket::Application' }

    hbx_id { SecureRandom.uuid }
    effective_on { TimeKeeper.date_of_record }
    submitted_at { nil }
    assistance_year { TimeKeeper.date_of_record.year }
    predecessor_id { nil }
    origin { :user }
    generation_reason { :manual }

    trait :renewal do
      generation_reason { :renewal }
      is_renewal { true }
      origin { :system }
      assistance_year { TimeKeeper.date_of_record.year.next }
      effective_on { TimeKeeper.date_of_record.next_year.beginning_of_year }
    end

    trait :with_primary do
      after(:build) do |application|
        application.applicants << FactoryBot.build(
          :individual_market_applicant,
          :with_person_name,
          :with_demographics,
          :with_eligibilities,
          application: application,
          family_member_id: application.family.primary_family_member.id
        )
      end
    end

    trait :with_applicants do
      after(:build) do |application|
        FactoryBot.build(:individual_market_applicant, :with_person_name, :with_demographics, :with_eligibilities, application: application)
        FactoryBot.build(:individual_market_applicant, :dependent, :with_person_name, :with_demographics, :with_eligibilities, application: application)
      end
    end

    # State traits
    trait :initial do
      current_state { :initial }
    end

    trait :submission_failed do
      current_state { :submission_failed }

      after(:create) do |app|
        app.state_histories.create(
          from_state: :initial,
          to_state: :submission_failed,
          transition_at: DateTime.now,
          event: :failed_submission
        )
      end
    end

    trait :submitted do
      current_state { :submitted }

      after(:create) do |app|
        app.state_histories.create(
          from_state: :initial,
          to_state: :submitted,
          transition_at: DateTime.now,
          event: :submit
        )
      end
    end

    trait :determination_failed do
      current_state { :determination_failed }

      after(:create) do |app|
        app.state_histories.create(
          from_state: :initial,
          to_state: :submitted,
          transition_at: DateTime.now - 1.hour,
          event: :submit
        )
        app.state_histories.create(
          from_state: :submitted,
          to_state: :determination_failed,
          transition_at: DateTime.now,
          event: :failed_determination
        )
      end
    end

    trait :determined do
      current_state { :determined }
      submitted_at { DateTime.now - 1.hour }

      after(:create) do |app|
        app.state_histories.create(
          from_state: :initial,
          to_state: :submitted,
          effective_on: DateTime.now - 1.hour,
          transition_at: DateTime.now - 1.hour,
          event: :submit
        )
        app.state_histories.create(
          from_state: :submitted,
          to_state: :determined,
          effective_on: DateTime.now,
          transition_at: DateTime.now,
          event: :determine
        )
      end
    end

    trait :expired do
      current_state { :expired }

      after(:create) do |app|
        app.state_histories.create(
          from_state: :initial,
          to_state: :expired,
          transition_at: DateTime.now,
          event: :expire
        )
      end
    end
  end
end
