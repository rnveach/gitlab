# frozen_string_literal: true

module AppSec
  module Dast
    module Profiles
      class UpdateService < BaseContainerService
        include Gitlab::Utils::StrongMemoize

        def execute
          return unauthorized unless allowed?
          return error('Profile parameter missing') unless dast_profile

          old_params = dast_profile.attributes.symbolize_keys

          return error(dast_profile.errors.full_messages) unless dast_profile.update(dast_profile_params)

          create_audit_events(old_params)

          return success(dast_profile: dast_profile, pipeline_url: nil) unless params[:run_after_update]

          response = create_scan(dast_profile)

          return response if response.error?

          success(dast_profile: dast_profile, pipeline_url: response.payload.fetch(:pipeline_url))
        end

        private

        def allowed?
          container.licensed_feature_available?(:security_on_demand_scans) &&
            can?(current_user, :create_on_demand_dast_scan, container)
        end

        def error(message, opts = {})
          ServiceResponse.error(message: message, **opts)
        end

        def success(payload)
          ServiceResponse.success(payload: payload)
        end

        def unauthorized
          error('You are not authorized to update this profile', http_status: 403)
        end

        def dast_profile
          params[:dast_profile]
        end

        def dast_profile_params
          params.slice(:dast_site_profile_id, :dast_scanner_profile_id, :name, :description, :branch_name)
        end

        def create_scan(dast_profile)
          ::DastOnDemandScans::CreateService.new(
            container: container,
            current_user: current_user,
            params: { dast_profile: dast_profile }
          ).execute
        end

        def create_audit_events(old_params)
          dast_profile_params.each do |property, new_value|
            old_value = old_params[property]

            next if old_value == new_value

            ::Gitlab::Audit::Auditor.audit(
              name: 'dast_profile_update',
              author: current_user,
              scope: container,
              target: dast_profile,
              message: audit_message(property, new_value, old_value)
            )
          end
        end

        def audit_message(property, new_value, old_value)
          case property
          when :dast_scanner_profile_id
            new_value = DastScannerProfile.find(new_value).name
            old_value = DastScannerProfile.find(old_value).name
            property = :dast_scanner_profile
          when :dast_site_profile_id
            new_value = DastSiteProfile.find(new_value).name
            old_value = DastSiteProfile.find(old_value).name
            property = :dast_site_profile
          end

          "Changed DAST profile #{property} from #{old_value} to #{new_value}"
        end
      end
    end
  end
end
