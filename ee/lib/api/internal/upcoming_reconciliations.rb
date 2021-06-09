# frozen_string_literal: true

module API
  module Internal
    class UpcomingReconciliations < ::API::Base
      before { authenticated_as_admin! }

      feature_category :purchase

      namespace :internal do
        resource :upcoming_reconciliations do
          desc 'Update upcoming reconciliations'
          params do
            requires :upcoming_reconciliations, type: Array[JSON], desc: 'An array of upcoming reconciliations' do
              requires :namespace_id, type: Integer, allow_blank: false
              requires :next_reconciliation_date, type: Date
              requires :display_alert_from, type: Date
            end
          end
          put '/' do
            render_api_error!({ error: 'This API is gitlab.com only!' }, 404) unless ::Gitlab.com?

            service = ::UpcomingReconciliations::UpdateService.new(params['upcoming_reconciliations'])
            response = service.execute

            if response.success?
              status 200
            else
              render_api_error!({ error: response.errors.first }, 400)
            end
          end
        end
      end
    end
  end
end
