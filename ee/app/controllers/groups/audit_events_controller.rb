# frozen_string_literal: true

class Groups::AuditEventsController < Groups::ApplicationController
  include AuditEvents::EnforcesValidDateParams
  include AuditEvents::AuditLogsParams
  include AuditEvents::Sortable
  include Analytics::UniqueVisitsHelper

  before_action :authorize_admin_group!
  before_action :check_audit_events_available!

  track_unique_visits :index, target_id: 'g_analytics_audit_events'

  layout 'group_settings'

  def index
    level = Gitlab::Audit::Levels::Group.new(group: group)
    # This is an interim change until we have proper API support within Audit Events
    audit_params = transform_author_entity_type(audit_logs_params)

    events = AuditLogFinder
      .new(level: level, params: audit_params)
      .execute
      .page(params[:page])
      .without_count

    @events = Gitlab::Audit::Events::Preloader.preload!(events)
    @table_events = AuditEventSerializer.new.represent(@events)
  end

  private

  def transform_author_entity_type(params)
    return params unless params[:entity_type] == 'Author'

    params[:author_id] = params[:entity_id]

    params.except(:entity_type, :entity_id)
  end
end
