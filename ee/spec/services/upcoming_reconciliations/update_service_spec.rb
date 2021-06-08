# frozen_string_literal: true

require 'spec_helper'

RSpec.describe UpcomingReconciliations::UpdateService do
  let_it_be(:existing_upcoming_reconciliation) { create(:upcoming_reconciliation, :saas) }
  let_it_be(:namespace) { create(:namespace) }

  let(:record_to_create) do
    {
      namespace_id: namespace.id,
      next_reconciliation_date: Date.today + 4.days,
      display_alert_from: Date.today - 3.days
    }
  end

  let(:record_to_update) do
    {
      namespace_id: existing_upcoming_reconciliation.namespace_id,
      next_reconciliation_date: Date.today + 5.days,
      display_alert_from: Date.today - 2.days
    }
  end

  let(:record_with_non_exist_namespace_id) do
    {
      namespace_id: non_existing_record_id,
      next_reconciliation_date: Date.today + 6.days,
      display_alert_from: Date.today - 1.day
    }
  end

  describe '#execute' do
    subject(:service) { described_class.new(upcoming_reconciliations) }

    shared_examples 'returns an error for the namespace' do |check_error_message: true|
      it 'includes the error for the namespace', :aggregate_failures do
        result = service.execute

        expect(result.status).to eq(:error)

        errors = Gitlab::Json.parse(result.message)
        expect(errors.map(&:keys).map(&:first)).to include(namespace_id.to_s)

        if check_error_message
          expect(errors).to include({ namespace_id.to_s => error })
        end
      end
    end

    shared_examples "returns success" do
      it do
        result = service.execute

        expect(result.status).to eq(:success)
      end
    end

    shared_examples 'creates new upcoming reconciliation' do
      it 'increases upcoming_reconciliations count' do
        expect { service.execute }
          .to change { GitlabSubscriptions::UpcomingReconciliation.count }.by(1)
      end

      it 'created upcoming reconciliation matches given hash' do
        service.execute

        expect_equal(GitlabSubscriptions::UpcomingReconciliation.last, record_to_create)
      end
    end

    shared_examples 'updates existing upcoming reconciliation' do
      it "does not increase upcoming_reconciliations count" do
        expect { service.execute }
          .not_to change { GitlabSubscriptions::UpcomingReconciliation.count }
      end

      it "updated upcoming_reconciliation matches given hash" do
        service.execute

        expect_equal(
          GitlabSubscriptions::UpcomingReconciliation.find_by_namespace_id(record_to_update[:namespace_id]),
          record_to_update)
      end
    end

    context "when upcoming_reconciliation does not exist for given namespace" do
      let(:upcoming_reconciliations) { [record_to_create] }

      it_behaves_like 'creates new upcoming reconciliation'

      it_behaves_like 'returns success'

      context 'unsuccessfully creating the record' do
        let(:error) { "create_upcoming_reconciliation_error" }

        before do
          expect_next_instance_of(GitlabSubscriptions::UpcomingReconciliation) do |instance|
            expect(instance).to receive(:save!).and_raise(StandardError, error)
          end
        end

        it_behaves_like 'returns an error for the namespace', check_error_message: true do
          let(:namespace_id) { record_to_create[:namespace_id] }
        end
      end
    end

    context "when upcoming_reconciliation exists for given namespace" do
      let(:upcoming_reconciliations) { [record_to_update] }

      it_behaves_like 'updates existing upcoming reconciliation'

      it_behaves_like 'returns success'

      context 'unsuccessfully updating the record' do
        let(:error) { "update_upcoming_reconciliation_error" }

        before do
          existing_record = double

          expect(GitlabSubscriptions::UpcomingReconciliation)
            .to receive(:find_by_namespace_id).with(namespace_id).and_return(existing_record)
          expect(existing_record).to receive(:update!).and_raise(StandardError, error)
        end

        it_behaves_like 'returns an error for the namespace', check_error_message: true do
          let(:namespace_id) { record_to_update[:namespace_id] }
        end
      end
    end

    context 'when partial success' do
      let_it_be(:existing_upcoming_reconciliation) { create(:upcoming_reconciliation, :saas) }

      let(:upcoming_reconciliations) do
        [
          record_to_create,
          record_to_update,
          record_with_non_exist_namespace_id
        ]
      end

      it_behaves_like 'creates new upcoming reconciliation'

      it_behaves_like 'returns an error for the namespace', check_error_message: false do
        let(:namespace_id) { record_with_non_exist_namespace_id[:namespace_id] }
      end
    end

    def expect_equal(upcoming_reconciliation, hash)
      aggregate_failures do
        expect(upcoming_reconciliation.namespace_id).to eq(hash[:namespace_id])
        expect(upcoming_reconciliation.next_reconciliation_date).to eq(hash[:next_reconciliation_date])
        expect(upcoming_reconciliation.display_alert_from).to eq(hash[:display_alert_from])
      end
    end
  end
end
