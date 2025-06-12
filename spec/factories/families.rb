# frozen_string_literal: true

FactoryBot.define do
  factory :family do
    association :person
    sequence(:e_case_id) {|n| "abc#{n}12xyz#{n}"}
    renewal_consent_through_year  { 2017 }
    submitted_at { Time.now }
    updated_at { "user" }

    transient do
      people { [] }
    end

    trait :with_primary_family_member do
      family_members do
        [FactoryBot.build(:family_member, family: self,
                                          is_primary_applicant: true, is_active: true, person: person)]
      end
    end

    trait :with_family_members do
      family_members { people.map{|person| FactoryBot.build(:family_member, family: self, is_primary_applicant: (self.person == person), is_active: true, person: person) }}
    end

    trait :with_nuclear_family do
      before(:create) do |family, _evaluator|
        FactoryBot.build(:family_member, is_primary_applicant: true, is_active: true, person: family.person, family: family)

        { 'Kelly' => 'spouse', 'Danny' => 'child' }.each do |first_name, relationship|
          person = FactoryBot.create(:person, :with_consumer_role, first_name: first_name, last_name: family.person.last_name)
          family.person.person_relationships.push PersonRelationship.new(relative_id: person.id, kind: relationship)
          person.save
          FactoryBot.build(:family_member, is_primary_applicant: false, is_active: true, person: person, family: family)
        end
      end

      after(:create) do |family, evaluator|
        #new_person = FactoryBot.build :person, last_name: family.person.last_name
        #family.family_members.push FactoryBot.build(:family_member, is_primary_applicant: false, is_active: true, person: new_person, relationship: 'spouse')
      end
    end

    trait :with_primary_family_member_and_spouse_and_child do
      family_members do
        [
            FactoryBot.build(:family_member, family: self, is_primary_applicant: true, is_active: true, person: person),
            FactoryBot.build(:family_member, family: self, is_primary_applicant: false, is_active: true, person: FactoryBot.create(:person, first_name: "Jane", last_name: person.last_name)),
            FactoryBot.build(:family_member, family: self, is_primary_applicant: false, is_active: true, person:  FactoryBot.create(:person, first_name: "Alex", last_name: person.last_name))
        ]
      end
      before(:create)  do |family, _evaluator|
        family.dependents.each do |dependent|
          family.relate_new_member(dependent.person, "spouse") if dependent.person.first_name == 'Jane'
          family.relate_new_member(dependent.person, "child") if dependent.person.first_name == 'Alex'
        end
      end
    end

    after(:create) do |f, _evaluator|
      f.households.first.add_household_coverage_member(f.family_members.first)
      f.save
    end

    trait :with_primary_family_member_and_dependent do
      family_members do
        [
          FactoryBot.build(:family_member, family: self, is_primary_applicant: true, is_active: true, person: person),
          FactoryBot.build(:family_member, family: self, is_primary_applicant: false, is_active: true, person: FactoryBot.create(:person, first_name: "John", last_name: "Doe")),
          FactoryBot.build(:family_member, family: self, is_primary_applicant: false, is_active: true, person:  FactoryBot.create(:person, first_name: "Alex", last_name: "Doe"))
        ]
      end
      before(:create)  do |family, _evaluator|
        family.dependents.each do |dependent|
          family.relate_new_member(dependent.person, "child")
        end
      end
    end

    trait :with_eligibility_determination do
      transient do
        subject_count { 3 }
        subjects_with_action_needed { 1 }
        subjects_with_review { 1 }
        verification_status { 'outstanding' }
        verification_due_date { TimeKeeper.date_of_record }
        verification_document_status { 'pending' }
      end

      after(:build) do |family, evaluator|
        family.eligibility_determination = build(
          :eligibilities_determination,
          subject_count: evaluator.subject_count,
          outstanding_verification_status: evaluator.verification_status,
          outstanding_verification_earliest_due_date: evaluator.verification_due_date,
          outstanding_verification_document_status: evaluator.verification_document_status,
          subjects_with_action_needed: evaluator.subjects_with_action_needed,
          subjects_with_review: evaluator.subjects_with_review
        )
      end
    end

    trait :with_eligibility_determination_and_subjects do
      transient do
        outstanding_verification_status { 'outstanding' }
        eligibility_item_keys { [] }
        grants_config {[]}
        assistance_year { TimeKeeper.date_of_record.year }
        member_ids {[]}
        use_family_member_ids { false }
      end

      after(:build) do |family, evaluator|
        family.eligibility_determination = build(
          :eligibilities_determination
        )
        family.eligibility_determination.subjects = family.family_members.map do |family_member|
          build(:eligibilities_subject, outstanding_verification_status: evaluator.outstanding_verification_status, first_name: family_member.person.first_name,
                                        last_name: family_member.person.last_name,
                                        dob: family_member.person.dob,
                                        person_id: family_member.person.id,
                                        hbx_id: family_member.person.hbx_id,
                                        is_primary: family_member.is_primary_applicant)
        end

        # Add configurable parameters with defaults
        eligibility_item_keys = if evaluator.respond_to?(:eligibility_item_keys)
                                  evaluator.eligibility_item_keys
                                else
                                  %w[aca_individual_market_eligibility aptc_csr_credit]
                                end
        grants_config = if evaluator.respond_to?(:grants_config)
                          evaluator.grants_config
                        else
                          {
                            'aptc_csr_credit' => [
                              { key: 'CsrAdjustmentGrant', value: 0 },
                              { key: 'AdvancePremiumAdjustmentGrant' },
                              { key: 'MagiMedicaidGrant' }
                            ],
                            'aca_individual_market_eligibility' => [
                              { key: 'QhpGrant' }
                            ]
                          }
                        end

        assistance_year = if evaluator.respond_to?(:assistance_year)
                            evaluator.assistance_year
                          else
                            TimeKeeper.date_of_record.year
                          end

        actual_member_ids = if evaluator.use_family_member_ids
                              family.family_members.map(&:id).flat_map(&:to_s)
                            else
                              evaluator.member_ids
                            end

        grant_configs = grants_config['aptc_csr_credit'] || []
        family.eligibility_determination.grants = grant_configs&.collect do |config|
          build(:eligibilities_grant, key: config[:key], assistance_year: assistance_year, value: config[:value],
                                      title: config[:title],
                                      start_on: config[:start_on],
                                      end_on: config[:end_on],
                                      member_ids: actual_member_ids)
        end

        # Combined loop that adds both eligibility states and grants
        family.eligibility_determination.subjects.each do |subject|
          # Add eligibility states
          eligibility_item_keys.each do |determination_type|
            subject.eligibility_states << build(:eligibilities_eligibility_state, eligibility_item_key: determination_type) unless subject.eligibility_states.any? { |es| es.eligibility_item_key == determination_type }
          end

          # Add grants to each state
          subject.eligibility_states.each do |state|
            grant_configs = grants_config[state.eligibility_item_key]
            grant_configs&.each do |config|
              # Skip if the key is 'AdvancePremiumAdjustmentGrant' as it is created on determination grants
              next if config[:key] == 'AdvancePremiumAdjustmentGrant'

              state.grants << build(
                :eligibilities_grant,
                key: config[:key],
                assistance_year: assistance_year,
                value: config[:value],
                title: config[:title],
                start_on: config[:start_on],
                end_on: config[:end_on],
                member_ids: actual_member_ids
              )
            end
          end
        end
      end
    end
  end
