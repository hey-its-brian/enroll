# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

module Operations
  module People
    # updates identity verification for users based on their identity response code.
    class ValidateIdentityVerification
      include Dry::Monads[:do, :result]

      VALID_TYPES = %w[report update_identity_verification].freeze

      REPORT_HEADERS = %w[
        user.identity_response_code
        user.created_at
        person_hbx_id
        consumer_created_at
        identity_validation
        identity_update_reason
        application_validation
        application_update_reason
      ].freeze

      def call(params)
        valid_params = yield validate(params)
        users = yield fetch_users(valid_params[:identity_response_code])
        yield create_report(users)
        yield update_identity_verification(users, valid_params[:type])

        Success('Report created successfully')
      end

      private

      def validate(params)
        return Failure('Missing report parameters') if params.blank?
        return Failure('Invalid type') unless VALID_TYPES.include?(params[:type])
        return Failure('Missing identity_response_code') if params[:identity_response_code].blank?
        return Failure('identity_response_code must be a string') unless params[:identity_response_code].is_a?(String)

        Success(params)
      end

      def fetch_users(code)
        users = User.collection.aggregate([
          { "$match" => { "identity_response_code" => code.to_s }},
          { "$lookup" => {
            from: "people",
            localField: "_id",
            foreignField: "user_id",
            as: "person_docs"
          }},
          { "$unwind" => "$person_docs" },
          { "$match" => {
            "$or": [
              { "person_docs.consumer_role.identity_validation": { "$in": ["pending", "rejected"] } },
              { "person_docs.consumer_role.application_validation": { "$in": ["pending", "rejected"] } }
            ]
          }},
          { "$project" => {
            _id: 1,
            identity_response_code: 1,
            created_at: 1,
            person_hbx_id: "$person_docs.hbx_id",
            consumer_created_at: "$person_docs.consumer_role.created_at",
            identity_validation: "$person_docs.consumer_role.identity_validation",
            identity_update_reason: "$person_docs.consumer_role.identity_update_reason",
            application_validation: "$person_docs.consumer_role.application_validation",
            application_update_reason: "$person_docs.consumer_role.application_update_reason"

          }}
        ], { allowDiskUse: true })

        if users.any?
          Success(users)
        else
          Failure('No users found with identity response code "acc"')
        end
      end

      def create_report(users)
        CSV.open("user_identity_validation_report.csv", "w") do |csv|
          csv << REPORT_HEADERS

          users.each do |user|
            csv << [
              user['_id'],
              user['identity_response_code'],
              user['created_at'],
              user['person_hbx_id'],
              user['consumer_created_at'],
              user['identity_validation'],
              user['identity_update_reason'],
              user['application_validation'],
              user['application_update_reason']
            ]
          end
        end

        Success("Report created with #{users.size} records")
      end

      def update_identity_verification(persons, type)
        return Success("Report complete") if type == 'report'

        person_hbx_ids = persons.map { |person| person['person_hbx_id'] }

        Person.where(:hbx_id.in => person_hbx_ids).each do |person|
          puts "Updating identity verification for person: #{person.hbx_id}"
          person.consumer_role.update_attributes!(identity_validation: "valid")
        end

        Success("Identity verification updated for #{persons.size} persons")
      end
    end
  end
end