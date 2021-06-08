# frozen_string_literal: true

module UpcomingReconciliations
  class UpdateService
    def initialize(upcoming_reconciliations)
      @upcoming_reconciliations = upcoming_reconciliations
      @errors = []
    end

    def execute
      upcoming_reconciliations.each { |reconciliation| upsert_upcoming_reconciliation(reconciliation) }

      result
    end

    private

    attr_reader :upcoming_reconciliations, :errors

    def upsert_upcoming_reconciliation(reconciliation)
      existing_record = GitlabSubscriptions::UpcomingReconciliation.find_by_namespace_id(reconciliation[:namespace_id])

      if existing_record
        existing_record.update!(reconciliation)
      else
        GitlabSubscriptions::UpcomingReconciliation.new(reconciliation).save!
      end
    rescue StandardError => e
      errors << { reconciliation[:namespace_id] => e.message }
    end

    def result
      errors.empty? ? ServiceResponse.success : ServiceResponse.error(message: errors.to_json)
    end
  end
end
