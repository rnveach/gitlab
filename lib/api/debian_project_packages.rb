# frozen_string_literal: true

module API
  class DebianProjectPackages < Grape::API::Instance
    params do
      requires :id, type: String, desc: 'The ID of a project'
    end

    resource :projects, requirements: API::NAMESPACE_OR_PROJECT_REQUIREMENTS do
      before do
        not_found! unless ::Feature.enabled?(:debian_packages, user_project)

        authorize_read_package!
      end

      namespace ':id/-/packages/debian' do
        include DebianPackageEndpoints

        params do
          requires :file_name, type: String, desc: 'The file name'
        end

        namespace 'incoming/:file_name', requirements: FILE_NAME_REQUIREMENTS do
          # PUT {projects|groups}/:id/-/packages/debian/incoming/:file_name
          params do
            requires :file, type: ::API::Validations::Types::WorkhorseFile, desc: 'The package file to be published (generated by Multipart middleware)'
          end

          route_setting :authentication, deploy_token_allowed: true, basic_auth_personal_access_token: true, job_token_allowed: :basic_auth
          put do
            authorize_upload!(authorized_user_project)
            bad_request!('File is too large') if authorized_user_project.actual_limits.exceeded?(:debian_max_file_size, params[:file].size)

            track_package_event('push_package', :debian)

            created!
          rescue ObjectStorage::RemoteStoreError => e
            Gitlab::ErrorTracking.track_exception(e, extra: { file_name: params[:file_name], project_id: authorized_user_project.id })

            forbidden!
          end

          # PUT {projects|groups}/:id/-/packages/debian/incoming/:file_name/authorize
          route_setting :authentication, deploy_token_allowed: true, basic_auth_personal_access_token: true, job_token_allowed: :basic_auth
          post 'authorize' do
            authorize_workhorse!(
              subject: authorized_user_project,
              has_length: false,
              maximum_size: authorized_user_project.actual_limits.debian_max_file_size
            )
          end
        end
      end
    end
  end
end
