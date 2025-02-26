# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::Operations::HbxEnrollments::Expire, dbclean: :around_each do
  include Dry::Monads[:do, :result]

  let(:family)      { FactoryBot.create(:family, :with_primary_family_member) }
  let!(:enrollment) { FactoryBot.create(:hbx_enrollment, :individual_unassisted, family: family) }
  let(:transmittable_job) do
    ::Operations::Transmittable::CreateJob.new.call(
      {
        key: :hbx_enrollments_expiration,
        title: "Request expiration of all active IVL enrollments.",
        description: "Job that requests expiration of all active IVL enrollments.",
        publish_on: DateTime.now,
        started_at: DateTime.now
      }
    ).success
  end

  let(:request_transmission) do
    operation_instance.request_transmission
  end

  let(:request_transaction) do
    operation_instance.request_transaction
  end

  let(:job_process_status) { transmittable_job.process_status }

  let(:transmittable_transmission) { FactoryBot.create(:transmittable_transmission, job: transmittable_job) }

  let(:logger) do
    File.read("#{Rails.root}/log/hbx_enrollments_expire_#{TimeKeeper.date_of_record.strftime('%Y_%m_%d')}.log")
  end

  describe 'with invalid params' do
    context 'failure' do
      context 'missing enrollment_gid in params' do
        let(:params) { {} }
        let(:result) { described_class.new.call(params) }

        it 'returns a failure' do
          expect(result.success?).to be_falsey
          expect(result.failure).to eq("Missing enrollment_gid in params: #{params}.")
        end
      end

      context 'missing job_gid in params' do
        let(:params) { { enrollment_gid: "test" } }
        let(:result) { described_class.new.call(params) }

        it 'returns a failure' do
          expect(result.success?).to be_falsey
          expect(result.failure).to eq("Missing job_gid in params: #{params}.")
        end
      end

      context 'find_enrollment' do
        let(:params) do
          { enrollment_gid: "test", job_gid: "test" }
        end
        let(:result) { described_class.new.call(params) }

        context 'invalid enrollment_gid' do
          it 'returns a failure' do
            expect(result.success?).to be_falsey
            expect(result.failure).to eq("No HbxEnrollment found with given global ID: test")
          end
        end

        context 'shop enrollment' do
          let(:params) do
            { enrollment_gid: enrollment.to_global_id.to_s, job_gid: "test" }
          end
          let(:result) { described_class.new.call(params) }
          it 'returns a failure if enrollment is not IVL kind' do
            enrollment.update_attributes(kind: 'employer_sponsored')
            expect(result.success?).to be_falsey
            expect(result.failure).to eq("Failed to expire enrollment hbx id #{enrollment.hbx_id} - #{enrollment.kind} is not a valid IVL enrollment kind")
          end
        end
      end

      context 'find_job_by_global_id' do
        let(:params) do
          { enrollment_gid: enrollment.to_global_id.to_s, job_gid: "test" }
        end
        let(:result) { described_class.new.call(params) }

        context 'invalid job_gid' do
          it 'returns a failure' do
            expect(result.success?).to be_falsey
            expect(result.failure).to eq("No Transmittable::Job found with given global ID: test")
          end
        end
      end

      context 'when transmission creation fails' do
        let(:params) do
          { enrollment_gid: enrollment.to_global_id.to_s, job_gid: transmittable_job.to_global_id.to_s }
        end
        let(:operation_instance) { described_class.new }
        let(:result) { operation_instance.call(params) }

        before :each do
          allow(
            ::Operations::Transmittable::CreateTransmission
          ).to receive(:new).and_return(
            double('CreateTransmission', call: Failure('Failed to create transmission due to invalid params.'))
          )

          result
        end

        it 'returns a failure monad' do
          expect(result.failure).to eq('Failed to create transmission due to invalid params.')
        end

        it 'does not create transmission' do
          expect(transmittable_job.transmissions.count).to eq(0)
          expect(operation_instance.request_transmission).to be_nil
          expect(Transmittable::Transmission.count).to eq(0)
        end

        it 'creates an error associated to the job' do
          expect(transmittable_job.transmittable_errors.count).to eq(1)
          expect(transmittable_job.transmittable_errors.first.key).to eq(:create_request_transmission)
          expect(Transmittable::Error.all.count).to eq(1)
          expect(Transmittable::Error.first.errorable).to eq(transmittable_job)
        end

        it 'updates the process status and creates new process state associated to the job' do
          expect(job_process_status.reload.latest_state).to eq(:failed)
          expect(job_process_status.process_states.count).to eq(2)
          expect(job_process_status.process_states.last.state_key).to eq(:failed)
        end
      end

      context 'when transaction creation fails' do
        let(:params) do
          { enrollment_gid: enrollment.to_global_id.to_s, job_gid: transmittable_job.to_global_id.to_s }
        end
        let(:operation_instance) { described_class.new }
        let(:result) { operation_instance.call(params) }

        before :each do
          allow(
            ::Operations::Transmittable::CreateTransaction
          ).to receive(:new).and_return(
            double('CreateTransaction', call: Failure('Failed to create transaction due to invalid params.'))
          )

          result
        end

        it 'returns a failure monad' do
          expect(result.failure).to eq('Failed to create transaction due to invalid params.')
        end

        it 'does not create transaction' do
          expect(request_transmission.transactions.count).to eq(0)
          expect(operation_instance.request_transaction).to be_nil
          expect(Transmittable::Transaction.count).to eq(0)
        end

        it 'creates an error associated to the job and transmission' do
          expect(request_transmission.transmittable_errors.count).to eq(1)
          expect(request_transmission.transmittable_errors.first.key).to eq(:create_request_transaction)
          expect(transmittable_job.transmittable_errors.count).to eq(1)
          expect(transmittable_job.transmittable_errors.first.key).to eq(:create_request_transaction)
          expect(Transmittable::Error.all.count).to eq(2)
          expect(Transmittable::Error.all.map(&:errorable)).to match_array([request_transmission, transmittable_job])
        end

        it 'updates the process status and creates new process state associated to the job' do
          expect(job_process_status.reload.latest_state).to eq(:failed)
          expect(job_process_status.process_states.count).to eq(2)
          expect(job_process_status.process_states.last.state_key).to eq(:failed)
          expect(request_transmission.process_status.latest_state).to eq(:failed)
          expect(request_transmission.process_status.process_states.count).to eq(2)
          expect(request_transmission.process_status.process_states.last.state_key).to eq(:failed)
        end
      end
    end
  end

  describe 'with invalid enrollment' do
    let(:params) do
      { enrollment_gid: enrollment.to_global_id.to_s, job_gid: transmittable_job.to_global_id.to_s }
    end
    let(:operation_instance) { described_class.new }
    let(:result) { operation_instance.call(params) }

    describe 'where enrollment fails the expiration guard clause' do
      let(:benefit_group) { FactoryBot.create(:benefit_group) }

      before do
        benefit_group.plan_year.update_attributes(end_on: Date.today - 1.day)
        enrollment.update_attributes(benefit_group_id: benefit_group.id)
      end

      it 'fails due to invalid state transition to coverage_expired' do
        msg = "Failed to expire enrollment hbx id #{enrollment.hbx_id} - Event 'expire_coverage' cannot transition from 'coverage_selected'."
        expect(result.success?).to be_falsey
        expect(result.failure).to include(msg)
        expect(logger).to include(msg)
      end

      it 'updates response_transmission and response_transaction' do
        result
        expect(operation_instance.response_transmission.transmittable_errors).to be_present
        expect(operation_instance.response_transmission.transmittable_errors.pluck(:key)).to include(:expire_enrollment)
        expect(operation_instance.response_transaction.transmittable_errors.pluck(:key)).to include(:expire_enrollment)
        expect(operation_instance.response_transaction.transmittable_errors.pluck(:key)).to be_present
        expect(operation_instance.response_transaction.process_status.latest_state).to eq :failed
      end
    end
  end


  describe 'with valid params' do
    let(:params) do
      { enrollment_gid: enrollment.to_global_id.to_s, job_gid: transmittable_job.to_global_id.to_s }
    end
    let(:operation_instance) { described_class.new }
    let(:result) { operation_instance.call(params) }

    before :each do
      result
    end

    it 'succeeds with message' do
      msg = "Successfully expired enrollment hbx id #{enrollment.hbx_id}"
      expect(result.success?).to be_truthy
      expect(result.value!).to eq(msg)
      expect(logger).to include(msg)
    end

    context "request and response transmission and transaction" do
      it 'creates transmission with correct association' do
        expect(operation_instance.request_transmission).to be_a(::Transmittable::Transmission)
        expect(operation_instance.request_transmission.transmission_id).to eq(enrollment.hbx_id)
        expect(operation_instance.request_transmission.job).to eq(transmittable_job)
      end

      it 'associates newly created transmission to job' do
        expect(transmittable_job.transmissions.first).to eq(operation_instance.request_transmission)
      end

      it 'creates transaction with correct associations' do
        expect(operation_instance.request_transaction).to be_a(::Transmittable::Transaction)
        expect(operation_instance.request_transaction.transaction_id).to eq(enrollment.hbx_id)
        expect(operation_instance.request_transaction.transactable).to eq(enrollment)
      end

      it 'creates join table record between transmission and transaction' do
        expect(
          ::Transmittable::TransactionsTransmissions.where(
            transaction_id: operation_instance.request_transaction.id,
            transmission_id: operation_instance.request_transmission.id
          ).count
        ).to eq(1)
      end

      it 'associates newly created transaction to enrollment' do
        expect(enrollment.transactions.first).to eq(operation_instance.request_transaction)
      end
    end

    context "response transmission and transaction" do
      it 'creates transmission with correct association' do
        expect(operation_instance.response_transmission).to be_a(::Transmittable::Transmission)
        expect(operation_instance.response_transmission.job).to eq(transmittable_job)
      end

      it 'associates newly created response transmission to job' do
        expect(transmittable_job.transmissions.count).to eq(2)
        expect(transmittable_job.transmissions.pluck(:key)).to include(:hbx_enrollment_expiration_response)
      end

      it 'creates response transaction with correct associations' do
        expect(operation_instance.response_transaction).to be_a(::Transmittable::Transaction)
        expect(operation_instance.response_transaction.transactable).to eq(enrollment)
      end

      it 'creates join table record between transmission and transaction' do
        expect(
          ::Transmittable::TransactionsTransmissions.where(
            transaction_id: operation_instance.response_transaction.id,
            transmission_id: operation_instance.response_transmission.id
          ).count
        ).to eq(1)
      end

      it 'associates both request/response transmission and transaction to enrollment' do
        request_transmission = transmittable_job.transmissions.detect { |transmission| transmission.key == :hbx_enrollment_expiration_request }
        expect(request_transmission.transmission_id).to eq(enrollment.hbx_id)
        expect(operation_instance.response_transmission.transmission_id).to eq(enrollment.hbx_id)
        expect(operation_instance.response_transaction.transaction_id).to eq(enrollment.hbx_id)
      end
    end
  end

  after :all do
    file_path = "#{Rails.root}/log/hbx_enrollments_expire_#{TimeKeeper.date_of_record.strftime('%Y_%m_%d')}.log"
    File.delete(file_path) if File.file?(file_path)
  end
end
