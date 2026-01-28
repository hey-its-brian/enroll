# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

module Operations
  module TaxForms
    # This class fetch tax form messages for a person
    class FetchTaxFormMessages
      include Dry::Monads[:do, :result]

      TAX_FORM_SUBJECTS = [
        'Corrected 1095-A Tax Form',
        'Void 1095-A Tax Form',
        'Your 1095-A Health Coverage Tax Form'
      ].freeze

      def call(params)
        validated_params = yield validate(params)
        person = yield fetch_person(validated_params[:person_id])
        family = yield fetch_family(validated_params[:family_id])
        messages = yield fetch_tax_form_messages(person)

        Success({messages: messages, person: person, family: family})
      end

      private

      def validate(params)
        return Failure("Missing person_id") if params[:person_id].blank?
        return Failure("Missing family_id") if params[:family_id].blank?

        Success(params)
      end

      def fetch_person(person_id)
        ::Operations::People::Find.new.call(person_id: person_id)
      end

      def fetch_family(family_id)
        family = Family.find(family_id)
        Success(family)
      rescue Mongoid::Errors::DocumentNotFound
        Failure("Family not found")
      end

      def fetch_tax_form_messages(person)
        Success(person.inbox.messages.where(:subject.in => TAX_FORM_SUBJECTS).order_by(:created_at => :desc))
      end
    end
  end
end
