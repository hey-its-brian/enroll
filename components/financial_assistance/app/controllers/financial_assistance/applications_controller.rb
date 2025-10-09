# frozen_string_literal: true

module FinancialAssistance
  # IAP application controller
  class ApplicationsController < FinancialAssistance::ApplicationController
    include ::ResourceRegistryHelper

    before_action :set_current_person
    before_action :set_family
    before_action :find_application, :except => [:index, :index_with_filter, :new]
    before_action :enable_bs4_layout, only: [:application_year_selection, :application_checklist, :edit, :eligibility_results, :review_and_submit,
                                             :review, :submit_your_application, :wait_for_eligibility_response, :preferences,
                                             :application_publish_error, :eligibility_response_error, :index, :index_with_filter]
    before_action :enable_admin_bs4_layout, only: [:transfer_history, :raw_application, :show]

    around_action :cache_current_hbx, :only => [:index_with_filter]

    include ActionView::Helpers::SanitizeHelper
    include Acapi::Notifiers
    include ::FileUploadHelper
    include ::ResourceRegistryHelper
    include FinancialAssistance::NavigationHelper
    require 'securerandom'

    before_action :check_eligibility, only: [:copy]
    before_action :set_summary_helpers, only: [:review_and_submit, :review, :raw_application, :show]
    before_action :set_cache_headers, only: [:index, :relationships, :review_and_submit, :index_with_filter]
    before_action :endpoint_access_control, only: [:index, :index_with_filter]

    # This is a before_action that checks if the application is a renewal draft and if it is, it sets a flash message and redirects to the applications_path
    # This before_action needs to be called after finding the application
    #
    # @before_action
    # @private
    before_action :check_for_uneditable_application, only: [
      :edit,
      :step,
      :copy,
      :application_year_selection,
      :application_checklist,
      :review_and_submit,
      :review,
      :raw_application,
      :show,
      :wait_for_eligibility_response,
      :eligibility_results,
      :application_publish_error,
      :eligibility_response_error,
      :check_eligibility_results_received,
      :checklist_pdf,
      :update_transfer_requested,
      :update_application_year
    ]

    layout :resolve_layout

    # We should ONLY be getting applications that are associated with PrimaryFamily of Current Person.
    # DO NOT include applications from other families.
    def index
      authorize @family, :index?

      @copyable_application_ids = @family.fetch_copyable_faa_application_ids
      @applications = FinancialAssistance::Application.where("family_id" => @family.id)

      respond_to :html
    end

    def index_with_filter
      authorize @family, :index?

      @copyable_application_ids = @family.fetch_copyable_faa_application_ids

      result = FinancialAssistance::Operations::Applications::QueryFilteredApplications.new.call(
        {
          family_id: @family.id,
          filter_year: params.dig(:filter, :year)
        }
      )
      if result.success?
        value = result.value!
        @applications = value[:applications]

        @filtered_applications = value[:filtered_applications]
        @recent_determined_hbx_id = value[:recent_determined_hbx_id]

        respond_to do |format|
          format.html
        end
      else
        respond_to do |format|
          format.json { render json: result.failure.to_h, status: 422 }
        end
      end
    end

    def edit
      authorize @application, :edit?
      save_faa_bookmark(request.original_url)
      set_admin_bookmark_url
      load_support_texts

      respond_to :html
    end

    def preferences
      authorize @application, :preferences?

      # Triggers the creation of IVL eligibility, related 3.0 evidences, and triggers events to call respective hubs when qhp_application feature is enabled.
      ::Operations::Eligibilities::V3::IndividualMarket::CreateAndCallHubs.new.call(application: @application) if qhp_application_feature_enabled?

      save_faa_bookmark(request.original_url)
      respond_to :html
    end

    def save_preferences
      raise ActionController::UnknownFormat unless request.format.html?

      authorize @application, :save_preferences?
      if params[:application].present?
        @application.clean_conditional_params(params[:application])
        attrs = application_params.to_h
        transform_contact_methods!(attrs[:applicants_attributes])
        # Mark empty phones for destruction
        mark_empty_phones_for_destruction(attrs[:applicants_attributes]) if attrs[:applicants_attributes].present?
        mark_empty_emails_for_destruction(attrs[:applicants_attributes]) if attrs[:applicants_attributes].present?

        @application.assign_attributes(attrs)
        applicant_errors = save_preferences_applicant_errors

        if applicant_errors.empty? && @application.save
          redirect_to save_preferences_redirection_link
        else
          @application.save!(validate: false)
          # Add validation errors from applicants to the application's errors
          applicant_errors.each { |error| @application.errors.add(:base, error) }
          flash[:error] = build_error_messages(@application).join(", ")
          render 'preferences'
        end
      else
        render 'preferences'
      end
    end

    def submit_your_application
      authorize @application, :submit_your_application?
      save_faa_bookmark(request.original_url)
      set_admin_bookmark_url
      respond_to :html
    end

    def submit_your_application_save
      raise ActionController::UnknownFormat unless request.format.html?

      authorize @application, :submit?
      if params[:application].present?
        @application.clean_conditional_params(params[:application])
        @application.assign_attributes(permit_params(params[:application]))

        if @application.save
          submit_location = submit_and_publish_application_redirect_path
          submit_location[:flash].present? ? redirect_to(submit_location[:path], flash: submit_location[:flash]) : redirect_to(submit_location[:path])
        else
          @application.save!(validate: false)
          flash[:error] = build_error_messages(@application).join(", ")
          render 'submit_your_application'
        end
      else
        render 'submit_your_application'
      end
    end

    def step
      raise ActionController::UnknownFormat unless request.format.html?

      authorize @application, :step?

      if params[:step] == "1"
        redirect_to preferences_application_path(@application)
      else
        redirect_to submit_your_application_application_path(@application)
      end
    end

    def copy
      authorize @application, :copy?
      begin
        copy_result = ::FinancialAssistance::Operations::Applications::Copy.new.call(
          copy_params(params[:id], @person, current_user, params[:assistance_year])
        )
        if copy_result.success?
          @application = copy_result.success
          @application.configure_assistance_year
          assistance_year_show = EnrollRegistry.feature_enabled?(:iap_year_selection) && (HbxProfile.current_hbx.under_open_enrollment? || EnrollRegistry.feature_enabled?(:iap_year_selection_form))
          assistance_year_set = params[:assistance_year].present? && params[:assistance_year].to_s.match?(/\A\d+\z/)
          assistance_year_page = assistance_year_show && !assistance_year_set
          redirect_path = get_redirect_path(@application, assistance_year_page)

          redirect_to redirect_path
        else
          flash[:error] = copy_result.failure[:simple_error_message]
          redirect_to applications_path
        end
      rescue StandardError => e
        flash[:error] = "#{l10n('exchange.error')} - #{e}"
        redirect_to applications_path(tab: 'cost_savings')
      end
    end

    def application_year_selection
      authorize @application, :application_year_selection?
      save_faa_bookmark(request.original_url)
      set_admin_bookmark_url

      respond_to :html
    end

    def application_checklist
      authorize @application, :application_checklist?
      save_faa_bookmark(request.original_url)
      set_admin_bookmark_url
      respond_to :html
    end

    def review_and_submit
      authorize @application, :review_and_submit?
      save_faa_bookmark(request.original_url)
      set_admin_bookmark_url
      @all_relationships = @application.relationships
      @application.calculate_total_net_income_for_applicants
      build_applicants_name_by_hbx_id_hash
      error_message = FinancialAssistanceRegistry.feature_enabled?(:spousal_tax_info_validation) ? 'Application has incomplete or invalid information' : 'Applicant has incomplete information'
      flash[:error] = error_message unless @application.valid_applicants?
      @has_outstanding_local_mec_evidence = has_outstanding_local_mec_evidence?(@application) if EnrollRegistry.feature_enabled?(:mec_check)
      @shop_coverage = shop_enrollments_exist?(@application) if EnrollRegistry.feature_enabled?(:shop_coverage_check)

      unless @application.valid_relations?
        redirect_to application_relationships_path(@application)
        flash[:error] = l10n("faa.errors.inconsistent_relationships_error")
      end
      redirect_to applications_path if @application.blank?

      respond_to :html
    end

    def review
      return redirect_to application_path(@application) if qhp_application_feature_enabled?
      authorize @application, :review?

      save_faa_bookmark(request.original_url)
      return redirect_to applications_path if @application.blank?

      build_applicants_name_by_hbx_id_hash

      respond_to :html
    end

    # This action is used to show the application details in a read-only format.
    # It is authorized by the application policy's show? method.
    # It should not be used unless the qhp_application feature is enabled.
    # @return [void]
    def show
      return redirect_to review_application_path(@application) unless qhp_application_feature_enabled?
      authorize @application, :show?
      respond_to :html
    end

    def raw_application
      authorize @application, :raw_application?
      return redirect_to application_path(@application) if qhp_application_feature_enabled?

      if @application.nil? || (@application.is_draft? && !qhp_application_feature_enabled?)
        redirect_to applications_path
      else
        @all_relationships = @application.relationships
        @demographic_hash = {}
        @income_coverage_hash = {}
        build_applicants_name_by_hbx_id_hash

        unless @bs4
          @applicants.each do |applicant|
            file = if FinancialAssistanceRegistry[:has_enrolled_health_coverage].setting(:currently_enrolled).item
                     File.read("./components/financial_assistance/app/views/financial_assistance/applications/raw_application.yml.erb")
                   else
                     File.read("./components/financial_assistance/app/views/financial_assistance/applications/raw_application_hra.yml.erb")
                   end
            application_hash = YAML.safe_load(ERB.new(file).result(binding))
            @demographic_hash[applicant.id] = application_hash[0]["demographics"]
            application_hash[0]["demographics"]["ADDRESSES"] = generate_address_hash(applicant)
            application_hash[1]["financial_assistance_info"]["INCOME"] = generate_income_hash(applicant)
            @income_coverage_hash[applicant.id] = application_hash[1]["financial_assistance_info"]
          end
        end
      end

      respond_to :html
    end

    def transfer_history
      authorize @application, :transfer_history?

      @transfers = []
      if @application.account_transferred || !@application.transfer_id.nil?
        @transfers << {
          transfer_id: @application.transfer_id || 'n/a',
          direction: transfer_direction(@application),
          timestamp: @application.transferred_at,
          reason: transfer_reason(@application),
          source: transfer_source(@application)
        }
      end

      redirect_to applications_path if @application.nil?

      respond_to :html
    end

    def wait_for_eligibility_response
      authorize @application, :wait_for_eligibility_response?
      save_faa_bookmark(applications_path)
      set_admin_bookmark_url

      respond_to :html
    end

    def eligibility_results
      authorize @application, :eligibility_results?
      save_faa_bookmark(request.original_url)
      set_admin_bookmark_url
      @in_application_flow = true if params.keys.include?('cur')
      respond_to :html
    end

    def application_publish_error
      authorize @application, :application_publish_error?
      save_faa_bookmark(request.original_url)
      set_admin_bookmark_url
      @override_flash = true if EnrollRegistry.feature_enabled?(:bs4_consumer_flow)
      respond_to :html
    end

    def eligibility_response_error
      authorize @application, :eligibility_response_error?
      save_faa_bookmark(request.original_url)
      set_admin_bookmark_url
      redirect_to eligibility_results_application_path(@application.id, cur: 1) if eligibility_results_received?(@application)
      @application.update_attributes(determination_http_status_code: 999) if @application.determination_http_status_code.nil?
      @application.send_failed_response

      respond_to :html
    end

    def check_eligibility_results_received
      authorize @application, :check_eligibility_results_received?

      respond_to do |format|
        format.html { render plain: determination_token_present?(@application), content_type: 'text/plain' }
      end
    end

    def checklist_pdf
      raise ActionController::UnknownFormat unless request.format.html?

      authorize @application, :checklist_pdf?
      send_file(
        FinancialAssistance::Engine.root.join(
          FinancialAssistanceRegistry[:ivl_application_checklist].setting(:file_location).item.to_s
        ), :disposition => "inline", :type => "application/pdf"
      )
    end

    def update_transfer_requested
      authorize @application, :update_transfer_requested?
      @button_sent_text = l10n("faa.sent_to_external_verification")

      respond_to do |format|
        if @application.update_attributes(transfer_requested: true)
          format.js
        else
          # TODO: respond with HTML on failure???
          format.html
        end
      end
    end

    def update_application_year
      authorize @application, :update_application_year?
      new_year = params[:application][:assistance_year]

      @application.update_attributes(assistance_year: new_year) if new_year && new_year != @application.assistance_year

      redirect_to application_checklist_application_path(@application)
    end

    private

    # This is a before_action that redirects to the main_app's insured_sbm_applications_path if the qhp_application feature is enabled
    def endpoint_access_control
      return unless qhp_application_feature_enabled?

      redirect_to main_app.insured_sbm_applications_path
    end

    # Returns the redirect path based on the application and assistance year page
    # @param application [FinancialAssistance::Application] The financial assistance application
    # @param assistance_year_page [Boolean] Indicates if the assistance year page is being displayed
    # @return [String] The redirect path based on the application state and parameters
    def get_redirect_path(application, assistance_year_page)
      if qhp_application_feature_enabled? && params[:applicant_hbx_id].present?
        applicant = application.applicants.detect { |app| app.person_hbx_id == params[:applicant_hbx_id] }

        if applicant.present?
          path_mapping = {
            personal_info: -> { application_applicants_path(application, applicant: applicant.id) },
            preferences: -> { preferences_application_path(application) },
            tax_info: -> { go_to_step_application_applicant_path(application, applicant, 1) },
            income: -> { application_applicant_incomes_path(application, applicant) },
            income_adjustments: -> { application_applicant_deductions_path(application, applicant) },
            other_incomes: -> { other_application_applicant_incomes_path(application, applicant) },
            health_coverage: -> { application_applicant_benefits_path(application, applicant) },
            other_questions: -> { other_questions_application_applicant_path(application, applicant) },
            relationships: -> { application_relationships_path(application) }
          }

          path_key = path_mapping.keys.find { |key| params[key].present? }
          return path_mapping[path_key].call if path_key
        end
      end
      if assistance_year_page
        application_year_selection_application_path(application)
      elsif qhp_application_feature_enabled?
        application_applicants_path(application_id: application.id)
      else
        edit_application_path(application)
      end
    end

    # Prepares parameters for copying an existing financial assistance application
    #
    # @param application_id [String] The ID of the application to copy
    # @param person [Person] The person applying for financial assistance
    # @param current_user [User] The current user making the request
    # @param assistance_year [String] The year for the new application
    # @return [Hash] Parameters to pass to the financial assistance application creation
    def copy_params(application_id, person, logged_in_user, assistance_year = nil)
      if qhp_application_feature_enabled?
        params = {
          application_id: application_id,
          origin: fetch_origin(person, logged_in_user),
          generation_reason: :manual
        }
        params[:assistance_year] = assistance_year if assistance_year.present?
        params
      else
        { application_id: application_id }
      end
    end

    def transfer_direction(application)
      return 'In' unless application.transfer_id.nil?
      return 'Out' if application.account_transferred
    end

    def transfer_reason(application)
      case transfer_direction(application)
      when "Out"
        application.transfer_requested ? "User request" : "Medicaid/CHIP Assessment"
      when "In"
        "Medicaid/CHIP Assessment"
      end
    end

    def transfer_source(application)
      if application.transfer_id.nil? || application.transfer_id&.include?('SBM')
        'SBM'
      elsif application.transfer_id&.include? 'MEA'
        'SMA'
      elsif application.transfer_id&.include? 'FFM'
        'FFM'
      end
    end

    # rubocop:disable Style/ExplicitBlockArgument
    def cache_current_hbx
      ::Caches::CurrentHbx.with_cache do
        yield
      end
    end
    # rubocop:enable Style/ExplicitBlockArgument

    def set_family
      @family = @person.primary_family
    end

    def enable_bs4_layout
      @bs4 = true if EnrollRegistry.feature_enabled?(:bs4_consumer_flow)
    end

    def enable_admin_bs4_layout
      @bs4 = true if EnrollRegistry.feature_enabled?(:bs4_admin_flow)
    end

    def resolve_layout
      case action_name
      when "edit", "submit_your_application", "preferences", "review_and_submit", "review", "step", "eligibility_response_error", "application_publish_error"
        EnrollRegistry.feature_enabled?(:bs4_consumer_flow) ? "financial_assistance_progress" : "financial_assistance_nav"
      when "application_year_selection", "application_checklist", "index", "index_with_filter"
        EnrollRegistry.feature_enabled?(:bs4_consumer_flow) ? "financial_assistance_progress" : "financial_assistance"
      when "eligibility_results"
        return "financial_assistance_progress" if EnrollRegistry.feature_enabled?(:bs4_consumer_flow)
        params.keys.include?('cur') ? "financial_assistance_nav" : "financial_assistance"
      when "wait_for_eligibility_response"
        EnrollRegistry.feature_enabled?(:bs4_consumer_flow) ? "bs4_financial_assistance" : "financial_assistance"
      when "transfer_history", "raw_application", "show"
        EnrollRegistry.feature_enabled?(:bs4_admin_flow) ? "financial_assistance_progress" : "financial_assistance"
      else
        "financial_assistance"
      end
    end

    def determination_token_present?(application)
      Rails.cache.read("application_#{application.hbx_id}_determined").present?.to_s
    end

    def has_outstanding_local_mec_evidence?(application)
      # when qhp is enabled, we don't copy evidences and their states instead we build new evidences with default states
      # so the aptc csr evidences are not expected to be in any outstanding states in this case
      return false if qhp_application_feature_enabled?
      application.applicants.any? {|applicant| Eligibilities::Evidence::OUTSTANDING_STATES.include?(applicant&.local_mec_evidence&.aasm_state)}
    end

    def shop_enrollments_exist?(application)
      applicant_enrollments = []
      application.applicants.each do |applicant|
        applicant_coverage = ::Operations::Households::CheckExistingCoverageByPerson.new.call(person_hbx_id: applicant.person_hbx_id, market_kind: "employer_sponsored")
        applicant_enrollments << (applicant_coverage.success? && applicant_coverage.success.present?)
      end
      applicant_enrollments.include?(true)
    end

    def eligibility_results_received?(application)
      application.success_status_codes?(application.determination_http_status_code) && application.determined?
    end

    def validation_errors_parser(result)
      result.errors.each_with_object([]) do |error, collect|
        collect << if error.is_a?(Dry::Schema::Message)
                     message = error.path.reduce("The ") do |attribute_message, path|
                       next_element = error.path[(error.path.index(path) + 1)]
                       attribute_message + if next_element.is_a?(Integer)
                                             "#{(next_element + 1).ordinalize} #{path.to_s.humanize.downcase}'s "
                                           elsif path.is_a? Integer
                                             ""
                                           else
                                             "#{path.to_s.humanize.downcase}:"
                                           end
                     end
                     message + " #{error.text}."
                   else
                     error.flatten.flatten.join(',').gsub(",", " ").titleize
                   end
      end
    end

    def build_error_messages(model)
      model.errors.full_messages
    end

    def haven_determination_is_enabled?
      FinancialAssistanceRegistry.feature_enabled?(:haven_determination)
    end

    def medicaid_gateway_determination_is_enabled?
      FinancialAssistanceRegistry.feature_enabled?(:medicaid_gateway_determination)
    end

    def determination_request_class
      return FinancialAssistance::Operations::Application::RequestDetermination if haven_determination_is_enabled?
      # TODO: This beelow line will cause failures
      return FinancialAssistance::Operations::Applications::MedicaidGateway::RequestEligibilityDetermination if medicaid_gateway_determination_is_enabled?
    end

    def set_summary_helpers
      @cfl_service = ::FinancialAssistance::Services::ConditionalFieldsLookupService.new
      @applicants = @application&.active_applicants
      return unless @bs4

      @summary_helper = ::FinancialAssistance::Services::SummaryService.instance_for_action(action_name, @cfl_service, @application, @applicants)
    end

    def check_eligibility
      call_service
      [(flash[:error] = helpers.l10n(helpers.decode_msg(@message))), (redirect_to applications_path)] unless @assistance_status
    end

    def call_service
      if FinancialAssistanceRegistry.feature_enabled?(:aceds_curam)
        person = FinancialAssistance::Factories::AssistanceFactory.new(@person)
        @assistance_status, @message = person.search_existing_assistance
      else
        @assistance_status = true
        @message = nil
      end
    end

    def hash_to_param(param_hash)
      ActionController::Parameters.new(param_hash)
    end

    def permit_params(attributes)
      attributes.permit!
    end

    def find
      find_application
    end

    def save_faa_bookmark(url)
      current_person = get_current_person
      return if current_person.consumer_role.blank?
      current_person.consumer_role.update_attribute(:bookmark_url, url) if current_person.consumer_role.identity_verified?
    end

    def check_citizen_immigration_status?(applicant)
      applicant.naturalized_citizen.present? || applicant.eligible_immigration_status.present?
    end

    def generate_income_hash(applicant)
      assistance_year = FinancialAssistance::Operations::EnrollmentDates::ApplicationYear.new.call.value!.to_s
      income_hash = {
        "#{l10n('faa.incomes.from_employer', assistance_year: assistance_year)}*" => human_boolean(applicant.has_job_income),
        "jobs" => generate_employment_hash(applicant.incomes.jobs),
        l10n('faa.incomes.from_self_employment',
             assistance_year: assistance_year) => human_boolean(applicant.has_self_employment_income),
        l10n('faa.other_incomes.other_sources', assistance_year: assistance_year) => human_boolean(applicant.has_other_income)
      }
      income_hash.merge!(l10n('faa.other_incomes.unemployment', assistance_year: assistance_year) => human_boolean(applicant.has_unemployment_income)) if FinancialAssistanceRegistry.feature_enabled?(:unemployment_income)
      income_hash
    end

    def generate_employment_hash(jobs)
      job_hash = {}
      jobs.each do |job|
        job_hash[job.id] = {
          "Employer Name" => job.employer_name,
          "EMPLOYER ADDRESSS LINE 1" => job&.employer_address&.address_1,
          "EMPLOYER ADDRESSS LINE 2" => job&.employer_address&.address_2,
          "CITY" => job&.employer_address&.city,
          "STATE" => job&.employer_address&.state,
          "ZIP" => job&.employer_address&.zip,
          "EMPLOYER PHONE " => job.employer_phone&.full_phone_number
        }
      end
      job_hash
    end

    def generate_address_hash(applicant)
      addresses_hash = {}
      applicant.addresses.each do |address|
        addresses_hash["#{address.kind}_address"] = {
          "ADDRESS LINE 1" => address&.address_1,
          "ADDRESS LINE 2" => address&.address_2,
          "CITY" => address&.city,
          "ZIP" => address&.zip,
          "STATE" => address&.state,
          "COUNTY" => address&.county
        }
      end
      addresses_hash
    end

    def human_boolean(value)
      if value == true
        'Yes'
      elsif value == false
        'No'
      elsif value.nil?
        'N/A'
      else
        value
      end
    end

    def build_applicants_name_by_hbx_id_hash
      return {} if @applicants.blank?

      @applicants_name_by_hbx_id_hash = @applicants.each_with_object({}) do |applicant, hash|
        hash[applicant.person_hbx_id] = applicant.full_name
      end
    end

    def submit_and_publish_application_redirect_path
      return { path: application_publish_error_application_path(@application), flash: { error: "Submission Error: Imported Application can't be submitted for Eligibity" } } if @application.imported?
      return { path: application_publish_error_application_path(@application), flash: { error: build_error_messages(@application) } } unless @application.complete?

      publish_result = determination_request_class.new.call(application_id: @application.id)
      return { path: wait_for_eligibility_response_application_path(@application) } if publish_result.success?

      @application.unsubmit! if @application.may_unsubmit?

      flash_message = case publish_result.failure
                      when Dry::Validation::Result
                        { error: validation_errors_parser(publish_result.failure) }
                      when Exception
                        { error: publish_result.failure.message }
                      else
                        { error: "Submission Error: #{publish_result.failure}" }
                      end
      { path: application_publish_error_application_path(@application), flash: flash_message }
    end

    # Strong parameters: permit any nested attributes you need
    def application_params
      params.require(:application).permit(
        :is_renewal_authorized,
        :years_to_renew,
        applicants_attributes: [
          :id,
          :language_preference,
          # contact_method comes in as an Array; we'll map it below
          { contact_method: [] },
          { phones_attributes:   {} },
          { emails_attributes:   {} }
        ]
      )
    end

    # Walks applicants_attributes
    # and replaces each contact_method Array with the mapped value.
    def transform_contact_methods!(applicants_attrs)
      return unless applicants_attrs.is_a?(Hash)

      applicants_attrs.each_value do |applicant_h|
        cm = applicant_h["contact_method"] || applicant_h[:contact_method]
        next unless cm.is_a?(Array) && cm.any?

        # lookup in your mapping constant
        mapped = IndividualMarket::Applicant::CONTACT_METHOD_MAPPING[cm]
        # overwrite the array
        applicant_h["contact_method"] = mapped
      end
    end

    # This method marks empty phone numbers for destruction in the applicants_attributes hash.
    # It iterates through each applicant's phones_attributes and sets the _destroy flag to true if the full_phone_number is blank.
    # @param applicants_attributes [Hash] The hash containing applicants and their phone attributes.
    # # @return [void] The method modifies the applicants_attributes in place.
    def mark_empty_phones_for_destruction(applicants_attributes)
      applicants_attributes.each do |_, applicant_attrs|
        next unless applicant_attrs[:phones_attributes].present?

        applicant_attrs[:phones_attributes].each do |_, phone_attrs|
          phone_attrs[:_destroy] = "1" if phone_attrs[:full_phone_number].blank? && phone_attrs[:id].present?
        end
      end
    end

    def mark_empty_emails_for_destruction(applicants_attributes)
      applicants_attributes.each do |_, applicant_attrs|
        next unless applicant_attrs[:emails_attributes].present?

        applicant_attrs[:emails_attributes].each do |_, email_attrs|
          email_attrs[:_destroy] = "1" if email_attrs[:address].blank? && email_attrs[:id].present?
        end
      end
    end

    def save_preferences_redirection_link
      if qhp_application_feature_enabled?
        review_and_submit_application_path(@application)
      else
        submit_your_application_application_path(@application)
      end
    end

    def save_preferences_applicant_errors
      return [] unless EnrollRegistry.feature_enabled?(:enroll_sms_notifications)

      @application.applicants.map { |applicant| applicant.errors unless applicant.valid?(:enhanced_contact_preferences) }.compact
    end
  end
end
