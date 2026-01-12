#frozen_string_literal: true

require "rails_helper"
require File.join(Rails.root, "app", "data_migrations", "update_missing_county")

describe UpdateMissingCounty do
  let(:given_task_name) { "update_missing_county" }
  subject { UpdateMissingCounty.new(given_task_name, double(:current_scope => nil)) }

  describe "given a task name" do
    it "has the given task name" do
      expect(subject.name).to eql given_task_name
    end
  end

  describe "migrate" do
    let!(:county_zip) { FactoryBot.create(:benefit_markets_locations_county_zip, zip: "12345", state: "ME", county_name: "Valid County") }

    before do
      # Mock CSV file creation to avoid actual file creation during tests
      allow(CSV).to receive(:open).and_yield(double('csv', :<< => nil))
    end

    context "when person has invalid county with valid zip" do
      let!(:person) do
        FactoryBot.create(:person).tap do |person|
          person.addresses.first.update!(
            county: "Please provide a zip code",
            zip: "12345",
            state: "ME"
          )
        end
      end

      it "updates the county to the correct county name" do
        expect { subject.migrate }.to output(/Person #{person.hbx_id} - Address updated with county: Valid County/).to_stdout

        person.reload
        expect(person.addresses.first.county).to eq "Valid County"
      end
    end

    context "when person has invalid county but no corresponding county zip record" do
      let!(:person) do
        FactoryBot.create(:person).tap do |person|
          person.addresses.first.update!(
            county: "Please provide a zip code",
            zip: "99999",
            state: "ME"
          )
        end
      end

      it "does not update the county and logs message" do
        subject.migrate
        person.reload
        expect(person.addresses.first.county).to eq "Please provide a zip code"
      end
    end

    context "when person has valid county already" do
      let!(:person) do
        FactoryBot.create(:person).tap do |person|
          person.addresses.first.update!(
            county: "Already Valid County",
            zip: "12345",
            state: "ME"
          )
        end
      end

      it "does not change the county" do
        expect { subject.migrate }.not_to output(/Person #{person.hbx_id}/).to_stdout

        person.reload
        expect(person.addresses.first.county).to eq "Already Valid County"
      end
    end

    context "when person has multiple addresses" do
      let!(:person) do
        FactoryBot.create(:person).tap do |person|
          person.addresses.clear

          # First address with invalid county and valid county zip
          first_address = Address.new(
            kind: 'home',
            address_1: '123 Valid Street',
            city: 'Valid City',
            county: "Please provide a zip code",
            zip: "12345",
            state: "ME"
          )

          # Second address with invalid county but no county zip record
          second_address = Address.new(
            kind: 'work',
            address_1: '456 Invalid Street',
            city: 'Invalid City',
            county: "Please provide a zip code",
            zip: "99999",
            state: "ME"
          )

          person.addresses = [first_address, second_address]
          person.save!
        end
      end

      it "updates only the address with valid county zip" do
        expect { subject.migrate }.to output(/Person #{person.hbx_id} - Address updated with county: Valid County/).to_stdout

        person.reload
        expect(person.addresses.first.county).to eq "Valid County"
        expect(person.addresses.second.county).to eq "Please provide a zip code"
      end
    end

    context "when county zip exists but has no county name" do
      let!(:invalid_county_zip) { FactoryBot.create(:benefit_markets_locations_county_zip, zip: "11111", state: "ME", county_name: nil) }
      let!(:person) do
        FactoryBot.create(:person).tap do |person|
          person.addresses.first.update!(
            county: "Please provide a zip code",
            zip: "11111",
            state: "ME"
          )
        end
      end

      it "does not update the county" do
        subject.migrate
        person.reload
        expect(person.addresses.first.county).to eq "Please provide a zip code"
      end
    end

    context "when financial assistance application has invalid county with valid zip" do
      let!(:fa_application) do
        FactoryBot.create(:financial_assistance_application, assistance_year: 2025, aasm_state: "draft").tap do |application|
          applicant = FactoryBot.build(:applicant, application: application, person_hbx_id: "test_hbx_id_fa")
          address = FactoryBot.build(:financial_assistance_address, county: "Please provide a zip code", zip: "12345", state: "ME")
          applicant.addresses = [address]
          application.applicants = [applicant]
          application.save!
        end
      end

      it "updates the financial assistance applicant address county" do
        expect { subject.migrate }.to output(/FA Application #{fa_application.hbx_id} - Applicant test_hbx_id_fa - Address updated with county: Valid County/).to_stdout

        fa_application.reload
        expect(fa_application.applicants.first.addresses.first.county).to eq "Valid County"
      end
    end

    context "when financial assistance application has invalid county but no corresponding county zip record" do
      let!(:fa_application) do
        FactoryBot.create(:financial_assistance_application, assistance_year: 2025, aasm_state: "draft").tap do |application|
          applicant = FactoryBot.build(:applicant, application: application, person_hbx_id: "test_hbx_id_fa_invalid")
          address = FactoryBot.build(:financial_assistance_address, county: "Please provide a zip code", zip: "99999", state: "ME")
          applicant.addresses = [address]
          application.applicants = [applicant]
          application.save!
        end
      end

      it "does not update the county and logs message" do
        subject.migrate
        fa_application.reload
        expect(fa_application.applicants.first.addresses.first.county).to eq "Please provide a zip code"
      end
    end

    context "when financial assistance application is from non-target year" do
      let!(:fa_application) do
        FactoryBot.create(:financial_assistance_application, assistance_year: 2024, aasm_state: "draft").tap do |application|
          applicant = FactoryBot.build(:applicant, application: application, person_hbx_id: "test_hbx_id_fa_2024")
          address = FactoryBot.build(:financial_assistance_address, county: "Please provide a zip code", zip: "12345", state: "ME")
          applicant.addresses = [address]
          application.applicants = [applicant]
          application.save!
        end
      end

      it "does not update the county" do
        subject.migrate
        fa_application.reload
        expect(fa_application.applicants.first.addresses.first.county).to eq "Please provide a zip code"
      end
    end

    context "when individual market application has invalid county with valid zip" do
      let!(:im_application) do
        FactoryBot.create(:individual_market_application, assistance_year: 2026, current_state: :initial).tap do |application|
          applicant = FactoryBot.build(:individual_market_applicant, :with_home_address, application: application, hbx_id: "test_hbx_id_im")
          applicant.addresses.first.county = "Please provide a zip code"
          applicant.addresses.first.zip = "12345"
          applicant.addresses.first.state = "ME"
          application.applicants = [applicant]
          application.save!
        end
      end

      it "updates the individual market applicant address county" do
        expect { subject.migrate }.to output(/IM Application #{im_application.hbx_id} - Applicant test_hbx_id_im - Address updated with county: Valid County/).to_stdout

        im_application.reload
        expect(im_application.applicants.first.addresses.first.county).to eq "Valid County"
      end
    end

    context "when individual market application has invalid county but no corresponding county zip record" do
      let!(:im_application) do
        FactoryBot.create(:individual_market_application, assistance_year: 2025, current_state: :initial).tap do |application|
          applicant = FactoryBot.build(:individual_market_applicant, :with_home_address, application: application, hbx_id: "test_hbx_id_im_invalid")
          applicant.addresses.first.county = "Please provide a zip code"
          applicant.addresses.first.zip = "99999"
          applicant.addresses.first.state = "ME"
          application.applicants = [applicant]
          application.save!
        end
      end

      it "does not update the county and logs message" do
        subject.migrate
        im_application.reload
        expect(im_application.applicants.first.addresses.first.county).to eq "Please provide a zip code"
      end
    end

    context "when individual market application is from non-target year" do
      let!(:im_application) do
        FactoryBot.create(:individual_market_application, assistance_year: 2024, current_state: :initial).tap do |application|
          applicant = FactoryBot.build(:individual_market_applicant, :with_home_address, application: application, hbx_id: "test_hbx_id_im_2024")
          applicant.addresses.first.county = "Please provide a zip code"
          applicant.addresses.first.zip = "12345"
          applicant.addresses.first.state = "ME"
          application.applicants = [applicant]
          application.save!
        end
      end

      it "does not update the county" do
        subject.migrate
        im_application.reload
        expect(im_application.applicants.first.addresses.first.county).to eq "Please provide a zip code"
      end
    end

    context "when multiple applications have mixed scenarios" do
      let!(:person) do
        FactoryBot.create(:person).tap do |person|
          person.addresses.first.update!(
            county: "Please provide a zip code",
            zip: "12345",
            state: "ME"
          )
        end
      end

      let!(:fa_application) do
        FactoryBot.create(:financial_assistance_application, assistance_year: 2025, aasm_state: "draft").tap do |application|
          applicant = FactoryBot.build(:applicant, application: application, person_hbx_id: "test_hbx_id_mixed_fa")
          address = FactoryBot.build(:financial_assistance_address, county: "Please provide a zip code", zip: "99999", state: "ME")
          applicant.addresses = [address]
          application.applicants = [applicant]
          application.save!
        end
      end

      let!(:im_application) do
        FactoryBot.create(:individual_market_application, assistance_year: 2025, current_state: :initial).tap do |application|
          applicant = FactoryBot.build(:individual_market_applicant, :with_home_address, application: application, hbx_id: "test_hbx_id_mixed_im")
          applicant.addresses.first.county = "Please provide a zip code"
          applicant.addresses.first.zip = "12345"
          applicant.addresses.first.state = "ME"
          application.applicants = [applicant]
          application.save!
        end
      end

      it "processes all applications and updates only valid ones" do
        expect { subject.migrate }.to output(/Person #{person.hbx_id} - Address updated with county: Valid County.*IM Application #{im_application.hbx_id} - Applicant test_hbx_id_mixed_im - Address updated with county: Valid County/m).to_stdout

        person.reload
        fa_application.reload
        im_application.reload

        expect(person.addresses.first.county).to eq "Valid County"
        expect(fa_application.applicants.first.addresses.first.county).to eq "Please provide a zip code"
        expect(im_application.applicants.first.addresses.first.county).to eq "Valid County"
      end
    end

    context "when applications have multiple applicants with different address scenarios" do
      let!(:fa_application) do
        FactoryBot.create(:financial_assistance_application, assistance_year: 2026, aasm_state: "draft").tap do |application|
          # Primary applicant with valid county zip
          primary_applicant = FactoryBot.build(:applicant, application: application, person_hbx_id: "primary_fa", is_primary_applicant: true)
          primary_address = FactoryBot.build(:financial_assistance_address, county: "Please provide a zip code", zip: "12345", state: "ME")
          primary_applicant.addresses = [primary_address]

          # Dependent applicant with invalid county zip
          dependent_applicant = FactoryBot.build(:applicant, application: application, person_hbx_id: "dependent_fa", is_primary_applicant: false)
          dependent_address = FactoryBot.build(:financial_assistance_address, county: "Please provide a zip code", zip: "99999", state: "ME")
          dependent_applicant.addresses = [dependent_address]

          application.applicants = [primary_applicant, dependent_applicant]
          application.save!
        end
      end

      it "updates only the applicant with valid county zip" do
        expect { subject.migrate }.to output(/FA Application #{fa_application.hbx_id} - Applicant primary_fa - Address updated with county: Valid County/).to_stdout

        fa_application.reload
        primary_applicant = fa_application.applicants.find { |a| a.person_hbx_id == "primary_fa" }
        dependent_applicant = fa_application.applicants.find { |a| a.person_hbx_id == "dependent_fa" }

        expect(primary_applicant.addresses.first.county).to eq "Valid County"
        expect(dependent_applicant.addresses.first.county).to eq "Please provide a zip code"
      end
    end

    context "when financial assistance application is in determined state" do
      let!(:fa_application_determined) do
        FactoryBot.create(:financial_assistance_application, assistance_year: 2025, aasm_state: "determined").tap do |application|
          applicant = FactoryBot.build(:applicant, application: application, person_hbx_id: "determined_fa")
          address = FactoryBot.build(:financial_assistance_address, county: "Please provide a zip code", zip: "12345", state: "ME")
          applicant.addresses = [address]
          application.applicants = [applicant]
          application.save!
        end
      end

      it "does not update the county for determined applications" do
        expect { subject.migrate }.not_to output(/FA Application #{fa_application_determined.hbx_id}/).to_stdout

        fa_application_determined.reload
        expect(fa_application_determined.applicants.first.addresses.first.county).to eq "Please provide a zip code"
      end
    end

    context "when individual market application is in determined state" do
      let!(:im_application_determined) do
        FactoryBot.create(:individual_market_application, assistance_year: 2025, current_state: :determined).tap do |application|
          applicant = FactoryBot.build(:individual_market_applicant, :with_home_address, application: application, hbx_id: "determined_im")
          applicant.addresses.first.county = "Please provide a zip code"
          applicant.addresses.first.zip = "12345"
          applicant.addresses.first.state = "ME"
          application.applicants = [applicant]
          application.save!
        end
      end

      it "does not update the county for determined applications" do
        expect { subject.migrate }.not_to output(/IM Application #{im_application_determined.hbx_id}/).to_stdout

        im_application_determined.reload
        expect(im_application_determined.applicants.first.addresses.first.county).to eq "Please provide a zip code"
      end
    end
  end
end