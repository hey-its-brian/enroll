# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Migrations::DataModelMigrator, type: :model do
  let(:migrator) { described_class.new }
  let(:old_model) { double('OldModel', field_1: "1", field_2: "2") }
  let(:new_model) { double('NewModel') }
  let(:field_mappings) do
    {
      'field_1' => 'field_3',
      'field_2' => 'field_4'
    }
  end

  before do
    allow(YAML).to receive(:safe_load).and_return({ 'test_model' => field_mappings })
    allow(old_model).to receive(:class).and_return(double(name: 'Namespace::TestModel'))
    allow(new_model).to receive(:[]=) # Allow the `:[]=` method on the new_model double
  end

  describe '.field_mappings' do
    it 'returns the correct field mappings for a model' do
      expect(described_class.field_mappings('test_model')).to eq(field_mappings)
    end
  end

  describe '#perform' do
    before do
      allow(old_model).to receive(:[]).with('field_1').and_return('old_value')
      allow(old_model).to receive(:[]).with('field_2').and_return('old_value')
    end

    context "valid" do
      before do
        allow(old_model).to receive(:is_a?).with(::Mongoid::Document).and_return(true)
        allow(new_model).to receive(:is_a?).with(::Mongoid::Document).and_return(true)
        allow(old_model).to receive(:respond_to?).with('field_1').and_return(true)
        allow(old_model).to receive(:respond_to?).with('field_2').and_return(true)
      end

      it 'migrates fields from old_model to new_model' do
        migrator.perform(old_model, new_model)
        expect(new_model).to have_received(:[]=).with('field_3', 'old_value')
      end
    end

    context "invalid" do
      it 'raises error when OldModel is not a Mongoid Document' do
        old_model = double('OldModel', is_a?: false)

        expect do
          migrator.send(:validate_models!, old_model, new_model)
        end.to raise_error(ArgumentError)
      end
    end
  end

  describe '#migrate_field' do
    context 'when field is nested attributes' do
      let(:nested_old_model) { double('NestedOldModel') }
      let(:nested_new_model) { double('NestedNewModel') }
      let(:nested_collection) { [nested_old_model] }

      before do
        allow(old_model).to receive(:respond_to?).with('nested').and_return(true)
        allow(old_model).to receive(:nested).and_return(nested_collection)
        allow(new_model).to receive(:nested_models).and_return(double(build: nested_new_model))
        allow(migrator).to receive(:perform)
      end

      it 'migrates nested attributes' do
        migrator.send(:migrate_nested_attributes, old_model, new_model, 'nested_attributes', 'nested_models')
        expect(migrator).to have_received(:perform).with(nested_old_model, nested_new_model)
      end
    end
  end

  describe '.load_mappings' do
    let(:file_path) { Rails.root.join('app/models/migrations/mapping_config.yml') }
    let(:mappings) { {"test_model" => {"field_1" => "field_3", "field_2" => "field_4"}} }

    before do
      allow(File).to receive(:read).with(file_path).and_return(mappings.to_yaml)
    end

    it 'loads and validates mappings from the configuration file' do
      expect(described_class.load_mappings).to eq(mappings)
    end

    it 'raises an error if the file is missing' do
      allow(File).to receive(:read).and_raise(Errno::ENOENT)
      expect { described_class.load_mappings }.to raise_error(StandardError, /Mapping configuration file not found/)
    end
  end
end