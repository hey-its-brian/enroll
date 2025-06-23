# frozen_string_literal: true

FactoryBot.define do
  factory :individual_market_immigration_information, class: 'IndividualMarket::ImmigrationInformation' do
    association :applicant, factory: :individual_market_applicant

    subject                 { 'I-94 (Arrival/Departure Record) in Unexpired Foreign Passport' }
    alien_number            { 'A12345678' }
    i94_number              { '98765432112' }
    visa_number             { 'V123456789' }
    passport_number         { 'X123456789' }
    sevis_id                { 'N123456789' }
    naturalization_number   { 'N123456789' }
    receipt_number          { 'R123457891234' }
    citizenship_number      { 'C123456789' }
    card_number             { '1234567890123' }
    country_of_citizenship  { 'United States' }
    expiration_date         { Date.current + 1.year }
    issuing_country         { 'United States' }
    description             { 'This is type of immigration document information to prove the lawful presence in the US.' }
  end
end
