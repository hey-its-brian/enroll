# frozen_string_literal: true

module Operations
  # This class is responsible for updating consumer demographic information.
  class ApplyConsumerDemographicUpdates
    include Dry::Monads[:do, :result]

    def call(params)
      values = yield validate(params)
      apply_updates     = yield apply_updates(values)

      Success(apply_updates)
    end

    def validate(params)
      return Failure("params are missing") if params.blank?
      Success(params)
    end

    def apply_updates(update_data)
      person = update_data[:person]
      build_addresses(
        update_data[:mailing_address],
        update_data[:home_address],
        update_data[:destroyed_mailing_address_params],
        person
      )

      update_lawful_presence(update_data)
      update_consumer_role(update_data)
      update_addresses(update_data)
      update_contact_info(update_data)
      person.assign_attributes(update_data[:person_params]) unless update_data[:person_params].empty?
      person.save!
      Success("Person updated successfully")
    end

    def update_lawful_presence(update_data)
      lpd_attributes = update_data[:lawful_presence_determination_attributes]
      return if lpd_attributes.empty?

      update_data[:person].consumer_role.lawful_presence_determination.update_attributes!(lpd_attributes)
    end

    def update_consumer_role(update_data)
      consumer_role_attributes = update_data[:consumer_role_attributes]
      return if consumer_role_attributes.empty?

      update_data[:consumer_role].update_attributes!(consumer_role_attributes)
    end

    def update_addresses(update_data)
      update_mailing_address(update_data)
      update_home_address(update_data)
    end

    def update_mailing_address(update_data)
      mailing_address = update_data[:mailing_address]
      mailing_address_params = update_data[:mailing_address_params]
      return if mailing_address_params.empty? || mailing_address.nil?

      if mailing_address_params[:zip].present?
        mailing_county = fetch_county(mailing_address_params[:zip])
        mailing_address.update_attributes(mailing_address_params.merge!(county: mailing_county))
      else
        mailing_address.update_attributes(mailing_address_params)
      end
    end

    def update_home_address(update_data)
      home_address = update_data[:home_address]
      home_address_params = update_data[:home_address_params]
      return if home_address_params.empty? || home_address.nil?

      if home_address_params[:zip].present?
        home_county = fetch_county(home_address_params[:zip])
        home_address.update_attributes(home_address_params.merge!(county: home_county))
      else
        home_address.update_attributes(home_address_params)
      end
    end

    def update_contact_info(update_data)
      update_emails(update_data)
      update_phones(update_data)
    end

    def update_emails(update_data)
      home_email = update_data[:home_email_address]
      work_email = update_data[:work_email_address]
      home_email_hash = update_data[:home_email_hash]
      work_email_hash = update_data[:work_email_hash]

      home_email&.update_attributes!(home_email_hash) unless home_email_hash.empty?
      work_email&.update_attributes!(work_email_hash) unless work_email_hash.empty?
    end

    def update_phones(update_data)
      home_phone = update_data[:home_phone]
      work_phone = update_data[:work_phone]
      mobile_phone = update_data[:mobile_phone]
      home_phone_hash = update_data[:home_phone_hash]
      work_phone_hash = update_data[:work_phone_hash]
      mobile_phone_hash = update_data[:mobile_phone_hash]
      home_phone&.update_attributes!(home_phone_hash) unless home_phone_hash.empty?
      work_phone&.update_attributes!(work_phone_hash) unless work_phone_hash.empty?
      mobile_phone&.update_attributes!(mobile_phone_hash) unless mobile_phone_hash.empty?
    end

    private

    def build_addresses(mailing_address, _home_address, destroyed_mailing_address_params, person)
      return unless mailing_address.nil? && destroyed_mailing_address_params[:state].to_s == "ME" && destroyed_mailing_address_params.keys.count >= 5
      county = fetch_county(destroyed_mailing_address_params[:zip])
      address_attributes = {:address_1 => destroyed_mailing_address_params[:address_1], :kind => 'mailing', :address_2 => destroyed_mailing_address_params[:address_2], :address_3 => destroyed_mailing_address_params[:address_3],
                            :city => destroyed_mailing_address_params[:city], :state => destroyed_mailing_address_params[:state], :zip => destroyed_mailing_address_params[:zip], :county => county}
      person.addresses.build(address_attributes)
    end

    def fetch_county(zip)
      county_zip = ::BenefitMarkets::Locations::CountyZip.where(zip: zip).first
      county_zip.present? ? county_zip.county_name : nil
    end
  end
end