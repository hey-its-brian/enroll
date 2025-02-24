# frozen_string_literal: true

require 'rails_helper'

describe Effective::Datatables::PeopleDataTable, "with correct access permissions" do

  let(:admin_user) { FactoryBot.create(:user, person: admin_person) }
  let(:admin_person) { FactoryBot.create(:person, :with_hbx_staff_role) }
  let(:regular_user) { FactoryBot.create(:user, person: regular_person) }
  let(:regular_person) {FactoryBot.create(:person) }

  subject { Effective::Datatables::PeopleDataTable.new }

  it "allows hbx staff which have the permission" do
    expect(subject.authorized?(admin_user, nil, nil, nil)).to be_truthy
  end

  it "blocks regular users" do
    expect(subject.authorized?(regular_user, nil, nil, nil)).to be_falsey
  end
end
