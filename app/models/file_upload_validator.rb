# frozen_string_literal: true

require 'exifr/jpeg'

# This is not an ActiveRecord model, but rather a virtual model for holding and validating file uploads using the ActiveModel API.
class FileUploadValidator
  include ActiveModel::Model
  include ActiveModel::Validations

  # Common content type groups.
  VERIFICATION_DOC_TYPES = %w[application/pdf image/jpeg image/png image/gif].freeze
  XLS_TYPES = %w[application/vnd.ms-excel application/vnd.openxmlformats-officedocument.spreadsheetml.sheet].freeze
  # Depending on the CSV content, byte-order markers, etc. CSV can show up as a mess of different formats.
  CSV_TYPES = ["text/csv", "text/plain", "application/octet-stream"].freeze
  PDF_TYPE = ['application/pdf'].freeze

  attr_accessor :file_data
  attr_reader :allowed_content_types

  MAX_FILE_SIZE_MB = EnrollRegistry[:upload_file_size_limit_in_mb].item.to_i
  validates :file_data, file_size: { less_than_or_equal_to: MAX_FILE_SIZE_MB.megabytes },
                        file_content_type: { allow: ->(validator) { validator.determine_allowed_types }, mode: :strict, tool: :marcel }

  validate :check_specific_content

  def initialize(file_data:, content_types:)
    @file_data = file_data
    @allowed_content_types = content_types
  end

  def determine_allowed_types
    if expects_pdf?
      ["application/pdf"]
    elsif expects_jpeg?
      ["image/jpeg"]
    else
      @allowed_content_types
    end
  end

  def check_specific_content
    if expects_pdf?
      # rubocop:disable Style/RescueStandardError
      begin
        data = file_data.respond_to?(:path) ? file_data.path : file_data

        reader = PDF::Reader.new(data)
        reader.pdf_version
      rescue
        errors.add(:file_data, "does not appear to be a valid PDF")
      end
      # rubocop:enable Style/RescueStandardError
    elsif expects_jpeg?
      # rubocop:disable Style/RescueStandardError
      begin
        data = file_data.respond_to?(:path) ? file_data.path : file_data
        EXIFR::JPEG.new(data)
      rescue
        errors.add(:file_data, "does not appear to be a valid JPEG")
      end
      # rubocop:enable Style/RescueStandardError
    end
  end

  def human_readable_file_types
    self.class.human_readable_file_types(content_types: @allowed_content_types)
  end

  def self.human_readable_file_types(content_types: VERIFICATION_DOC_TYPES, formatter: [:join, ', '], pluralize: false)
    mime_type_to_readable_name = {
      'application/pdf' => 'PDF',
      'image/jpeg' => 'JPEG',
      'image/png' => 'PNG',
      'image/gif' => 'GIF',
      'text/csv' => 'CSV',
      'application/vnd.ms-excel' => 'XLS',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' => 'XLSX'
      # Additional mappings as needed...
    }.freeze

    formatted_types = content_types.map { |type| mime_type_to_readable_name[type] || type.split('/').last.upcase }
    formatted_types = formatted_types.map(&:pluralize) if pluralize
    formatted_types.send(*formatter)
  end

  protected

  def expects_jpeg?
    return false unless @allowed_content_types == VERIFICATION_DOC_TYPES
    return if file_data.blank?

    file_ext = File.extname(file_data.original_filename)

    (file_data.respond_to?(:content_type) && file_data.content_type == "image/jpeg") || ["jpeg", "jpg"].include?(file_ext)
  end

  def expects_pdf?
    return true if @allowed_content_types == PDF_TYPE
    return false unless @allowed_content_types == VERIFICATION_DOC_TYPES
    return if file_data.blank?

    file_ext = File.extname(file_data.original_filename)

    (file_data.respond_to?(:content_type) && file_data.content_type == "application/pdf") || (file_ext == "pdf")
  end
end
