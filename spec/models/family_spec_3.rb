# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Family, dbclean: :after_each do
  let(:user) { FactoryBot.create(:user) }
  let(:person) { FactoryBot.create(:person, :with_family, user: user) }
  let(:family) { person.primary_family }
  let(:current_year) { TimeKeeper.date_of_record.year }
  let(:renewal_year) { current_year.next }

  describe '#previous_year_faa_app_info_needing_evidence_display' do
    context 'Case 1:
      - current_year FAA (migrated or later) with actionable APTC evidences
      - renewal_year QHP' do
      let(:migrated_faa_app) do
        FactoryBot.create(
          :financial_assistance_application,
          family_id: family.id,
          assistance_year: current_year,
          aasm_state: "determined",
          origin: "migration",
          generation_reason: "manual",
          submitted_at: 10.days.ago
        )
      end

      let(:current_year_faa_app) do
        FactoryBot.create(
          :financial_assistance_application,
          family_id: family.id,
          assistance_year: current_year,
          aasm_state: "determined",
          submitted_at: 5.days.ago
        )
      end

      let(:applicant) do
        FactoryBot.create(
          :financial_assistance_applicant,
          :with_work_email,
          :with_work_phone,
          application: current_year_faa_app
        )
      end
      let(:aptc_csr_eligibility) { FactoryBot.create(:aptc_csr_eligibility, eligible: applicant) }
      let(:evidence) { FactoryBot.create(:income_evidence, :outstanding, eligibility: aptc_csr_eligibility) }

      let(:renewal_year_qhp_app) do
        FactoryBot.create(
          :individual_market_application,
          family_id: family.id,
          assistance_year: renewal_year,
          current_state: "determined",
          submitted_at: 3.days.ago
        )
      end

      before do
        migrated_faa_app
        evidence
        renewal_year_qhp_app
      end

      it 'returns FAA application info when current year has FAA after migration and renewal year has QHP' do
        result = family.previous_year_faa_app_info_needing_evidence_display

        expect(result).to eq({ application_type: :faa, application: current_year_faa_app })
      end

      context 'when current year FAA is the migrated application itself' do
        it 'returns FAA application info' do
          result = family.previous_year_faa_app_info_needing_evidence_display

          expect(result).to eq({ application_type: :faa, application: current_year_faa_app })
        end
      end

      context 'when current year has both QHP and FAA, but FAA is more recent' do
        let(:current_year_qhp_app) do
          FactoryBot.create(
            :individual_market_application,
            family_id: family.id,
            assistance_year: current_year,
            current_state: "determined",
            submitted_at: 6.days.ago
          )
        end

        before do
          current_year_qhp_app
        end

        it 'returns FAA application info when FAA is more recent than QHP' do
          result = family.previous_year_faa_app_info_needing_evidence_display

          expect(result).to eq({ application_type: :faa, application: current_year_faa_app })
        end
      end
    end

    context 'Case 2: current_year FAA (migrated or later) + renewal_year FAA' do
      let(:migrated_faa_app) do
        FactoryBot.create(
          :financial_assistance_application,
          family_id: family.id,
          assistance_year: current_year,
          aasm_state: "determined",
          origin: "migration",
          generation_reason: "manual",
          submitted_at: 10.days.ago
        )
      end

      let(:current_year_faa_app) do
        FactoryBot.create(
          :financial_assistance_application,
          family_id: family.id,
          assistance_year: current_year,
          aasm_state: "determined",
          submitted_at: 5.days.ago
        )
      end

      let(:renewal_year_faa_app) do
        FactoryBot.create(
          :financial_assistance_application,
          family_id: family.id,
          assistance_year: renewal_year,
          aasm_state: "determined",
          submitted_at: 3.days.ago
        )
      end

      before do
        migrated_faa_app
        current_year_faa_app
        renewal_year_faa_app
      end

      it 'returns empty hash' do
        result = family.previous_year_faa_app_info_needing_evidence_display
        expect(result).to eq({})
      end
    end

    context 'Case 3: current_year QHP + renewal_year FAA' do
      let(:migrated_faa_app) do
        FactoryBot.create(
          :financial_assistance_application,
          family_id: family.id,
          assistance_year: current_year,
          aasm_state: "determined",
          origin: "migration",
          generation_reason: "manual",
          submitted_at: 10.days.ago
        )
      end

      let(:current_year_qhp_app) do
        FactoryBot.create(
          :individual_market_application,
          family_id: family.id,
          assistance_year: current_year,
          current_state: "determined",
          submitted_at: 5.days.ago
        )
      end

      let(:renewal_year_faa_app) do
        FactoryBot.create(
          :financial_assistance_application,
          family_id: family.id,
          assistance_year: renewal_year,
          aasm_state: "determined",
          submitted_at: 3.days.ago
        )
      end

      before do
        migrated_faa_app
        current_year_qhp_app
        renewal_year_faa_app
      end

      it 'returns empty hash' do
        result = family.previous_year_faa_app_info_needing_evidence_display
        expect(result).to eq({})
      end
    end

    context 'Case 4: current_year QHP + renewal_year QHP' do
      let(:migrated_faa_app) do
        FactoryBot.create(
          :financial_assistance_application,
          family_id: family.id,
          assistance_year: current_year,
          aasm_state: "determined",
          origin: "migration",
          generation_reason: "manual",
          submitted_at: 10.days.ago
        )
      end

      let(:current_year_qhp_app) do
        FactoryBot.create(
          :individual_market_application,
          family_id: family.id,
          assistance_year: current_year,
          current_state: "determined",
          submitted_at: 5.days.ago
        )
      end

      let(:renewal_year_qhp_app) do
        FactoryBot.create(
          :individual_market_application,
          family_id: family.id,
          assistance_year: renewal_year,
          current_state: "determined",
          submitted_at: 3.days.ago
        )
      end

      before do
        migrated_faa_app
        current_year_qhp_app
        renewal_year_qhp_app
      end

      it 'returns empty hash' do
        result = family.previous_year_faa_app_info_needing_evidence_display
        expect(result).to eq({})
      end
    end

    context 'Case 5: current_year FAA (non-migrated) + renewal_year NONE' do
      let(:current_year_faa_app) do
        FactoryBot.create(
          :financial_assistance_application,
          family_id: family.id,
          assistance_year: current_year,
          aasm_state: "determined",
          submitted_at: 5.days.ago
        )
      end

      before do
        current_year_faa_app
      end

      it 'returns empty hash when no migrated FAA app exists' do
        result = family.previous_year_faa_app_info_needing_evidence_display
        expect(result).to eq({})
      end
    end

    context 'Case 6: current_year NONE + renewal_year NONE' do
      it 'returns empty hash when no applications exist' do
        result = family.previous_year_faa_app_info_needing_evidence_display
        expect(result).to eq({})
      end

      context 'when migrated app exists but no determined apps' do
        let(:migrated_faa_app) do
          FactoryBot.create(
            :financial_assistance_application,
            family_id: family.id,
            assistance_year: current_year,
            aasm_state: "submitted", # not determined
            origin: "migration",
            generation_reason: "manual",
            submitted_at: 10.days.ago
          )
        end

        before do
          migrated_faa_app
        end

        it 'returns empty hash' do
          result = family.previous_year_faa_app_info_needing_evidence_display
          expect(result).to eq({})
        end
      end
    end

    context 'Case 7:
      - current_year FAA (migrated or later) without actionable APTC evidences
      - renewal_year QHP' do
      let(:migrated_faa_app) do
        FactoryBot.create(
          :financial_assistance_application,
          family_id: family.id,
          assistance_year: current_year,
          aasm_state: "determined",
          origin: "migration",
          generation_reason: "manual",
          submitted_at: 10.days.ago
        )
      end

      let(:current_year_faa_app) do
        FactoryBot.create(
          :financial_assistance_application,
          family_id: family.id,
          assistance_year: current_year,
          aasm_state: "determined",
          submitted_at: 5.days.ago
        )
      end

      let(:applicant) { FactoryBot.create(:financial_assistance_applicant, application: current_year_faa_app) }
      let(:aptc_csr_eligibility) { FactoryBot.create(:aptc_csr_eligibility, eligible: applicant) }
      let(:esi_mec_evidence) { FactoryBot.create(:esi_mec_evidence, :verified, eligibility: aptc_csr_eligibility) }
      let(:income_evidence) { FactoryBot.create(:income_evidence, :verified, eligibility: aptc_csr_eligibility) }
      let(:local_mec_evidence) { FactoryBot.create(:local_mec_evidence, :verified, eligibility: aptc_csr_eligibility) }
      let(:non_esi_mec_evidence) { FactoryBot.create(:non_esi_mec_evidence, :verified, eligibility: aptc_csr_eligibility) }

      let(:renewal_year_qhp_app) do
        FactoryBot.create(
          :individual_market_application,
          family_id: family.id,
          assistance_year: renewal_year,
          current_state: "determined",
          submitted_at: 3.days.ago
        )
      end

      before do
        migrated_faa_app
        esi_mec_evidence
        income_evidence
        local_mec_evidence
        non_esi_mec_evidence
        renewal_year_qhp_app
      end

      it 'does not return FAA application info when current year FAA lacks actionable APTC evidences' do
        result = family.previous_year_faa_app_info_needing_evidence_display
        expect(result).to be_empty
      end
    end

    context 'Edge cases and complex scenarios' do
      context 'when FAA application exists before migration' do
        let(:migrated_faa_app) do
          FactoryBot.create(
            :financial_assistance_application,
            family_id: family.id,
            assistance_year: current_year,
            aasm_state: "determined",
            origin: "migration",
            generation_reason: "manual",
            submitted_at: 10.days.ago
          )
        end

        let(:applicant) { FactoryBot.create(:financial_assistance_applicant, application: migrated_faa_app) }
        let(:aptc_csr_eligibility) { FactoryBot.create(:aptc_csr_eligibility, eligible: applicant) }
        let(:evidence) { FactoryBot.create(:income_evidence, :outstanding, eligibility: aptc_csr_eligibility) }

        let(:pre_migration_faa_app) do
          FactoryBot.create(
            :financial_assistance_application,
            family_id: family.id,
            assistance_year: current_year,
            aasm_state: "determined",
            submitted_at: 15.days.ago # before migration
          )
        end

        let(:renewal_year_qhp_app) do
          FactoryBot.create(
            :individual_market_application,
            family_id: family.id,
            assistance_year: renewal_year,
            current_state: "determined",
            submitted_at: 3.days.ago
          )
        end

        before do
          evidence
          pre_migration_faa_app
          renewal_year_qhp_app
        end

        it 'ignores pre-migration FAA and uses migrated FAA' do
          result = family.previous_year_faa_app_info_needing_evidence_display
          expect(result).to eq({ application_type: :faa, application: migrated_faa_app })
        end
      end

      context 'when multiple applications exist in renewal year' do
        let(:migrated_faa_app) do
          FactoryBot.create(
            :financial_assistance_application,
            family_id: family.id,
            assistance_year: current_year,
            aasm_state: "determined",
            origin: "migration",
            generation_reason: "manual",
            submitted_at: 10.days.ago
          )
        end

        let(:current_year_faa_app) do
          FactoryBot.create(
            :financial_assistance_application,
            family_id: family.id,
            assistance_year: current_year,
            aasm_state: "determined",
            submitted_at: 5.days.ago
          )
        end

        let(:applicant) { FactoryBot.create(:financial_assistance_applicant, application: current_year_faa_app) }
        let(:aptc_csr_eligibility) { FactoryBot.create(:aptc_csr_eligibility, eligible: applicant) }
        let(:evidence) { FactoryBot.create(:income_evidence, :outstanding, eligibility: aptc_csr_eligibility) }

        let(:renewal_year_qhp_app_older) do
          FactoryBot.create(
            :individual_market_application,
            family_id: family.id,
            assistance_year: renewal_year,
            current_state: "determined",
            submitted_at: 4.days.ago
          )
        end

        let(:renewal_year_qhp_app_newer) do
          FactoryBot.create(
            :individual_market_application,
            family_id: family.id,
            assistance_year: renewal_year,
            current_state: "determined",
            submitted_at: 2.days.ago
          )
        end

        let(:renewal_year_faa_app) do
          FactoryBot.create(
            :financial_assistance_application,
            family_id: family.id,
            assistance_year: renewal_year,
            aasm_state: "determined",
            submitted_at: 3.days.ago
          )
        end

        before do
          migrated_faa_app
          evidence
          renewal_year_qhp_app_older
          renewal_year_qhp_app_newer
          renewal_year_faa_app
        end

        it 'uses the most recent renewal year application (QHP in this case)' do
          result = family.previous_year_faa_app_info_needing_evidence_display

          expect(result).to eq({ application_type: :faa, application: current_year_faa_app })
        end
      end

      context 'when QHP is more recent than post-migration FAA in current year' do
        let(:migrated_faa_app) do
          FactoryBot.create(
            :financial_assistance_application,
            family_id: family.id,
            assistance_year: current_year,
            aasm_state: "determined",
            origin: "migration",
            generation_reason: "manual",
            submitted_at: 10.days.ago
          )
        end

        let(:current_year_faa_app) do
          FactoryBot.create(
            :financial_assistance_application,
            family_id: family.id,
            assistance_year: current_year,
            aasm_state: "determined",
            submitted_at: 6.days.ago
          )
        end

        let(:current_year_qhp_app) do
          FactoryBot.create(
            :individual_market_application,
            family_id: family.id,
            assistance_year: current_year,
            current_state: "determined",
            submitted_at: 4.days.ago # more recent than FAA
          )
        end

        let(:renewal_year_qhp_app) do
          FactoryBot.create(
            :individual_market_application,
            family_id: family.id,
            assistance_year: renewal_year,
            current_state: "determined",
            submitted_at: 2.days.ago
          )
        end

        before do
          migrated_faa_app
          current_year_faa_app
          current_year_qhp_app
          renewal_year_qhp_app
        end

        it 'returns empty hash when current year QHP is more recent than post-migration FAA' do
          result = family.previous_year_faa_app_info_needing_evidence_display
          expect(result).to eq({})
        end
      end

      context 'when an application is non-migrated' do
        let(:non_migrated_migrated_faa_app) do
          FactoryBot.create(
            :financial_assistance_application,
            family_id: family.id,
            assistance_year: current_year,
            aasm_state: "determined",
            origin: "user",
            generation_reason: "manual",
            submitted_at: 10.days.ago
          )
        end

        let(:current_year_faa_app) do
          FactoryBot.create(
            :financial_assistance_application,
            family_id: family.id,
            assistance_year: current_year,
            aasm_state: "determined",
            submitted_at: 5.days.ago
          )
        end

        let(:renewal_year_qhp_app) do
          FactoryBot.create(
            :individual_market_application,
            family_id: family.id,
            assistance_year: renewal_year,
            current_state: "determined",
            submitted_at: 3.days.ago
          )
        end

        before do
          non_migrated_migrated_faa_app
          current_year_faa_app
          renewal_year_qhp_app
        end

        it 'returns empty hash when no manual migration exists' do
          result = family.previous_year_faa_app_info_needing_evidence_display
          expect(result).to eq({})
        end
      end

      context 'when applications exist but none are determined' do
        let(:migrated_faa_app) do
          FactoryBot.create(
            :financial_assistance_application,
            family_id: family.id,
            assistance_year: current_year,
            aasm_state: "submitted", # not determined
            origin: "migration",
            generation_reason: "manual",
            submitted_at: 10.days.ago
          )
        end

        let(:current_year_faa_app) do
          FactoryBot.create(
            :financial_assistance_application,
            family_id: family.id,
            assistance_year: current_year,
            aasm_state: "submitted", # not determined
            submitted_at: 5.days.ago
          )
        end

        let(:renewal_year_qhp_app) do
          FactoryBot.create(
            :individual_market_application,
            family_id: family.id,
            assistance_year: renewal_year,
            current_state: "submitted", # not determined
            submitted_at: 3.days.ago
          )
        end

        before do
          migrated_faa_app
          current_year_faa_app
          renewal_year_qhp_app
        end

        it 'returns empty hash when no determined applications exist' do
          result = family.previous_year_faa_app_info_needing_evidence_display
          expect(result).to eq({})
        end
      end
    end
  end
end
