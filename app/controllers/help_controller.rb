# frozen_string_literal: true

class HelpController < ApplicationController
  skip_before_action :authenticate_user!, unless: :public_visibility_restricted?
  feature_category :not_owned

  layout 'help'

  # Taken from Jekyll
  # https://github.com/jekyll/jekyll/blob/3.5-stable/lib/jekyll/document.rb#L13
  YAML_FRONT_MATTER_REGEXP = /\A(---\s*\n.*?\n?)^((---|\.\.\.)\s*$\n?)/m.freeze
  GITLAB_DOCS_HOST = 'https://docs.gitlab.com'.freeze

  def index
    # Remove YAML frontmatter so that it doesn't look weird
    @help_index = File.read(Rails.root.join('doc', 'README.md')).sub(YAML_FRONT_MATTER_REGEXP, '')

    # Prefix Markdown links with `help/` unless they are external links.
    # '//' not necessarily part of URL, e.g., mailto:mail@example.com
    # See https://rubular.com/r/DFHZl5w8d3bpzV
    @help_index.gsub!(%r{(?<delim>\]\()(?!\w+:)(?!/)(?<link>[^\)\(]+\))}) do
      "#{$~[:delim]}#{Gitlab.config.gitlab.relative_url_root}/help/#{$~[:link]}"
    end
  end

  def show
    @path = Rack::Utils.clean_path_info(path_params[:path])

    respond_to do |format|
      format.any(:markdown, :md, :html) do
        if redirect_to_documentation_website?
          redirect_to documentation_url
        else
          render 'errors/not_found.html.haml', layout: 'errors', status: :not_found
        end
      end

      # Allow access to specific media files in the doc folder
      format.any(:png, :gif, :jpeg, :mp4, :mp3) do
        # Note: We are purposefully NOT using `Rails.root.join` because of https://gitlab.com/gitlab-org/gitlab/-/issues/216028.
        path = File.join(Rails.root, 'doc', "#{@path}.#{params[:format]}")

        if File.exist?(path)
          send_file(path, disposition: 'inline')
        else
          head :not_found
        end
      end

      # Any other format we don't recognize, just respond 404
      format.any { head :not_found }
    end
  end

  def shortcuts
  end

  def instance_configuration
    @instance_configuration = InstanceConfiguration.new
  end

  def ui
    @user = User.new(id: 0, name: 'John Doe', username: '@johndoe')
  end

  private

  def path_params
    params.require(:path)

    params
  end

  def redirect_to_documentation_website?
    return false unless Gitlab::UrlSanitizer.valid_web?(documentation_url)

    true
  end

  def documentation_url
    @documentation_url ||= Gitlab::Utils.append_path(documentation_base_url, documentation_file_path)
  end

  def documentation_base_url
    @documentation_base_url ||= Gitlab::CurrentSettings.current_application_settings.help_page_documentation_base_url.presence || GITLAB_DOCS_HOST
  end

  def documentation_file_path
    @documentation_file_path ||= [version_segment, 'ee', "#{@path}.html"].compact.join('/')
  end

  def version_segment
    return if Gitlab.pre_release?

    version = Gitlab.version_info
    [version.major, version.minor].join('.')
  end
end
