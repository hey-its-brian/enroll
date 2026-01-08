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
        expect { subject.migrate }.to output(/Person #{person.hbx_id} - No county found for zip: 99999, state: ME/).to_stdout

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
        expect { subject.migrate }.to output(
          /Person #{person.hbx_id} - Address updated with county: Valid County.*Person #{person.hbx_id} - No county found for zip: 99999, state: ME/m
        ).to_stdout

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
        expect { subject.migrate }.to output(/Person #{person.hbx_id} - No county found for zip: 11111, state: ME/).to_stdout

        person.reload
        expect(person.addresses.first.county).to eq "Please provide a zip code"
      end
    end
  end
end