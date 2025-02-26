# frozen_string_literal: true

require_dependency "benefit_sponsors/application_controller"

module BenefitSponsors
  module Profiles
    module AssisterAgencies
      # controller for assister agency profiles, frequently utilized in but not limited to the assister portal
      class AssisterAgencyProfilesController < ::BenefitSponsors::ApplicationController
        # include Acapi::Notifiers
        include DataTablesAdapter
        include BenefitSponsors::Concerns::ProfileRegistration

        rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

        before_action :set_current_person, only: [:staff_index]
        before_action :check_and_download_commission_statement, only: [:download_commission_statement, :show_commission_statement]
        before_action :set_cache_headers, only: [:show]
        before_action :enable_bs4_layout, only: [:show, :messages, :inbox, :family_index]

        skip_before_action :verify_authenticity_token, only: :create

        layout :resolve_layout

        EMPLOYER_DT_COLUMN_TO_FIELD_MAP = {
          "2" => "legal_name",
          "4" => "employer_profile.aasm_state",
          "5" => "employer_profile.plan_years.start_on"
        }.freeze

        def index
          # a specific instance of BenefitSponsors::Organizations::AssisterAgencyProfile is not needed to test this endpoint
          authorize BenefitSponsors::Organizations::AssisterAgencyProfile
          @assister_agency_profiles = BenefitSponsors::Organizations::Organization.assister_agency_profiles.map(&:assister_agency_profile)
        end

        def show
          @assister_agency_profile = ::BenefitSponsors::Organizations::AssisterAgencyProfile.find(params[:id])
          authorize @assister_agency_profile
          set_flash_by_announcement
          @provider = current_user.person
          @histories = @assister_agency_profile&.primary_assister_role&.person&.assister_role&.workflow_state_transitions
          @id = params[:id]
        end

        def staff_index
          # a specific instance of BenefitSponsors::Organizations::AssisterAgencyProfile is not needed to test this endpoint
          authorize BenefitSponsors::Organizations::AssisterAgencyProfile
          bs4 = params.permit(:bs4)[:bs4]
          @bs4 = bs4 == "true" if bs4
          @q = params.permit(:q)[:q]

          @staff = eligible_assisters
          @page_alphabets = if EnrollRegistry.feature_enabled?(:bs4_consumer_flow)
                              grouped_alphabet(@staff, "last_name")
                            else
                              page_alphabets(@staff, "last_name")
                            end
          @alph_labels = @page_alphabets.map{|alph| [alph.first, alph.last].join("–")} if EnrollRegistry.feature_enabled?(:bs4_consumer_flow)
          page_no = cur_page_no(@page_alphabets.first)
          @staff = if @q.nil?
                     @staff.where(last_name: /^#{page_no}/i)
                   elsif @q.blank?
                     @staff.uniq.sort_by(&:last_name)
                   else
                     assister_profile_ids = BenefitSponsors::Organizations::Organization.where(legal_name: /^#{Regexp.escape(@q)}/i).map(&:profiles).flatten.map(&:id)
                     find_by_agency_name = @staff.where(:'assister_role.benefit_sponsors_assister_agency_profile_id'.in => assister_profile_ids)
                     search_hash = @staff.search_hash(@q)
                     find_by_search_hash = @staff.where(search_hash)
                     unsorted_search = find_by_agency_name + find_by_search_hash
                     unsorted_search.sort_by(&:last_name).uniq
                   end
        end

        # TODO: need to refactor for cases around SHOP assister agencies
        def family_datatable
          find_assister_agency_profile(BSON::ObjectId.from_string(params.permit(:id)[:id]))
          authorize @assister_agency_profile
          @display_family_link = if ::EnrollRegistry.feature_enabled?(:disable_family_link_in_broker_agency)
                                   current_user.has_hbx_staff_role? || !::EnrollRegistry[:disable_family_link_in_broker_agency].setting(:enable_after_time_period).item.cover?(TimeKeeper.date_of_record)
                                 else
                                   true
                                 end
          dt_query = extract_datatable_parameters

          query = BenefitSponsors::Queries::AssisterFamiliesQuery.new(dt_query.search_string, @assister_agency_profile.id, @assister_agency_profile.market_kind)
          @total_records = query.total_count
          @records_filtered = query.filtered_count
          @families = query.filtered_scope.skip(dt_query.skip).limit(dt_query.take).to_a
          primary_member_ids = @families.map do |fam|
            fam.primary_family_member.person_id
          end
          @primary_member_cache = {}
          Person.where(:_id => { "$in" => primary_member_ids }).each do |pers|
            @primary_member_cache[pers.id] = pers
          end

          @draw = dt_query.draw
        end

        def family_index
          find_assister_agency_profile(BSON::ObjectId.from_string(params.permit(:id)[:id]))
          authorize @assister_agency_profile
          @q = params.permit(:q)[:q]

          respond_to do |format|
            format.js
            format.html { render "benefit_sponsors/profiles/assister_agencies/assister_agency_profiles/family_datatable.html.erb" } if @bs4
          end
        end

        def commission_statements
          permitted = params.permit(:id)
          @id = permitted[:id]
          if current_user.has_assister_agency_staff_role?
            id = BSON::ObjectId(params[:id]) || current_user.person.assister_role.benefit_sponsors_assister_agency_profile_id
            find_assister_agency_profile(id)
          elsif current_user.has_hbx_staff_role?
            find_assister_agency_profile(BSON::ObjectId.from_string(@id))
          else
            redirect_to new_profiles_registration_path
            return
          end
          authorize @assister_agency_profile
          documents = @assister_agency_profile.documents
          @statements = get_commission_statements(documents) if documents
          collect_and_sort_commission_statements
          respond_to do |format|
            format.js
          end
        end

        def show_commission_statement
          authorize @assister_agency_profile

          options = {}
          options[:filename] = @commission_statement.title
          options[:type] = 'application/pdf'
          options[:disposition] = 'inline'
          send_data Aws::S3Storage.find(@commission_statement.identifier), options
        end

        def download_commission_statement
          authorize @assister_agency_profile

          options = {}
          options[:content_type] = @commission_statement.type
          options[:filename] = @commission_statement.title
          send_data Aws::S3Storage.find(@commission_statement.identifier), options
        end

        def general_agency_index
          @assister_agency_profile = BenefitSponsors::Organizations::AssisterAgencyProfile.find(params[:id])
          authorize @assister_agency_profile
          @assister_role = current_user.person.assister_role || nil
          @general_agency_profiles = BenefitSponsors::Organizations::GeneralAgencyProfile.all_by_assister_role(@assister_role, approved_only: true)
        end

        def messages
          @sent_box = true
          # don't use current_user
          # messages are different for current_user is admin and assister account login
          @assister_agency_profile = ::BenefitSponsors::Organizations::AssisterAgencyProfile.find(params[:id])
          @assister_provider = @assister_agency_profile&.primary_assister_role&.person
          authorize @assister_agency_profile

          respond_to do |format|
            format.js
          end
        end

        def inbox
          @sent_box = true
          if params["id"].present?
            provider_id = params["id"]
            @assister_agency_provider = Person.find(provider_id)
            @assister_agency_profile = @assister_agency_provider.assister_role.assister_agency_profile
            authorize @assister_agency_profile
          elsif params['profile_id'].present?
            provider_id = params['profile_id']
            @assister_agency_provider = find_assister_agency_profile(BSON::ObjectId(provider_id))
            authorize @assister_agency_provider
          end

          @folder = (params[:folder] || 'Inbox').capitalize

          @provider = (current_user.person._id.to_s == provider_id) ? current_user.person : @assister_agency_provider
        end

        # no auth required for this action: it is used to send an email for prospective assisters, which can be non-users
        # may want to consider implementing some sort of rate limitation on this endpoint to prevent it from being abused
        def email_guide
          notice = "A copy of the Assister Registration Guide has been emailed to #{params[:email]}"
          flash[:notice] = notice
          UserMailer.assister_registration_guide(params).deliver_now
          render 'benefit_sponsors/profiles/registrations/confirmation'
        end

        private

        def check_and_download_commission_statement
          @assister_agency_profile = BenefitSponsors::Organizations::Profile.find(params[:id])
          authorize @assister_agency_profile, :access_to_assister_agency_profile?
          @commission_statement = @assister_agency_profile.documents.find(params[:statement_id])
        end

        def find_assister_agency_profile(id = nil)
          organizations = BenefitSponsors::Organizations::Organization.where(:"profiles._id" => id)
          @assister_agency_profile = organizations.first.assister_agency_profile if organizations.present?
        end

        def user_not_authorized(exception)
          if exception.query == :show?
            redirect_to main_app.new_user_registration_path
          elsif current_user&.has_assister_agency_staff_role?
            redirect_to profiles_assister_agencies_assister_agency_profile_path(:id => current_user.person.assister_agency_staff_roles.first.benefit_sponsors_assister_agency_profile_id)
          else
            redirect_to new_profiles_registration_path(:profile_type => :assister_agency)
          end
        end

        def send_general_agency_assign_msg(general_agency, employer_profile, status); end

        def eligible_assisters
          assister_profile_ids = BenefitSponsors::Organizations::Organization.assister_agency_profiles.approved_assister_agencies.assister_agencies_by_market_kind(['both', person_market_kind]).map(&:assister_agency_profile).pluck(:id)
          Person.where(:"assister_role.benefit_sponsors_assister_agency_profile_id".in => assister_profile_ids, :"assister_role.aasm_state" => "active")
        end

        def update_ga_for_employers(assister_agency_profile, old_default_ga = nil); end

        def person_market_kind
          if @person.has_active_consumer_role?
            "individual"
          elsif @person.has_active_employee_role?
            "shop"
          end
        end

        def check_general_agency_profile_permissions_assign; end

        def check_general_agency_profile_permissions_set_default; end

        def get_commission_statements(documents)
          commission_statements = []
          documents.each do |document|
            # grab only documents that are commission statements by checking the bucket in which they are placed
            commission_statements << document if document.identifier.include?("commission-statements")
          end
          commission_statements
        end

        def collect_and_sort_commission_statements(_sort_order = 'ASC')
          @statement_years = (Settings.aca.shop_market.assister_agency_profile.minimum_commission_statement_year..TimeKeeper.date_of_record.year).to_a.reverse
          @statements.sort_by!(&:date).reverse!
        end

        def enable_bs4_layout
          @bs4 = true if EnrollRegistry.feature_enabled?(:bs4_broker_flow)
        end

        def resolve_layout
          return "single_column" unless EnrollRegistry.feature_enabled?(:bs4_broker_flow)
          "progress"
        end
      end
    end
  end
end
