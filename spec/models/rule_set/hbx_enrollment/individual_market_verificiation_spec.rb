require "rails_helper"
require "#{BenefitSponsors::Engine.root}/spec/shared_contexts/benefit_market.rb"
require "#{BenefitSponsors::Engine.root}/spec/shared_contexts/benefit_application.rb"

describe RuleSet::HbxEnrollment::IndividualMarketVerification, :if => ExchangeTestingConfigurationHelper.individual_market_is_enabled?, dbclean: :around_each do
  include_context 'setup benefit market with market catalogs and product packages'
  include_context 'setup initial benefit application'

  subject { RuleSet::HbxEnrollment::IndividualMarketVerification.new(enrollment) }
  let(:effective_on) { TimeKeeper.date_of_record.beginning_of_year }
  let(:enrollment_status) { 'coverage_selected' }
  let(:product) {FactoryBot.build(:benefit_markets_products_product, benefit_market_kind: 'aca_individual') }

  let(:family)        { FactoryBot.create(:family, :with_primary_family_member) }
  let(:enrollment)    { FactoryBot.create(:hbx_enrollment,
                                          household: family.latest_household,
                                          family: family,
                                          effective_on: effective_on,
                                          kind: "individual",
                                          submitted_at: effective_on - 10.days,
                                          aasm_state: enrollment_status,
                                          product: product )}


  let(:shop_enrollment_verification) { RuleSet::HbxEnrollment::IndividualMarketVerification.new(shop_enrollment) }
  let(:current_effective_date) { TimeKeeper.date_of_record.beginning_of_month }
  let(:hired_on) { TimeKeeper.date_of_record - 3.months }
  let(:employee_created_at) { hired_on }
  let(:employee_updated_at) { employee_created_at }
  let(:shop_family) {FactoryBot.create(:family, :with_primary_family_member)}
  let(:census_employee) do
    create(:census_employee,
           :with_active_assignment,
           benefit_sponsorship: benefit_sponsorship,
           employer_profile: benefit_sponsorship.profile,
           benefit_group: current_benefit_package,
           hired_on: hired_on,
           created_at: employee_created_at,
           updated_at: employee_updated_at)
  end
  let(:employee_role) { FactoryBot.create(:employee_role, benefit_sponsors_employer_profile_id: abc_profile.id, hired_on: census_employee.hired_on, census_employee_id: census_employee.id) }
  let(:shop_enrollment) do
    FactoryBot.create(:hbx_enrollment,
                      household: shop_family.latest_household,
                      aasm_state: 'coverage_selected',
                      coverage_kind: 'health',
                      family: shop_family,
                      effective_on: current_effective_date,
                      enrollment_kind: 'open_enrollment',
                      kind: 'employer_sponsored',
                      submitted_at: effective_on - 10.days,
                      benefit_sponsorship_id: benefit_sponsorship.id,
                      sponsored_benefit_package_id: current_benefit_package.id,
                      sponsored_benefit_id: current_benefit_package.sponsored_benefits[0].id,
                      employee_role_id: employee_role.id,
                      benefit_group_assignment_id: census_employee.active_benefit_group_assignment.id)
  end

  describe "for a shop policy" do
    it "should not be applicable" do
      expect(shop_enrollment_verification.applicable?).to eq false
    end
  end

  describe "for an inactive individual policy" do
    let(:enrollment_status) { 'shopping' }
    it "should not be applicable" do
      expect(subject.applicable?).to eq false
    end
  end

  describe "for an active individual policy" do
    let(:enrollment_members) { [] }
    before(:each) do
      allow(enrollment).to receive(:hbx_enrollment_members).and_return(enrollment_members)
    end
    it "should be applicable" do
      expect(subject.applicable?).to eq true
    end
  end

  describe "determine the next state" do
    verification_states = %w(unverified ssa_pending dhs_pending verification_outstanding fully_verified verification_period_ended)
    verification_states.each do |state|
      obj=(state+"_person").to_sym
      let(obj) {
        person = FactoryBot.create(:person, :with_consumer_role)
        person.consumer_role.aasm_state = state
        person
      }
    end

    context "assigns proper states for people" do
      verification_states.each do |status|
        it "#{status}_person has #{status} aasm_state" do
          expect(eval("#{status}_person").consumer_role.aasm_state).to eq status
        end
      end
    end

    context "enrollment with fully verified member and status is_any_enrollment_member_outstanding false" do
      let(:enrollment_status) { 'coverage_selected' }
      let(:is_any_enrollment_member_outstanding) { false }

      it "return move_to_enrolled! event" do
        allow(subject).to receive(:roles_for_determination).and_return([fully_verified_person.consumer_role])
        expect(subject.determine_next_state).to eq [false, :do_nothing]
      end
    end

    context "enrollment with fully verified member and status not pending and is_any_enrollment_member_outstanding false" do
      let(:enrollment_status) { 'coverage_selected' }
      let(:is_any_enrollment_member_outstanding) { false }
      
      it 'should return do_nothing' do
        allow(subject).to receive(:roles_for_determination).and_return([fully_verified_person.consumer_role])
        expect(subject.determine_next_state).to eq [false, :do_nothing]
      end 
    end

    context "enrollment with outstanding member" do
      let(:enrollment_status) { 'coverage_selected' }

      before do
        allow(subject).to receive(:roles_for_determination).and_return([verification_outstanding_person.consumer_role])
        allow(subject).to receive(:any_outstanding?).and_return(true)
      end

      it "return move_to_enrolled! event along with true value" do
        expect(subject.determine_next_state).to eq [true, :do_nothing]
      end
    end

    context "selected enrollment with outstanding member" do
      let(:enrollment_status) { 'coverage_selected' }

      before do
        allow(subject).to receive(:roles_for_determination).and_return([verification_outstanding_person.consumer_role])
        allow(subject).to receive(:any_outstanding?).and_return(true)
      end

      it "return move_to_enrolled! event along with true value" do
        expect(subject.determine_next_state).to eq [true, :do_nothing]
      end
    end

    context "enrollment with verification_period_ended member" do
      it "return move_to_enrolled! event along with true value" do
        allow(subject).to receive(:roles_for_determination).and_return([verification_period_ended_person.consumer_role])
        expect(subject.determine_next_state).to eq [true, :do_nothing]
      end
    end

    context "enrollment with pending member" do
      it "return move_to_pending! event" do
        allow(subject).to receive(:roles_for_determination).and_return([ssa_pending_person.consumer_role])
        expect(subject.determine_next_state).to eq [false,:move_to_pending!]
      end
    end

    context "enrollment with mixed and outstanding members" do
      let(:enrollment_status) { 'unverified' }

      before do
        allow(subject).to receive(:roles_for_determination).and_return([verification_outstanding_person.consumer_role, fully_verified_person.consumer_role, ssa_pending_person.consumer_role])
        allow(subject).to receive(:any_outstanding?).and_return(true)
      end

      it "return move_to_enrolled! event along with true value" do
        expect(subject.determine_next_state).to eq [true, :move_to_enrolled!]
      end
    end

    context "enrollment with mixed, NO outstanding, with pending members" do
      it "return move_to_pending! event" do
        allow(subject).to receive(:roles_for_determination).and_return([ssa_pending_person.consumer_role, fully_verified_person.consumer_role, dhs_pending_person.consumer_role])
        expect(subject.determine_next_state).to eq [false,:move_to_pending!]
      end
    end
  end

  describe "#any_outstanding?" do
    let(:person1) { FactoryBot.create(:person, :with_consumer_role) }
    let(:person2) { FactoryBot.create(:person, :with_consumer_role) }
    let(:family) { FactoryBot.build(:family) }
    let(:enrollment) do
      FactoryBot.create(:hbx_enrollment,
                        household: family.latest_household,
                        family: family,
                        effective_on: effective_on,
                        kind: "individual",
                        submitted_at: effective_on - 10.days,
                        aasm_state: 'coverage_selected',
                        product: product)
    end
    let(:eligibility_determination) do
      family.build_eligibility_determination(
        outstanding_verification_status: 'outstanding',
        effective_date: TimeKeeper.date_of_record
      )
    end

    before do
      family.add_family_member(person1, is_primary_applicant: true)
      family.relate_new_member(person2, "spouse")
      family.save!

      person1_family_member = family.family_members.detect { |fm| fm.person_id == person1.id }
      person2_family_member = family.family_members.detect { |fm| fm.person_id == person2.id }

      FactoryBot.create(:hbx_enrollment_member,
                        hbx_enrollment: enrollment,
                        applicant_id: person1_family_member.id,
                        is_subscriber: true,
                        eligibility_date: effective_on,
                        coverage_start_on: effective_on)

      FactoryBot.create(:hbx_enrollment_member,
                        hbx_enrollment: enrollment,
                        applicant_id: person2_family_member.id,
                        is_subscriber: false,
                        eligibility_date: effective_on,
                        coverage_start_on: effective_on)

      enrollment.reload
      family.eligibility_determination = eligibility_determination
      family.save!
    end

    context "when there are no active subjects" do
      before do
        allow(subject).to receive(:active_subjects).and_return([])
      end

      it "returns false" do
        expect(subject.any_outstanding?).to be_falsey
      end
    end

    context "when active enrollment subjects have outstanding status" do
      before do
        person1_family_member = family.family_members.detect { |fm| fm.person_id == person1.id }
        person2_family_member = family.family_members.detect { |fm| fm.person_id == person2.id }

        eligibility_determination.subjects.build(
          gid: "gid://enroll/FamilyMember/#{person1_family_member.id}",
          person_id: person1.id.to_s,
          hbx_id: person1.hbx_id,
          is_primary: true,
          outstanding_verification_status: 'outstanding'
        )

        eligibility_determination.subjects.build(
          gid: "gid://enroll/FamilyMember/#{person2_family_member.id}",
          person_id: person2.id.to_s,
          hbx_id: person2.hbx_id,
          is_primary: false,
          outstanding_verification_status: 'verified'
        )

        eligibility_determination.save!
        family.save!
        enrollment.reload
      end

      it "returns true" do
        expect(subject.any_outstanding?).to be_truthy
      end
    end

    context "when active enrollment subjects do NOT have outstanding status" do
      before do
        person1_family_member = family.family_members.detect { |fm| fm.person_id == person1.id }
        person2_family_member = family.family_members.detect { |fm| fm.person_id == person2.id }

        eligibility_determination.subjects.build(
          gid: "gid://enroll/FamilyMember/#{person1_family_member.id}",
          person_id: person1.id.to_s,
          hbx_id: person1.hbx_id,
          is_primary: true,
          outstanding_verification_status: 'verified'
        )

        eligibility_determination.subjects.build(
          gid: "gid://enroll/FamilyMember/#{person2_family_member.id}",
          person_id: person2.id.to_s,
          hbx_id: person2.hbx_id,
          is_primary: false,
          outstanding_verification_status: 'verified'
        )

        eligibility_determination.save!
        family.save!
        enrollment.reload
      end

      it "returns false" do
        expect(subject.any_outstanding?).to be_falsey
      end
    end

    context "when only inactive family members have outstanding status" do
      let(:inactive_person) { FactoryBot.create(:person, :with_consumer_role) }

      before do
        family.relate_new_member(inactive_person, "child")
        family.save!

        inactive_family_member = family.family_members.detect { |fm| fm.person_id == inactive_person.id }
        inactive_family_member.update_attributes(is_active: false)

        FactoryBot.create(:hbx_enrollment_member,
                          hbx_enrollment: enrollment,
                          applicant_id: inactive_family_member.id,
                          is_subscriber: false,
                          eligibility_date: effective_on,
                          coverage_start_on: effective_on)

        person1_family_member = family.family_members.detect { |fm| fm.person_id == person1.id }
        person2_family_member = family.family_members.detect { |fm| fm.person_id == person2.id }

        eligibility_determination.subjects.build(
          gid: "gid://enroll/FamilyMember/#{person1_family_member.id}",
          person_id: person1.id.to_s,
          hbx_id: person1.hbx_id,
          is_primary: true,
          outstanding_verification_status: 'verified'
        )

        eligibility_determination.subjects.build(
          gid: "gid://enroll/FamilyMember/#{person2_family_member.id}",
          person_id: person2.id.to_s,
          hbx_id: person2.hbx_id,
          is_primary: false,
          outstanding_verification_status: 'verified'
        )

        eligibility_determination.subjects.build(
          gid: "gid://enroll/FamilyMember/#{inactive_family_member.id}",
          person_id: inactive_person.id.to_s,
          hbx_id: inactive_person.hbx_id,
          is_primary: false,
          outstanding_verification_status: 'outstanding'
        )

        eligibility_determination.save!
        family.save!
        enrollment.reload
      end

      it "returns false because inactive members are excluded" do
        expect(subject.any_outstanding?).to be_falsey
      end
    end

    context "when family members not in enrollment have outstanding status" do
      let(:non_enrolled_person) { FactoryBot.create(:person, :with_consumer_role) }

      before do
        family.relate_new_member(non_enrolled_person, "child")
        family.save!

        person1_family_member = family.family_members.detect { |fm| fm.person_id == person1.id }
        person2_family_member = family.family_members.detect { |fm| fm.person_id == person2.id }
        non_enrolled_member = family.family_members.detect { |fm| fm.person_id == non_enrolled_person.id }

        eligibility_determination.subjects.build(
          gid: "gid://enroll/FamilyMember/#{person1_family_member.id}",
          person_id: person1.id.to_s,
          hbx_id: person1.hbx_id,
          is_primary: true,
          outstanding_verification_status: 'verified'
        )

        eligibility_determination.subjects.build(
          gid: "gid://enroll/FamilyMember/#{person2_family_member.id}",
          person_id: person2.id.to_s,
          hbx_id: person2.hbx_id,
          is_primary: false,
          outstanding_verification_status: 'verified'
        )

        eligibility_determination.subjects.build(
          gid: "gid://enroll/FamilyMember/#{non_enrolled_member.id}",
          person_id: non_enrolled_person.id.to_s,
          hbx_id: non_enrolled_person.hbx_id,
          is_primary: false,
          outstanding_verification_status: 'outstanding'
        )

        eligibility_determination.save!
        family.save!
        enrollment.reload
      end

      it "returns false because non-enrolled members are excluded" do
        expect(subject.any_outstanding?).to be_falsey
      end
    end

    context "when multiple enrollment members have different statuses" do
      before do
        person1_family_member = family.family_members.detect { |fm| fm.person_id == person1.id }
        person2_family_member = family.family_members.detect { |fm| fm.person_id == person2.id }

        eligibility_determination.subjects.build(
          gid: "gid://enroll/FamilyMember/#{person1_family_member.id}",
          person_id: person1.id.to_s,
          hbx_id: person1.hbx_id,
          is_primary: true,
          outstanding_verification_status: 'verified'
        )

        eligibility_determination.subjects.build(
          gid: "gid://enroll/FamilyMember/#{person2_family_member.id}",
          person_id: person2.id.to_s,
          hbx_id: person2.hbx_id,
          is_primary: false,
          outstanding_verification_status: 'outstanding'
        )

        eligibility_determination.save!
        family.save!
        enrollment.reload
      end

      it "returns true if ANY active enrollment member has outstanding" do
        expect(subject.any_outstanding?).to be_truthy
      end
    end
  end

  describe "#extract_family_member_id_from_gid" do
    let(:object_id) { BSON::ObjectId.new }
    let(:gid) { "gid://enroll/FamilyMember/#{object_id}" }

    it "extracts ObjectId from gid string" do
      result = subject.extract_family_member_id_from_gid(gid)
      expect(result).to eq(object_id)
      expect(result).to be_a(BSON::ObjectId)
    end

    it "handles gid as URI object" do
      gid_uri = URI(gid)
      result = subject.extract_family_member_id_from_gid(gid_uri)
      expect(result).to eq(object_id)
    end
  end
end