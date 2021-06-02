# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::Internal::UpcomingReconciliations do
  include ApiHelpers

  let_it_be(:user) { create(:user) }
  let_it_be(:admin) { create(:admin) }
  let_it_be(:namespace) { create(:namespace) }

  let(:upcoming_reconciliations) do
    [{
       namespace_id: namespace.id,
       next_reconciliation_date: Date.today + 5.days,
       display_alert_from: Date.today - 2.days
    }]
  end

  describe "PUT /internal/upcoming_reconciliations" do
    context "when unauthenticated" do
      it "returns authentication error" do
        put api("/internal/upcoming_reconciliations")
        expect(response).to have_gitlab_http_status(:unauthorized)
      end
    end

    context "when authenticated as user" do
      it "returns authentication error" do
        put api("/internal/upcoming_reconciliations", user)
        expect(response).to have_gitlab_http_status(:forbidden)
      end
    end

    context "when authenticated as admin" do
      subject(:put_upcoming_reconciliations) do
        put api("/internal/upcoming_reconciliations", admin), params: { upcoming_reconciliations: upcoming_reconciliations }
      end

      it "returns success" do
        put_upcoming_reconciliations

        expect(response).to have_gitlab_http_status(:ok)
      end

      context "when update service failed" do
        let(:error_message) { "update_service_error" }

        before do
          allow_next_instance_of(::UpcomingReconciliations::UpdateService) do |service|
            allow(service).to receive(:execute).and_return(ServiceResponse.error(message: error_message))
          end
        end

        it "returns error" do
          put_upcoming_reconciliations

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(json_response.dig('message', 'error')).to eq(error_message)
        end
      end
    end
  end
end
