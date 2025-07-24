# frozen_string_literal: true

module Operations
  module Products
    # This operation updates the legal name of a carrier across organizations
    class RebrandCarrier
      include Dry::Monads[:do, :result]

      def call(params)
        old_name, new_name = yield validate(params)
        @logger = yield create_logger
        organizations = yield fetch_organizations(old_name)
        yield update_legal_names(organizations, new_name)

        Success("Updated organization from '#{old_name}' to '#{new_name}'")
      end

      private

      def validate(params)
        return Failure("Missing old name") if params[:old_name].blank?
        return Failure("Missing new name") if params[:new_name].blank?

        Success([params[:old_name], params[:new_name]])
      end

      def fetch_organizations(old_name)
        organizations = ::BenefitSponsors::Organizations::Organization.issuer_profiles.where(legal_name: old_name)
        return Failure("No organizations found with legal name: #{old_name}") if organizations.blank?

        Success(organizations)
      end

      def update_legal_names(organizations, new_name)
        organizations.each do |organization|
          organization.update_attributes!(legal_name: new_name)
          @logger.info { "Updated Organization ID: #{organization.id} - New Legal Name: #{new_name}" }
        end
        Success("Updated legal names")
      end

      def create_logger
        Success(Logger.new("#{Rails.root}/log/carrier_rebranding_report_#{TimeKeeper.date_of_record.strftime('%Y_%m_%d')}.log"))
      end
    end
  end
end
