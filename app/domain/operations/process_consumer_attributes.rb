# frozen_string_literal: true

module Operations
  # This operation is responsible for processing changed consumer attributes
  class ProcessConsumerAttributes
    include Dry::Monads[:do, :result]

    def call(params)
      _build_demographic_params = yield process_attributes(params)

      Success("Attributes built")
    end

    def process_attributes(params)
      max_count = params[:row].length || 0
      (1..max_count).each do |i|
        attribute_col = "diff#{i}_attribute"
        report1_col = "diff#{i}_report1_value"
        report2_col = "diff#{i}_report2_value"

        attribute = params[:row][attribute_col]
        report1_value = params[:row][report1_col]
        report2_value = params[:row][report2_col]
        next if attribute.nil? || attribute.strip.empty?
        values = {attribute: attribute, report1_value: report1_value, report2_value: report2_value, update_data: params[:update_data], results: params[:results], changed_results: params[:changed_results], hbx_id: params[:hbx_id]}

        update_single_attribute(values)
      end
      Success("Attributes processed")
    end

    def update_single_attribute(values)
      handler = attribute_handler_for(values[:attribute])
      return unless handler

      handler.call(values)
    end

    def attribute_handler_for(attribute)
      handlers = {
        "is_incarcerated" => method(:handle_boolean_attribute),
        "is_applying_coverage" => method(:handle_boolean_attribute),
        "is_homeless" => method(:handle_boolean_attribute),
        "middle_name" => method(:handle_string_attribute),
        "no_ssn" => method(:handle_string_attribute),
        "tribal_state" => method(:handle_string_attribute),
        "ethnicity" => method(:handle_ethnicity_attribute),
        "citizen_status" => method(:handle_citizen_status_attribute),
        "mailing_address_1" => method(:handle_mailing_address_attribute),
        "mailing_address_2" => method(:handle_mailing_address_attribute),
        "mailing_city" => method(:handle_mailing_address_attribute),
        "mailing_state" => method(:handle_mailing_address_attribute),
        "mailing_zip" => method(:handle_mailing_address_attribute),
        "mailing_county" => method(:handle_mailing_address_attribute),
        "home_address_1" => method(:handle_home_address_attribute),
        "home_address_2" => method(:handle_home_address_attribute),
        "home_city" => method(:handle_home_address_attribute),
        "home_state" => method(:handle_home_address_attribute),
        "home_zip" => method(:handle_home_address_attribute),
        "home_county" => method(:handle_home_address_attribute),
        "home_email_address" => method(:handle_email_attribute),
        "home_phone_number" => method(:handle_phone_attribute),
        "mobile_phone_number" => method(:handle_phone_attribute)
      }
      handlers[attribute]
    end

    def handle_citizen_status_attribute(values)
      report1_value = values[:report1_value]
      report2_value = values[:report2_value]
      attribute = values[:attribute]
      results = values[:results]
      changed_results = values[:changed_results]
      hbx_id = values[:hbx_id]
      person = values[:update_data][:person]
      changes = values[:update_data][:changes]
      different_values = values[:update_data][:different_values]

      current_value = person.consumer_role.lawful_presence_determination.citizen_status
      updated_value = (current_value.to_s == report2_value.to_s) ? report1_value : current_value
      values[:update_data][:person_params][attribute] = updated_value.present? ? updated_value : nil

      changes << [attribute, current_value, updated_value]
      results[person.hbx_id] = changes unless changes.empty?

      return unless current_value.to_s != report2_value.to_s
      different_values << [attribute, report2_value, current_value]
      changed_results[hbx_id] = different_values
    end

    def handle_mailing_address_attribute(values)
      report1_value = values[:report1_value]
      report2_value = values[:report2_value]
      attribute = values[:attribute]
      results = values[:results]
      changed_results = values[:changed_results]
      hbx_id = values[:hbx_id]
      person = values[:update_data][:person]
      changes = values[:update_data][:changes]
      different_values = values[:update_data][:different_values]
      mailing_address = values[:update_data][:mailing_address]
      mailing_address_params = values[:update_data][:mailing_address_params]

      field_mappings = {
        "mailing_address_1" => :address_1,
        "mailing_address_2" => :address_2,
        "mailing_city" => :city,
        "mailing_state" => :state,
        "mailing_zip" => :zip,
        "mailing_county" => :county
      }

      field = field_mappings[attribute]
      return unless field

      if mailing_address.present?
        current_value = mailing_address.send(field)
        if current_value.to_s == report2_value.to_s
          updated_value = report1_value
          mailing_address_params[field] = report1_value
        end

        changes << [attribute, current_value, updated_value]
        results[person.hbx_id] = changes unless changes.empty?

        return unless current_value.to_s != report2_value.to_s
        different_values << [attribute, report2_value, current_value]
        changed_results[hbx_id] = different_values
      else
        values[:update_data][:destroyed_mailing_address_params][field] = report1_value
        changes << [attribute, "#{attribute} Absent", report1_value]
        results[person.hbx_id] = changes unless changes.empty?
      end
    end

    def handle_phone_attribute(values)
      update_data = values[:update_data]
      report1_value = values[:report1_value]
      report2_value = values[:report2_value]
      attribute = values[:attribute]
      results = values[:results]
      changed_results = values[:changed_results]
      hbx_id = values[:hbx_id]

      person = update_data[:person]
      changes = update_data[:changes]
      different_values = update_data[:different_values]

      case attribute

      when "home_phone_number"
        phone = update_data[:home_phone]
        phone_hash = update_data[:home_phone_hash]
      when "mobile_phone_number"
        phone = update_data[:mobile_phone]
        phone_hash = update_data[:mobile_phone_hash]
      end
      current_value = phone.full_phone_number

      if current_value.to_s == report2_value.to_s
        updated_value = report1_value
        phone_hash[:full_phone_number] = report1_value
      else
        updated_value = current_value
      end

      changes << [attribute, current_value, updated_value]
      results[person.hbx_id] = changes unless changes.empty?

      return unless current_value.to_s != report2_value.to_s
      different_values << [attribute, report2_value, current_value]
      changed_results[hbx_id] = different_values
    end

    def handle_email_attribute(values)
      update_data = values[:update_data]
      report1_value = values[:report1_value]
      report2_value = values[:report2_value]
      attribute = values[:attribute]
      results = values[:results]
      changed_results = values[:changed_results]
      hbx_id = values[:hbx_id]
      person = update_data[:person]
      changes = update_data[:changes]
      different_values = update_data[:different_values]

      email = update_data[:home_email_address]
      email_hash = update_data[:home_email_hash]

      current_value = email.address
      if current_value.to_s == report2_value.to_s
        updated_value = report1_value
        email_hash[:address] = report1_value
      else
        updated_value = current_value
      end

      changes << [attribute, current_value, updated_value]
      results[person.hbx_id] = changes unless changes.empty?

      return unless current_value.to_s != report2_value.to_s
      different_values << [attribute, report2_value, current_value]
      changed_results[hbx_id] = different_values
    end

    def handle_home_address_attribute(values)
      update_data = values[:update_data]
      report1_value = values[:report1_value]
      report2_value = values[:report2_value]
      attribute = values[:attribute]
      results = values[:results]
      changed_results = values[:changed_results]
      hbx_id = values[:hbx_id]
      person = update_data[:person]
      changes = update_data[:changes]
      different_values = update_data[:different_values]
      home_address = update_data[:home_address]
      home_address_params = update_data[:home_address_params]

      return unless home_address

      field_mappings = {
        "home_address_1" => :address_1,
        "home_address_2" => :address_2,
        "home_city" => :city,
        "home_state" => :state,
        "home_zip" => :zip,
        "home_county" => :county
      }

      field = field_mappings[attribute]
      return unless field

      current_value = home_address.send(field)

      if current_value.to_s == report2_value.to_s
        updated_value = report1_value
        home_address_params[field] = report1_value
      else
        updated_value = current_value
      end

      changes << [attribute, current_value, updated_value]
      results[person.hbx_id] = changes unless changes.empty?
      return unless current_value.to_s != report2_value.to_s
      different_values << [attribute, report2_value, current_value]
      changed_results[hbx_id] = different_values
    end

    def handle_boolean_attribute(values)
      update_data = values[:update_data]
      report1_value = values[:report1_value]
      report2_value = values[:report2_value]
      attribute = values[:attribute]
      results = values[:results]
      changed_results = values[:changed_results]
      hbx_id = values[:hbx_id]
      person = update_data[:person]
      changes = update_data[:changes]
      different_values = update_data[:different_values]

      case attribute
      when "is_incarcerated"
        current_value = person.is_incarcerated
        params_key = :person_params
        attribute_key = :is_incarcerated
      when "is_applying_coverage"
        current_value = update_data[:consumer_role].is_applying_coverage
        params_key = :consumer_role_attributes
        attribute_key = :is_applying_coverage
      when "is_homeless"
        current_value = person.is_homeless
        params_key = :person_params
        attribute_key = :is_homeless
      end

      updated_value = (current_value.to_s == report2_value.to_s.downcase) ? report1_value&.downcase : current_value
      update_data[params_key][attribute_key] = updated_value.to_s.present? ? updated_value.to_s == "true" : nil

      changes << [attribute, current_value, updated_value]
      results[person.hbx_id] = changes unless changes.empty?

      return unless current_value.to_s != report2_value.to_s.downcase
      different_values << [attribute, report2_value, current_value]
      changed_results[hbx_id] = different_values
    end

    def handle_string_attribute(values)
      update_data = values[:update_data]
      report1_value = values[:report1_value]
      report2_value = values[:report2_value]
      attribute = values[:attribute]
      results = values[:results]
      changed_results = values[:changed_results]
      hbx_id = values[:hbx_id]
      person = update_data[:person]
      changes = update_data[:changes]
      different_values = update_data[:different_values]

      case attribute
      when "middle_name"
        current_value = person.middle_name
        params_key = :person_params
        attribute_key = :middle_name
      when "no_ssn"
        current_value = person.no_ssn
        params_key = :person_params
        attribute_key = :no_ssn
      when "tribal_state"
        current_value = person.tribal_state
        params_key = :person_params
        attribute_key = :tribal_state
      end

      updated_value = (current_value.to_s == report2_value.to_s) ? report1_value.to_s : current_value
      update_data[params_key][attribute_key] = updated_value.present? ? updated_value : nil

      changes << [attribute, current_value, updated_value]
      results[person.hbx_id] = changes unless changes.empty?

      return unless current_value.to_s != report2_value.to_s
      different_values << [attribute, report2_value, current_value]
      changed_results[hbx_id] = different_values
    end

    def handle_ethnicity_attribute(values)
      update_data = values[:update_data]
      report1_value = values[:report1_value]
      report2_value = values[:report2_value]
      attribute = values[:attribute]
      results = values[:results]
      changed_results = values[:changed_results]
      hbx_id = values[:hbx_id]
      person = update_data[:person]
      changes = update_data[:changes]
      different_values = update_data[:different_values]

      case attribute
      when "ethnicity"
        current_value = person.ethnicity
        params_key = :person_params
        attribute_key = :ethnicity
      end
      updated_value = (current_value == JSON.parse(report2_value)) ? report1_value : current_value
      update_data[params_key][attribute_key] = updated_value.instance_of?(String) ? JSON.parse(updated_value) : updated_value

      changes << [attribute, current_value, updated_value]
      results[person.hbx_id] = changes unless changes.empty?

      return unless current_value.to_s != report2_value
      different_values << [attribute, report2_value, current_value]
      changed_results[hbx_id] = different_values
    end
  end
end