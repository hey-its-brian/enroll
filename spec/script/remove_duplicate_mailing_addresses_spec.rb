# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'script/remove_duplicate_mailing_addresses.rb', type: :task do
  let(:timestamp) {Time.current.strftime('%Y_%m_%d_%H%M%S')}
  let(:output_path) { Rails.root.join("multiple_mailing_addresses_cleanup_#{timestamp}.csv").to_s }

  def create_person_with_addresses
    person = FactoryBot.create(:person)

    person.addresses.create!(
      kind: 'mailing',
      address_1: '123 Main St',
      address_2: '',
      city: 'Washington',
      state: 'DC',
      zip: '20001',
      created_at: 3.days.ago
    )

    person.addresses.create!(
      kind: 'mailing',
      address_1: '456 Oak Ave',
      address_2: 'Apt 2',
      city: 'Arlington',
      state: 'VA',
      zip: '22202',
      created_at: 2.days.ago
    )

    person.addresses.create!(
      kind: 'mailing',
      address_1: '456 Oak Ave',
      address_2: 'Apt 2',
      city: 'Arlington',
      state: 'VA',
      zip: '22202',
      created_at: 1.day.ago
    )

    person
  end

  before do
    FileUtils.mkdir_p(File.dirname(output_path))
    FileUtils.rm_f(output_path)
  end

  after do
    FileUtils.rm_f(output_path)
  end

  it 'generates a CSV' do
    person = create_person_with_addresses
    expect(person.addresses.where(kind: 'mailing').count).to eq(3)


    load Rails.root.join('script/remove_duplicate_mailing_addresses.rb')

    expect(File.exist?(output_path)).to be true
    csv = CSV.read(output_path)
    headers = csv.first
    rows = csv[1..]

    expect(headers).to include('person_hbx_id', 'duplicate_groups', 'destroyed_count', 'kept_address')
    expect(rows.size).to eq(1)
    row = rows.first
    expect(row[0]).to eq(person.hbx_id)
    expect(row[2].to_i).to eq(1)

    expect(person.reload.addresses.where(kind: 'mailing').count).to eq(2)
  end

  it 'destroys duplicate mailing addresses' do
    person = create_person_with_addresses
    expect(person.addresses.where(kind: 'mailing').count).to eq(3)


    load Rails.root.join('script/remove_duplicate_mailing_addresses.rb')
    expect(person.reload.addresses.where(kind: 'mailing').count).to eq(2)

    expect(File.exist?(output_path)).to be true
    csv = CSV.read(output_path)
    rows = csv[1..]
    expect(rows.size).to eq(1)
  end
end
