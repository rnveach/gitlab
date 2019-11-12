# frozen_string_literal: true

# == Mentionable concern
#
# Contains functionality related to objects that can mention Users, Issues, MergeRequests, Commits or Snippets by
# GFM references.
#
# Used by Issue, Note, MergeRequest, and Commit.
#
module Mentionable
  extend ActiveSupport::Concern

  class_methods do
    # Indicate which attributes of the Mentionable to search for GFM references.
    def attr_mentionable(attr, options = {})
      attr = attr.to_s
      mentionable_attrs << [attr, options]
    end
  end

  included do
    # Accessor for attributes marked mentionable.
    cattr_accessor :mentionable_attrs, instance_accessor: false do
      []
    end

    if self < Participable
      participant -> (user, ext) { all_references(user, extractor: ext) }
    end
  end

  # Returns the text used as the body of a Note when this object is referenced
  #
  # By default this will be the class name and the result of calling
  # `to_reference` on the object.
  def gfm_reference(from = nil)
    # "MergeRequest" > "merge_request" > "Merge request" > "merge request"
    friendly_name = self.class.to_s.underscore.humanize.downcase

    "#{friendly_name} #{to_reference(from)}"
  end

  # The GFM reference to this Mentionable, which shouldn't be included in its #references.
  def local_reference
    self
  end

  def all_references(current_user = nil, extractor: nil)
    # Use custom extractor if it's passed in the function parameters.
    if extractor
      extractors[current_user] = extractor
    else
      extractor = extractors[current_user] ||= Gitlab::ReferenceExtractor.new(project, current_user)

      extractor.reset_memoized_values
    end

    self.class.mentionable_attrs.each do |attr, options|
      text    = __send__(attr) # rubocop:disable GitlabSecurity/PublicSend
      options = options.merge(
        cache_key: [self, attr],
        author: author,
        skip_project_check: skip_project_check?
      ).merge(mentionable_params)

      cached_html = self.try(:updated_cached_html_for, attr.to_sym)
      options[:rendered] = cached_html if cached_html

      extractor.analyze(text, options)
    end

    extractor
  end

  def extractors
    @extractors ||= {}
  end

  def mentioned_users(current_user = nil)
    all_references(current_user).users
  end

  def store_mentions!
    return unless can_store_mentions?

    refs = all_references(self.author)

    mention = current_user_mention
    mention.mentioned_users_ids = refs.mentioned_users&.pluck(:id)
    mention.mentioned_groups_ids = refs.mentioned_users_by_groups&.pluck(:id)
    mention.mentioned_projects_ids = refs.mentioned_users_by_projects&.pluck(:id)

    if mention.has_mentions?
      mention.save!
    else
      mention.destroy!
    end
  end

  def referenced_users
    User.where(id: user_mentions.select("unnest(mentioned_users_ids)").distinct )
  end

  def referenced_projects
    Project.where(id: user_mentions.select("unnest(mentioned_projects_ids)").distinct )
  end

  def referenced_project_users
    User.joins(:project_members).where(members: { source_id: referenced_projects }).distinct
  end

  def referenced_groups
    Group.where(id: user_mentions.select("unnest(mentioned_groups_ids)").distinct )
  end

  def referenced_group_users
    User.joins(:group_members).where(members: { source_id: referenced_groups }).distinct
  end

  def directly_addressed_users(current_user = nil)
    all_references(current_user).directly_addressed_users
  end

  # Extract GFM references to other Mentionables from this Mentionable. Always excludes its #local_reference.
  def referenced_mentionables(current_user = self.author)
    return [] unless matches_cross_reference_regex?

    refs = all_references(current_user)

    # We're using this method instead of Array diffing because that requires
    # both of the object's `hash` values to be the same, which may not be the
    # case for otherwise identical Commit objects.
    extracted_mentionables(refs).reject { |ref| ref == local_reference }
  end

  # Uses regex to quickly determine if mentionables might be referenced
  # Allows heavy processing to be skipped
  def matches_cross_reference_regex?
    reference_pattern = if !project || project.default_issues_tracker?
                          ReferenceRegexes.default_pattern
                        else
                          ReferenceRegexes.external_pattern
                        end

    self.class.mentionable_attrs.any? do |attr, _|
      __send__(attr) =~ reference_pattern # rubocop:disable GitlabSecurity/PublicSend
    end
  end

  # Create a cross-reference Note for each GFM reference to another Mentionable found in the +mentionable_attrs+.
  def create_cross_references!(author = self.author, without = [])
    refs = referenced_mentionables(author)

    # We're using this method instead of Array diffing because that requires
    # both of the object's `hash` values to be the same, which may not be the
    # case for otherwise identical Commit objects.
    refs.reject! { |ref| without.include?(ref) || cross_reference_exists?(ref) }

    refs.each do |ref|
      SystemNoteService.cross_reference(ref, local_reference, author)
    end
  end

  # When a mentionable field is changed, creates cross-reference notes that
  # don't already exist
  def create_new_cross_references!(author = self.author)
    changes = detect_mentionable_changes

    return if changes.empty?

    create_cross_references!(author)
  end

  private

  def extracted_mentionables(refs)
    refs.issues + refs.merge_requests + refs.commits
  end

  # Returns a Hash of changed mentionable fields
  #
  # Preference is given to the `changes` Hash, but falls back to
  # `previous_changes` if it's empty (i.e., the changes have already been
  # persisted).
  #
  # See ActiveModel::Dirty.
  #
  # Returns a Hash.
  def detect_mentionable_changes
    source = (changes.presence || previous_changes).dup

    mentionable = self.class.mentionable_attrs.map { |attr, options| attr }

    # Only include changed fields that are mentionable
    source.select { |key, val| mentionable.include?(key) }
  end

  # Determine whether or not a cross-reference Note has already been created between this Mentionable and
  # the specified target.
  def cross_reference_exists?(target)
    SystemNoteService.cross_reference_exists?(target, local_reference)
  end

  def skip_project_check?
    false
  end

  def mentionable_params
    {}
  end

  def can_store_mentions?
    store_mentioned_users_to_db_enabled? && respond_to?(:user_mentions)
  end

  def store_mentioned_users_to_db_enabled?
    return Feature.enabled?(:store_mentioned_users_to_db, self.project&.group) if self.respond_to?(:project)
    return Feature.enabled?(:store_mentioned_users_to_db, self.group) if self.respond_to?(:group)
  end

  def current_user_mention
    user_mentions.find_or_initialize_by(note: nil)
  end
end

Mentionable.prepend_if_ee('EE::Mentionable')
