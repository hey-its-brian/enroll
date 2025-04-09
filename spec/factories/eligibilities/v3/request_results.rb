# frozen_string_literal: true

FactoryBot.define do
  factory :v3_request_result, class: 'Eligibilities::V3::RequestResult' do
    result { "success" }
    source { "FedHub" }
    source_transaction_id { "12345" }
    code { "200" }
    code_description { "Verified" }
    action { "Admin Hub Call" }
  end
end
