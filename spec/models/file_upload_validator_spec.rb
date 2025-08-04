# frozen_string_literal: true

require 'rails_helper'


# rubocop:disable Metrics/ParameterLists
RSpec.shared_examples_for "a validator which rejects" do |category, named_like, content_description, content_types, path, kind|
  context "a #{category}:
  - #{named_like}
  - #{content_description}
  " do
    subject do
      file_upload = fixture_file_upload(path, kind)
      FileUploadValidator.new(file_data: file_upload, content_types: content_types)
    end

    it "is invalid" do
      expect(subject.valid?).to be_falsey
    end
  end
end

RSpec.shared_examples_for "a validator which accepts" do |ext, named_like, content_description, content_types, path, kind|
  context "a #{ext}:
  - #{named_like}
  - #{content_description}
  " do
    subject do
      file_upload = fixture_file_upload(path, kind)
      FileUploadValidator.new(file_data: file_upload, content_types: content_types)
    end

    it "is valid" do
      expect(subject.valid?).to be_truthy
    end
  end
end
# rubocop:enable Metrics/ParameterLists

RSpec.describe FileUploadValidator, "with improved content validation" do
  it_behaves_like(
    "a validator which rejects",
    "PDF",
    "named like a PDF",
    "but does not contain pdf data",
    FileUploadValidator::PDF_TYPE,
    "#{Rails.root}/test/invalid_content_pdf.pdf",
    "application/pdf"
  )

  it_behaves_like(
    "a validator which rejects",
    "verification document",
    "named like a PDF",
    "does not contain pdf data",
    FileUploadValidator::VERIFICATION_DOC_TYPES,
    "#{Rails.root}/test/invalid_content_pdf.pdf",
    "application/pdf"
  )

  it_behaves_like("a validator which rejects", "verification document", "named like a jpeg", "contains png data", FileUploadValidator::VERIFICATION_DOC_TYPES, "#{Rails.root}/test/actually_a_png.jpeg", "image/jpeg")
  it_behaves_like("a validator which rejects", "verification document", "named like a jpeg", "contains bogus data", FileUploadValidator::VERIFICATION_DOC_TYPES, "#{Rails.root}/test/invalid_content_jpeg.jpg", "image/jpeg")


  it_behaves_like("a validator which accepts", "CSV", "named like a CSV", "contains CSV data", FileUploadValidator::CSV_TYPES, "#{Rails.root}/ivl_testbed_scenarios_2021.csv", "text/csv")
  it_behaves_like("a validator which accepts", "PDF", "named like a PDF", "contains pdf data", FileUploadValidator::PDF_TYPE, "#{Rails.root}/lib/pdf_templates/blank.pdf", "application/pdf")
  it_behaves_like("a validator which accepts", "PDF", "named like a PDF", "contains pdf data", FileUploadValidator::PDF_TYPE, "#{Rails.root}/test/JavaScript.pdf", "application/pdf")
  it_behaves_like("a validator which accepts", "verification document", "named like a PDF", "contains pdf data", FileUploadValidator::VERIFICATION_DOC_TYPES, "#{Rails.root}/test/JavaScript.pdf", "application/pdf")
  it_behaves_like("a validator which accepts", "verification document", "named like a PDF", "contains pdf data", FileUploadValidator::VERIFICATION_DOC_TYPES, "#{Rails.root}/lib/pdf_templates/blank.pdf", "application/pdf")
  it_behaves_like("a validator which accepts", "verification document", "named like a jpeg", "contains valid data", FileUploadValidator::VERIFICATION_DOC_TYPES, "#{Rails.root}/test/valid_content_jpeg.jpg", "image/jpeg")
end