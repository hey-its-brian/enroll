require "rails_helper"

if ExchangeTestingConfigurationHelper.individual_market_is_enabled?

describe "A new consumer role with an individual market enrollment", :dbclean => :around_each do
  let(:person) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role) }
  let(:family) { FactoryBot.create(:individual_market_family, primary_person: person) }
  let(:hbx_profile) { FactoryBot.create(:hbx_profile, :open_enrollment_coverage_period) }
  let(:product) { FactoryBot.create(:benefit_markets_products_health_products_health_product, benefit_market_kind: :aca_individual, kind: :health, csr_variant_id: '01') }
  let(:enrollment) do
    benefit_sponsorship = hbx_profile.benefit_sponsorship
    benefit_package = benefit_sponsorship.benefit_coverage_periods.first.benefit_packages.first
    enrollment = family.households.first.create_hbx_enrollment_from(
      coverage_household: family.households.first.coverage_households.first,
      consumer_role: person.consumer_role,
      benefit_package: hbx_profile.benefit_sponsorship.benefit_coverage_periods.first.benefit_packages.first
    )
    enrollment.product = product
    enrollment.select_coverage!
    enrollment
  end

  describe "when lawful presence fails verification" do
    let(:denial_information) do
      OpenStruct.new({ :determined_at => Time.now, :authority => 'ssa' })
    end

    before :each do
      person.consumer_role.coverage_purchased!("args")
    end

    describe "when the enrollment is active" do
      before :each do
        enrollment

        eligibility_determination = family.build_eligibility_determination(
          outstanding_verification_status: 'outstanding',
          effective_date: TimeKeeper.date_of_record
        )

        family_member = family.family_members.detect { |fm| fm.person_id == person.id }

        eligibility_determination.subjects.build(
          gid: "gid://enroll/FamilyMember/#{family_member.id}",
          person_id: person.id.to_s,
          hbx_id: person.hbx_id,
          is_primary: true,
          outstanding_verification_status: 'outstanding'
        )

        eligibility_determination.save!
        family.eligibility_determination = eligibility_determination
        family.save!

        person.consumer_role.ssn_invalid!(denial_information)
      end

      it "sets is_any_enrollment_member_outstanding field to true" do
        enroll = HbxEnrollment.by_hbx_id(enrollment.hbx_id).first
        expect(enroll.aasm_state).to eql "coverage_selected"
        expect(enroll.is_any_enrollment_member_outstanding).to eql true
      end
    end

    describe "when the enrollment is terminated" do
      before :each do
        enrollment.terminate_coverage!
        person.consumer_role.ssn_invalid!(denial_information)
      end

      it "does not change the state of the enrollment" do
        enroll = HbxEnrollment.by_hbx_id(enrollment.hbx_id).first
        expect(enroll.aasm_state).to eql "coverage_terminated"
      end
    end
  end
end

end
