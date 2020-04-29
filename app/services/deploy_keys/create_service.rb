# frozen_string_literal: true

module DeployKeys
  class CreateService < Keys::BaseService
    def execute(project: nil)
      params[:deploy_key_type] = DeployKey.deploy_key_types[:project_type]

      DeployKey.create(params.merge(user: user))
    end
  end
end

DeployKeys::CreateService.prepend_if_ee('::EE::DeployKeys::CreateService')
