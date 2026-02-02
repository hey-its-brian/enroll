# frozen_string_literal: true

module Insured
  module IndividualMarket
    # Controller for managing applicants in the individual market
    # pundit policies use QhpApplicationPolicy for applications and ApplicantPolicy for applicants
    class ApplicantsController < ApplicationController
      before_action :verify_qhp_application_enabled
      before_action :set_current_person
      before_action :set_family
      before_action :find_application
      before_action :find_applicant, only: [:edit, :update, :destroy, :show]
      before_action :check_for_editable_application, only: [:index, :create, :update, :destroy, :new, :edit, :update_preferences]
      before_action :set_consumer_bookmark_url, except: [:new, :edit, :destroy, :create, :update, :show_ssn, :update_preferences]
      before_action :enable_bs4_layout

      layout "progress"

      include ::ResourceRegistryHelper
      include ::ApplicationHelper

      def index
        authorize @application, :applicants?

        if session[:applicant_form_errors].present? && session[:applicant_form_errors].any?
          @applicant_form = OpenStruct.new(errors: OpenStruct.new(full_messages: session[:applicant_form_errors], any?: true))
          session.delete(:applicant_form_errors)
        end

        respond_to :html
      end

      def show
        authorize @applicant, :show?

        respond_to :html
      end

      def new
        authorize @application, :new_applicant?
        @applicant = ::Forms::IndividualMarket::Applicant.new(
          application_id: @application.id,
          is_primary_applicant: @application.applicants.blank?
        )
        @person_name_form = ::Forms::IndividualMarket::PersonNameForm.new
        @demographics_form = ::Forms::IndividualMarket::DemographicsForm.new
        @immigration_information_form = ::Forms::IndividualMarket::ImmigrationInformationForm.new
        @address_forms = [::Forms::Locations::AddressForm.new]
        respond_to do |format|
          format.html { render 'new', layout: false}
        end
      end

      def create
        authorize @application, :new_applicant?
        @applicant = ::Forms::IndividualMarket::Applicant.new(applicant_params.merge(application_id: params[:application_id]))

        success, result = @applicant.save

        respond_to do |format|
          format.html do
            if success
              redirect_to insured_individual_market_application_applicants_path(@application)
            else
              flash.now[:error] = result
              redirect_to insured_individual_market_application_applicants_path(@application), :flash => { :error => "Failed to create applicant due to response: #{result}" }
            end
          end

          format.js
        end
      end

      def edit
        authorize @applicant, :edit?

        # Load existing eligibilities if present
        @applicant.eligibilities ||= @applicant.initialize_eligibilities

        respond_to do |format|
          format.html { render 'new', layout: false}
        end
      end

      def update
        authorize @applicant, :edit?
        existing_ssn = @applicant.demographics.ssn
        existing_no_ssn = @applicant.demographics.no_ssn unless applicant_params[:demographics_attributes].present? && applicant_params[:demographics_attributes][:no_ssn].present?

        @applicant = ::Forms::IndividualMarket::Applicant.new(applicant_params.merge(application_id: params[:application_id], id: params[:id], existing_ssn: existing_ssn, existing_no_ssn: existing_no_ssn))

        success, result = @applicant.save

        respond_to do |format|
          format.html do
            unless success
              session[:applicant_form_errors] = result.is_a?(Array) ? result : [result]
            end
            redirect_to insured_individual_market_application_applicants_path(@application)
          end
        end
      end

      def destroy
        authorize @applicant, :destroy?
        ::Operations::IndividualMarket::Applicant::Destroy.new.call(@applicant)

        redirect_to insured_individual_market_application_applicants_path(@application)
      end

      def update_preferences
        authorize @application, :edit?

        @applicant = @application.applicants.where(id: params[:applicant_id]).first

        contact_method = transform_contact_method

        @applicant.assign_attributes(preferences_params.except(:contact_method).merge(contact_method: contact_method))

        destroy_removed_contact_methods

        save_context = EnrollRegistry.feature_enabled?(:enroll_sms_notifications) ? :enhanced_contact_preferences : nil
        if @applicant.save(context: save_context)
          redirect_to review_insured_individual_market_application_path(@application)
        else
          flash[:error] = @applicant.errors.full_messages.join(", ")
          redirect_to preferences_insured_individual_market_application_path(@application)
        end
      end

      def show_ssn
        authorize @application, :can_show_ssn?
        @applicant = @application.applicants.find_by(id: params[:id])
        if @applicant
          payload = number_to_ssn(@applicant.demographics.ssn)
          render json: { payload: payload, status: 200 }
        else
          render json: { message: "Unauthorized" }, status: 401
        end
      rescue Pundit::NotAuthorizedError, Mongoid::Errors::DocumentNotFound
        render json: { message: "Unauthorized" }, status: 401
      end

      private

      def verify_qhp_application_enabled
        return render(file: 'public/404.html', status: 404) unless EnrollRegistry.feature_enabled?(:qhp_application)
        true
      end

      def find_application
        @application = if current_user.try(:person).try(:agent?)
                         ::IndividualMarket::Application.find(params[:application_id])
                       else
                         ::IndividualMarket::Application.find_by(
                           id: params[:application_id],
                           family_id: get_current_person&.primary_family&.id
                         )
                       end
      rescue Mongoid::Errors::DocumentNotFound
        authorize ::IndividualMarket::Application.new, :find_application?
      end

      def check_for_editable_application
        return if @application&.current_state == :initial
        redirect_to insured_individual_market_application_path(@application)
      end

      def find_applicant
        @applicant = @application.applicants.find(params[:id])
      end

      def set_family
        @family = @person.primary_family
      end

      def enable_bs4_layout
        @bs4 = true if EnrollRegistry.feature_enabled?(:bs4_consumer_flow)
      end

      def transform_contact_method
        contact_method = params.dig("individual_market_applicant", "contact_method")
        return unless contact_method.is_a?(Array)
        return if contact_method.empty?
        ::IndividualMarket::Applicant::CONTACT_METHOD_MAPPING[contact_method]
      end

      def destroy_removed_contact_methods
        destroy_phones
        destroy_emails
      end

      def destroy_phones
        phones_params = params.dig("individual_market_applicant", "phones_attributes")
        phones_to_destroy = phones_params&.select { |_key, phone| phone[:_destroy] == "true" && phone[:id].present? }
        phones_to_destroy&.each do |phone|
          @applicant.phones.where(id: phone.last[:id]).destroy_all
        end
      end

      def destroy_emails
        emails_params = params.dig("individual_market_applicant", "emails_attributes")
        emails_to_destroy = emails_params&.select { |_key, email| email[:_destroy] == "true" && email[:id].present? }
        emails_to_destroy&.each do |email|
          @applicant.emails.where(id: email.last[:id]).destroy_all
        end
      end

      def base_attributes
        {
          id: params[:id],
          application_id: params[:application_id],
          family_member_id: applicant_params[:family_member_id],
          is_primary_applicant: applicant_params[:is_primary_applicant],
          is_dependent: applicant_params[:is_dependent],
          is_applying_coverage: applicant_params[:is_applying_coverage],
          is_homeless: applicant_params[:is_homeless],
          age_off_excluded: applicant_params[:age_off_excluded],
          address_same_as_primary: applicant_params[:address_same_as_primary],
          relationship: applicant_params[:relationship],
          eligibilities: applicant_params[:eligibilities]
        }
      end

      def preferences_params
        params.require(:individual_market_applicant).permit(
          :language_preference,
          { contact_method: [] },
          phones_attributes: [:id, :kind, :number, :country_code, :area_code, :extension, :full_phone_number, :_destroy],
          emails_attributes: [:id, :kind, :address, :_destroy]
        )
      end

      def existing_no_ssn
        @applicant.demographics.no_ssn
      end

      def applicant_params
        params.require(:applicant).permit(
          :id,
          :family_member_id,
          :is_primary_applicant,
          :is_dependent,
          :is_applying_coverage,
          :is_homeless,
          :is_temporarily_out_of_state,
          :age_off_excluded,
          :address_same_as_primary,
          :relationship,
          eligibilities: [:key, :title],
          person_name_attributes: [
            :id,
            :given_name,
            :middle_name,
            :family_name,
            :name_pfx,
            :name_sfx,
            :alternate_name
          ],
          demographics_attributes: [
            :id,
            :encrypted_ssn,
            :ssn,
            :no_ssn,
            :dob,
            :gender,
            :us_citizen,
            :naturalized_citizen,
            :eligible_immigration_status,
            :indian_tribe_member,
            :tribal_id,
            :tribal_name,
            :tribal_state,
            :language_code,
            :citizen_status,
            :is_incarcerated,
            :is_applying_coverage,
            { ethnicity: [] },
            { race: [] },
            { tribe_codes: [] }
          ],
          immigration_information_attributes: [
            :id,
            :subject,
            :alien_number,
            :i94_number,
            :visa_number,
            :passport_number,
            :sevis_id,
            :naturalization_number,
            :receipt_number,
            :citizenship_number,
            :card_number,
            :country_of_citizenship,
            :expiration_date,
            :issuing_country,
            :description,
            { immigration_doc_statuses: [] }
          ],
          addresses_attributes: [
            :id,
            :kind,
            :address_1,
            :address_2,
            :address_3,
            :city,
            :county,
            :state,
            :zip,
            :country_name,
            :quadrant,
            :_destroy
          ]
        )
      end
    end
  end
end
