# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "_summary.html.slim.rb", :type => :view, dbclean: :after_each  do
  before do
    DatabaseCleaner.clean
  end

  let(:aws_env) { ENV['AWS_ENV'] || "qa" }
  let(:user) { FactoryBot.create(:user, person: person) }
  let!(:county_zip) { BenefitMarkets::Locations::CountyZip.create!(county_name: "Hampden", state: 'ME', zip: "01001")}
  let(:person) {FactoryBot.create(:person)}
  let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person)}
  let(:active_household) {family.active_household}
  let(:hbx_enrollment_member){ FactoryBot.build(:hbx_enrollment_member, is_subscriber: true, applicant_id: family.family_members.first.id, coverage_start_on: TimeKeeper.date_of_record, eligibility_date: TimeKeeper.date_of_record) }
  let!(:rating_area) do
    ::BenefitMarkets::Locations::RatingArea.rating_area_for(address, during: effective_date) || FactoryBot.create_default(:benefit_markets_locations_rating_area, active_year: effective_date.year)
  end
  let!(:effective_date) { TimeKeeper.date_of_record.beginning_of_year }
  let!(:address) { family.primary_person.rating_address }
  let(:kind) { 'individual' }
  let(:hbx_enrollment) do
    FactoryBot.create(:hbx_enrollment,household: active_household, kind: kind, family: family, hbx_enrollment_members: [hbx_enrollment_member], rating_area_id: rating_area.id, product: product, applied_aptc_amount: Money.new(50_00))
  end
  let(:member_enrollment) {BenefitSponsors::Enrollments::MemberEnrollment.new(member_id: hbx_enrollment_member.id, product_price: BigDecimal(100),sponsor_contribution: BigDecimal(100))}
  let(:group_enrollment) {BenefitSponsors::Enrollments::GroupEnrollment.new(product: mock_product, member_enrollments: [member_enrollment])}
  let(:member_group) {double(attrs.merge(group_enrollment: group_enrollment))}
  let(:mock_issuer_profile) { double("IssuerProfile", :dba => "a carrier name", :legal_name => "name") }
  let!(:application_period) { effective_date.beginning_of_year..effective_date.end_of_year }
  let!(:service_area) do
    ::BenefitMarkets::Locations::ServiceArea.service_areas_for(address, during: effective_date).first || FactoryBot.create_default(:benefit_markets_locations_service_area, active_year: effective_date.year)
  end

  let!(:product) do
    prod =
      FactoryBot.create(
        :benefit_markets_products_health_products_health_product,
        :with_issuer_profile,
        :silver,
        benefit_market_kind: :aca_individual,
        kind: :health,
        application_period: application_period,
        service_area: service_area,
        csr_variant_id: '01'
      )
    prod.premium_tables = [premium_table]
    prod.save
    prod
  end

  let!(:premium_table)        { build(:benefit_markets_products_premium_table, effective_period: application_period, rating_area: rating_area) }
  let!(:tax_household_group) do
    family.tax_household_groups.create!(
      assistance_year: TimeKeeper.date_of_record.year,
      source: 'Faa',
      start_on: TimeKeeper.date_of_record.beginning_of_year,
      tax_households: [
        FactoryBot.build(:tax_household, household: family.active_household)
      ]
    )
  end

  let!(:tax_household) do
    tax_household_group.tax_households.first
  end

  let!(:thhm_enrollment_members) do
    hbx_enrollment.hbx_enrollment_members.collect do |member|
      FactoryBot.build(:tax_household_member_enrollment_member, hbx_enrollment_member_id: member.id, family_member_id: member.applicant_id, tax_household_member_id: "123")
    end
  end

  let!(:thhe) do
    tax_household_enrollment = FactoryBot.build(:tax_household_enrollment, enrollment_id: hbx_enrollment.id, tax_household_id: tax_household.id,
                                                                           health_product_hios_id: hbx_enrollment.product.hios_id,
                                                                           household_health_benchmark_ehb_premium: Money.new(100_000),
                                                                           household_dental_benchmark_ehb_premium: Money.new(50_000),
                                                                           dental_product_hios_id: nil, tax_household_members_enrollment_members: thhm_enrollment_members)
    tax_household_enrollment.save
    tax_household_enrollment
  end

  let(:mock_product) do
    double(
      "Product",
      attrs
    )
  end

  let(:attrs) do
    {
      :active_year => 2018,
      :title => "A Plan Name",
      :carrier_profile_id => "a carrier profile id",
      :issuer_profile => mock_issuer_profile,
      :metal_level_kind => "Silver",
      :product_type => "A plan type",
      :nationwide => true,
      :network_information => "This is a test",
      :deductible => 0,
      :total_premium => 100.00,
      :total_employer_contribution => 0,
      :total_employee_cost => 100.00,
      :rx_formulary_url => "http://www.example.com",
      :provider_directory_url => "http://www.example1.com",
      :ehb => 0.988,
      :hios_id => "89789DC0010006-01",
      :id => "1234234234",
      :kind => :health,
      :health_plan_kind => "HMO",
      :sbc_file => "THE SBC FILE.PDF",
      :is_standard_plan => true,
      standard_plan_label: 'STANDARD PLAN',
      metal_level: 'Bronze',
      network: 'nationwide',
      :can_use_aptc? => true,
      total_ehb_premium: 99.00,
      total_childcare_subsidy_amount: 0.0,
      :sbc_document => document
    }
  end

  let(:document) do
    Document.new(
      {
        title: 'sbc_file_name',
        subject: "SBC",
        :identifier => "urn:openhbx:terms:v1:file_storage:s3:bucket:#{EnrollRegistry[:enroll_app].setting(:s3_prefix).item}"\
        "-enroll-sbc-#{aws_env}#7816ce0f-a138-42d5-89c5-25c5a3408b82"
      }
    )
  end
  let(:mock_qhp_cost_share_variance) { instance_double(Products::QhpCostShareVariance, :qhp_service_visits => []) }
  let(:mock_request) { double }

  before :each do
    allow(view).to receive(:request).and_return(mock_request)
    allow(mock_request).to receive(:referrer).and_return('')
    allow(mock_issuer_profile).to receive(:abbrev).and_return("MOCK_CARRIER")
    Caches::MongoidCache.release(CarrierProfile)
    allow(person).to receive(:primary_family).and_return(family)
    allow(family).to receive(:enrolled_hbx_enrollments).and_return([hbx_enrollment])
    assign :person, person
    assign :plan, mock_product
    assign :hbx_enrollment, hbx_enrollment
    assign :member_group, member_group
    sign_in user
  end

  it "should display standard plan indicator" do
    render "ui-components/v1/cards/summary", :qhp => mock_qhp_cost_share_variance
    expect(rendered).to have_content(/STANDARD PLAN/i)
  end

  it 'should display premium amount' do
    render 'ui-components/v1/cards/summary', qhp: mock_qhp_cost_share_variance
    expect(rendered).to include('$100.00')
  end

  context "with no rx_formulary_url and provider urls for coverage_kind = dental" do
    before :each do
      assign :coverage_kind, "dental"
      allow(mock_product).to receive(:kind).and_return("dental")
      allow(mock_product).to receive(:dental_level).and_return("high")
      allow(mock_product).to receive(:rx_formulary_url).and_return nil
      render "ui-components/v1/cards/summary", :qhp => mock_qhp_cost_share_variance
    end

    it "should not have coinsurance text" do
      expect(rendered).not_to have_selector('th', text: 'COINSURANCE')
    end

    it "should not have copay text" do
      expect(rendered).not_to have_selector('th', text: 'CO-PAY')
    end
  end

  context "with no provider_directory_url and rx_formulary_urls with coverage_kind = health" do

    before :each do
      assign(:coverage_kind, "health")
      render "ui-components/v1/cards/summary", :qhp => mock_qhp_cost_share_variance
    end

    it "should have a link to download the sbc pdf" do
      expect(rendered).to have_selector(
        "a[href='#{"/documents/#{document.id}/product_sbc_download?product_id=#{mock_product.id}&content_type=application/pdf&filename=APlanName.pdf"\
        '&disposition=inline'}']"
      )
    end

    it "should have a label 'Summary of Benefits and Coverage (SBC)'" do
      expect(rendered).to include('Summary of Benefits and Coverage')
    end

    it "should not have 'having a baby'" do
      expect(rendered).not_to have_selector("h4", text: "Having a Baby")
    end

    it "should not have 'managing type diabetes'" do
      expect(rendered).not_to have_selector("h4", text: "Managing Type 2 Diabetes")
    end
  end

  context "provider_directory_url and rx_formulary_url" do

    it "should have rx formulary url coverage_kind = health" do
      render "ui-components/v1/cards/summary", :qhp => mock_qhp_cost_share_variance
      expect(rendered).to match(/#{mock_product.rx_formulary_url}/)
    end

    it "should not have rx_formulary_url coverage_kind = dental" do
      allow(mock_product).to receive(:kind).and_return("dental")
      allow(member_group).to receive(:kind).and_return("dental")
      allow(mock_product).to receive(:dental_level).and_return("high")
      render "ui-components/v1/cards/summary", :qhp => mock_qhp_cost_share_variance
      expect(rendered).to_not match(/#{mock_product.rx_formulary_url}/)
    end

    it "should have provider directory url if nationwide = true" do
      render "ui-components/v1/cards/summary", :qhp => mock_qhp_cost_share_variance
      expect(rendered).to match(/#{mock_product.provider_directory_url}/)
      expect(rendered).to match("PROVIDER DIRECTORY")
    end

    it "should not have provider directory url if issuer is excluded" do
      allow(view).to receive(:offers_nationwide_plans?).and_return(true)
      allow(mock_product).to receive(:provider_directory_url).and_return("mock_url")
      allow(mock_product).to receive(:issuer_profile).and_return(mock_issuer_profile)
      allow(mock_issuer_profile).to receive(:abbrev).and_return("GHMSI")
      render "ui-components/v1/cards/summary", :qhp => mock_qhp_cost_share_variance
      expect(rendered).to_not match(/#{mock_product.provider_directory_url}/)
      expect(rendered).to_not match("PROVIDER DIRECTORY")
    end

    it "should not have provider directory url if nationwide = false(for ma)" do
      allow(view).to receive(:offers_nationwide_plans?).and_return(false)
      allow(mock_product).to receive(:nationwide).and_return(false)
      render "ui-components/v1/cards/summary", :qhp => mock_qhp_cost_share_variance
      expect(rendered).to_not match(/#{mock_product.provider_directory_url}/)
    end

    it "should not have provider directory url if url is nil" do
      allow(view).to receive(:offers_nationwide_plans?).and_return(true)
      allow(mock_product).to receive(:provider_directory_url).and_return(nil)
      allow(member_group).to receive(:provider_directory_url).and_return(nil)
      render "ui-components/v1/cards/summary", :qhp => mock_qhp_cost_share_variance
      expect(rendered).to_not match("PROVIDER DIRECTORY")
    end
  end

  context 'for display of enrollment additional summary with admin' do
    let(:hbx_staff_user) { FactoryBot.create(:user, person: hbx_staff_person) }
    let(:hbx_staff_person) {FactoryBot.create(:person, :with_hbx_staff_role)}

    before do
      allow(EnrollRegistry).to receive(:feature_enabled?).and_return(false)
      allow(EnrollRegistry).to receive(:feature_enabled?).with(:display_enr_summary).and_return(true)
      allow(EnrollRegistry).to receive(:feature_enabled?).with(:crm_publish_primary_subscriber).and_return(true)
      allow(EnrollRegistry).to receive(:feature_enabled?).with(:check_for_crm_updates).and_return(false)
      allow(EnrollRegistry).to receive(:feature_enabled?).with(:validate_quadrant).and_return(true)
      allow(EnrollRegistry).to receive(:feature_enabled?).with(:display_county).and_return(false)
      allow(EnrollRegistry).to receive(:feature_enabled?).with(:financial_assistance).and_return(true)
      allow(view).to receive(:display_carrier_logo).and_return('logo/carrier/uhic.jpg')
      sign_in hbx_staff_user
      render 'ui-components/v1/cards/summary', :qhp => mock_qhp_cost_share_variance
    end

    it 'should include enrollment effective_on text' do
      expect(rendered).to have_content(l10n('enrollment.effective_on'))
    end

    it 'should include latest transition text' do
      expect(rendered).to have_content(l10n('enrollment.transitions'))
    end

    it 'should include Product HIOS ID text' do
      expect(rendered).to have_content(l10n('product_hios_id'))
    end

    it 'should include RatingArea text' do
      expect(rendered).to have_content(l10n('rating_area.exchange_provided_code'))
    end

    it 'should include full name of person' do
      expect(rendered).to have_content(hbx_enrollment_member.person.full_name.titleize)
    end

    it 'should include premium of the enrollment' do
      expect(rendered).to have_content(hbx_enrollment.total_premium)
    end
  end

  context 'for display of enrollment additional summary with consumer' do
    before do
      allow(EnrollRegistry).to receive(:feature_enabled?).and_return(false)
      allow(EnrollRegistry).to receive(:feature_enabled?).with(:display_enr_summary).and_return(true)
      allow(EnrollRegistry).to receive(:feature_enabled?).with(:crm_publish_primary_subscriber).and_return(true)
      allow(EnrollRegistry).to receive(:feature_enabled?).with(:validate_quadrant).and_return(true)
      allow(EnrollRegistry).to receive(:feature_enabled?).with(:display_county).and_return(true)
      allow(EnrollRegistry).to receive(:feature_enabled?).with(:financial_assistance).and_return(true)
      allow(view).to receive(:display_carrier_logo).and_return('logo/carrier/uhic.jpg')
      sign_in user
      render 'ui-components/v1/cards/summary', :qhp => mock_qhp_cost_share_variance
    end

    it 'should not include enrollment effective_on text' do
      expect(rendered).to_not have_content(l10n('enrollment.effective_on'))
    end

    it 'should not include latest transition text' do
      expect(rendered).to_not have_content(l10n('enrollment.transitions'))
    end

    it 'should not include Product HIOS ID text' do
      expect(rendered).to_not have_content(l10n('product_hios_id'))
    end

    it 'should not include RatingArea text' do
      expect(rendered).to_not have_content(l10n('rating_area.exchange_provided_code'))
    end

    it 'should not include full name of person' do
      expect(rendered).to_not have_content(hbx_enrollment_member.person.full_name.titleize)
    end
  end

  context 'for display of enrollment additional summary with consumer with feature disabled' do
    before do
      allow(view).to receive(:display_carrier_logo).and_return('logo/carrier/uhic.jpg')
      sign_in user
      render 'ui-components/v1/cards/summary', :qhp => mock_qhp_cost_share_variance
    end

    it 'should not include enrollment effective_on text' do
      expect(rendered).to_not have_content(l10n('enrollment.effective_on'))
    end

    it 'should not include latest transition text' do
      expect(rendered).to_not have_content(l10n('enrollment.transitions'))
    end

    it 'should not include Product HIOS ID text' do
      expect(rendered).to_not have_content(l10n('product_hios_id'))
    end

    it 'should not include RatingArea text' do
      expect(rendered).to_not have_content(l10n('rating_area.exchange_provided_code'))
    end

    it 'should not include full name of person' do
      expect(rendered).to_not have_content(hbx_enrollment_member.person.full_name.titleize)
    end
  end

  context 'for display of enrollment additional summary with broker' do
    let(:broker_user) { FactoryBot.create(:user, person: broker_person) }
    let(:broker_person) {FactoryBot.create(:person, :with_broker_role)}
    before do
      allow(EnrollRegistry).to receive(:feature_enabled?).and_return(false)
      allow(EnrollRegistry).to receive(:feature_enabled?).with(:display_enr_summary).and_return(true)
      allow(EnrollRegistry).to receive(:feature_enabled?).with(:display_tax_household_summary).and_return(true)
      allow(EnrollRegistry).to receive(:feature_enabled?).with(:crm_publish_primary_subscriber).and_return(true)
      allow(EnrollRegistry).to receive(:feature_enabled?).with(:validate_quadrant).and_return(true)
      allow(EnrollRegistry).to receive(:feature_enabled?).with(:display_county).and_return(false)
      allow(EnrollRegistry).to receive(:feature_enabled?).with(:financial_assistance).and_return(true)
      allow(EnrollRegistry).to receive(:feature_enabled?).with(:allow_alphanumeric_npn).and_return(true)
      allow(view).to receive(:display_carrier_logo).and_return('logo/carrier/uhic.jpg')
      assign :bs4, true
      sign_in broker_user
      render 'ui-components/v1/cards/summary', :qhp => mock_qhp_cost_share_variance
    end

    it 'should include enrollment effective_on text' do
      expect(rendered).to have_content(l10n('enrollment.effective_on'))
    end

    it 'should include latest transition text' do
      expect(rendered).to have_content(l10n('enrollment.transitions'))
    end

    it 'should include Product HIOS ID text' do
      expect(rendered).to have_content(l10n('product_hios_id'))
    end

    it 'should include RatingArea text' do
      expect(rendered).to have_content(l10n('rating_area.exchange_provided_code'))
    end

    it 'should include full name of person' do
      expect(rendered).to have_content(hbx_enrollment_member.person.full_name.titleize)
    end

    it 'should include enrollment tax household details text' do
      expect(rendered).to have_content(l10n('enrollment.tax_household.details'))
    end

    it 'should include application details text' do
      expect(rendered).to have_content(l10n('application.details'))
    end

    it 'should include application ID text' do
      expect(rendered).to have_content(l10n('application_id'))
    end

    it 'should include application submitted_at text' do
      expect(rendered).to have_content(l10n('application.submitted_at'))
    end

    it 'should include enrollment ehb premium of all members' do
      expect(rendered).to have_content(number_to_currency(hbx_enrollment.total_ehb_premium_all_members))
    end

    it 'should include tax household members text' do
      expect(rendered).to have_content(l10n('tax_household_enrollment.members'))
    end

    it 'should include tax household members names' do
      expect(rendered).to have_content(thhe.tax_household_enrollment_member_names)
    end

    it 'should include tax household enrollment health benchmark text' do
      expect(rendered).to have_content(l10n('tax_household_enrollment.health_plan_benchmark_value'))
    end

    it 'should include tax household enrollment health benchmark value' do
      expect(rendered).to have_content(number_to_currency(thhe.household_health_benchmark_ehb_premium))
    end

    it 'should include tax household enrollment dental benchmark text' do
      expect(rendered).to have_content(l10n('tax_household_enrollment.dental_plan_benchmark_value'))
    end

    it 'should include tax household enrollment health benchmark value' do
      expect(rendered).to have_content(number_to_currency(thhe.household_dental_benchmark_ehb_premium))
    end

    it 'should include tax household enrollment aptc amount text' do
      expect(rendered).to have_content(l10n('tax_household_enrollment.aptc_amount'))
    end
  end

  context 'for display of enrollment additional summary with broker and feature flag is disabled' do
    let(:broker_user) { FactoryBot.create(:user, person: broker_person) }
    let(:broker_person) {FactoryBot.create(:person, :with_broker_role)}
    before do
      allow(EnrollRegistry).to receive(:feature_enabled?).and_return(false)
      allow(EnrollRegistry).to receive(:feature_enabled?).with(:display_enr_summary).and_return(false)
      allow(EnrollRegistry).to receive(:feature_enabled?).with(:display_tax_household_summary).and_return(false)
      allow(EnrollRegistry).to receive(:feature_enabled?).with(:crm_publish_primary_subscriber).and_return(true)
      allow(EnrollRegistry).to receive(:feature_enabled?).with(:validate_quadrant).and_return(true)
      allow(EnrollRegistry).to receive(:feature_enabled?).with(:display_county).and_return(false)
      allow(EnrollRegistry).to receive(:feature_enabled?).with(:financial_assistance).and_return(true)
      allow(EnrollRegistry).to receive(:feature_enabled?).with(:allow_alphanumeric_npn).and_return(true)
      allow(view).to receive(:display_carrier_logo).and_return('logo/carrier/uhic.jpg')
      sign_in broker_user
      render 'ui-components/v1/cards/summary', :qhp => mock_qhp_cost_share_variance
    end

    it 'should not include enrollment effective_on text' do
      expect(rendered).to_not have_content(l10n('enrollment.effective_on'))
    end

    it 'should not include latest transition text' do
      expect(rendered).to_not have_content(l10n('enrollment.transitions'))
    end

    it 'should not include Product HIOS ID text' do
      expect(rendered).to_not have_content(l10n('product_hios_id'))
    end

    it 'should not include RatingArea text' do
      expect(rendered).to_not have_content(l10n('rating_area.exchange_provided_code'))
    end

    it 'should not include full name of person' do
      expect(rendered).to_not have_content(hbx_enrollment_member.person.full_name.titleize)
    end

    it 'should not include full name of person' do
      expect(rendered).not_to have_content(hbx_enrollment_member.person.full_name.titleize)
    end

    it 'should not include enrollment tax household details text' do
      expect(rendered).not_to have_content(l10n('enrollment.tax_household.details'))
    end

    it 'should not include application details text' do
      expect(rendered).not_to have_content(l10n('application.details'))
    end

    it 'should not include application ID text' do
      expect(rendered).not_to have_content(l10n('application_id'))
    end

    it 'should not include application submitted_at text' do
      expect(rendered).not_to have_content(l10n('application.submitted_at'))
    end

    it 'should not include tax household members text' do
      expect(rendered).not_to have_content(l10n('tax_household_enrollment.members'))
    end
  end
end
