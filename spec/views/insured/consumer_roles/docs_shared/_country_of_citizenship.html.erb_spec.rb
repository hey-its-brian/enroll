# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'insured/consumer_roles/docs_shared/_country_of_citizenship.html.erb', type: :view do
  let(:person) { FactoryBot.create(:person, :with_consumer_role) }
  let(:consumer_role) { person.consumer_role }
  let(:country_of_citizenship) { 'United States' }
  let(:form_builder) { double('FormBuilder') }

  before do
    allow(form_builder).to receive(:object).and_return(consumer_role)
    assign(:country, country_of_citizenship)
    allow(view).to receive(:l10n).with("insured.consumer_roles.docs_shared.country_of_citizenship").and_return("Country of Citizenship")
    allow(form_builder).to receive(:label).and_return('<label>Country of Citizenship</label>'.html_safe)
    allow(form_builder).to receive(:select).and_return('<select>...</select>'.html_safe)
  end

  context 'when bs4 is enabled' do
    before do
      assign(:bs4, true)
    end

    it 'renders the select field with proper options' do
      render partial: 'insured/consumer_roles/docs_shared/country_of_citizenship', locals: { v: form_builder }
      expect(form_builder).to have_received(:select).with(
        :country_of_citizenship,
        ::VlpDocument::COUNTRIES_LIST,
        { include_blank: l10n("insured.consumer_roles.docs_shared.country_of_citizenship"), allow_blank: true },
        { class: "select_tag", id: "country_of_citizenship" }
      )
    end

    context 'when United States is selected' do
      let(:country_of_citizenship) { 'United States' }

      it 'renders select with United States pre-selected' do
        select_html = '<select class="select_tag" id="country_of_citizenship"><option value="">Country of Citizenship</option><option value="US" selected="selected">United States</option></select>'.html_safe
        allow(form_builder).to receive(:select).and_return(select_html)

        render partial: 'insured/consumer_roles/docs_shared/country_of_citizenship', locals: { v: form_builder }
        expect(rendered).to include('selected="selected">United States</option>')
      end
    end
  end
end