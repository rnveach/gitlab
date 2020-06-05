# frozen_string_literal: true

class Import::BitbucketProviderRepoEntity < Import::BaseProviderRepoEntity
  include ImportHelper

  expose :id, override: true do |repo|
    repo.full_name
  end

  expose :owner_name, override: true do |repo|
    repo.owner
  end

  expose :sanitized_name, override: true do |repo|
    repo.name.gsub(/[^\s\w.-]/, '')
  end

  expose :provider_link, override: true do |repo, options|
    repo.clone_url
  end
end