end

FactoryBot.define do
  factory(:individual_market_family, class: Family) do

    transient do
      primary_person    { FactoryBot.create(:person, :with_consumer_role) }
      significant_other { FactoryBot.create(:person, :with_consumer_role, gender: "female") }
      disabled_child    do
        FactoryBot.create(:person, :with_consumer_role,
                          is_disabled: true,
                          dob: (Date.today - 27.years))
      end
      second_disabled_child    do
        FactoryBot.create(:person, :with_consumer_role,
                          first_name: "Tony",
                          is_disabled: true,
                          dob: (Date.today - 30.years))
      end
    end

    family_members do
      [
        FactoryBot.build(:family_member, family: self, is_primary_applicant: true, is_active: true,
                                         person: primary_person)
      ]
    end

    after(:create) do |f, _evaluator|
      f.households.first.add_household_coverage_member(f.family_members.first)
    end

    factory :individual_market_family_with_spouse do

      after(:create) do |f, evaluator|
        spouse = FactoryBot.create(:family_member, family: f, is_primary_applicant: false,
                                                   is_active: true, person: evaluator.significant_other)
        f.active_household.add_household_coverage_member(spouse)
      end

    end

    factory :individual_market_family_with_disabled_overage_child do

      after(:create) do |f, evaluator|
        child = FactoryBot.create(:family_member, family: f, is_primary_applicant: false,
                                                  is_active: true, person: evaluator.disabled_child)
        f.active_household.add_household_coverage_member(child)
      end

    end

    factory :individual_market_family_with_spouse_and_two_disabled_children do
      after(:create) do |f, evaluator|
        spouse = FactoryBot.create(:family_member, family: f, is_primary_applicant: false,
                                                   is_active: true, person: evaluator.significant_other)
        f.active_household.add_household_coverage_member(spouse)
        f.relate_new_member(spouse.person, "spouse")
        child = FactoryBot.create(:family_member, family: f, is_primary_applicant: false,
                                                  is_active: true, person: evaluator.disabled_child)
        f.active_household.add_household_coverage_member(child)
        f.relate_new_member(child.person, "child")
        second_child = FactoryBot.create(:family_member, family: f, is_primary_applicant: false,
                                                         is_active: true, person: evaluator.second_disabled_child)
        f.active_household.add_household_coverage_member(second_child)
        f.relate_new_member(second_child.person, "child")
      end
    end
  end
end
