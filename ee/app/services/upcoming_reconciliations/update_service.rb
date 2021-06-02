# frozen_string_literal: true

module UpcomingReconciliations
  class UpdateService
    def initialize(upcoming_reconciliations)
      @upcoming_reconciliations = upcoming_reconciliations
    end

    def execute
      errors = []
      upcoming_reconciliations.each do |reconciliation|
        next unless reconciliation[:namespace_id]

        upsert_return = upsert_upcoming_reconciliation(reconciliation)

        errors << { reconciliation[:namespace_id] => upsert_return[:error] } unless upsert_return[:success]
      end

      errors.empty? ? ServiceResponse.success : ServiceResponse.error(message: errors.to_json)
    rescue StandardError => e
      ServiceResponse.error(message: e.message)
    end

    private

    attr_reader :upcoming_reconciliations

    def upsert_upcoming_reconciliation(reconciliation)
      existing_record = GitlabSubscriptions::UpcomingReconciliation.find_by_namespace_id(reconciliation[:namespace_id])

      if existing_record
        existing_record.update!(reconciliation)
      else
        GitlabSubscriptions::UpcomingReconciliation.new(reconciliation).save!
      end

      { success: true }
    rescue StandardError => e
      { success: false, error: e.message }
    end
  end
end
