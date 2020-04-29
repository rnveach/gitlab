# frozen_string_literal: true

require 'digest/md5'

class Key < ApplicationRecord
  include AfterCommitQueue
  include Sortable
  include Sha256Attribute
  include Expirable

  sha256_attribute :fingerprint_sha256

  belongs_to :user

  before_validation :generate_fingerprint

  validates :title,
    presence: true,
    length: { maximum: 255 }

  validates :key,
    presence: true,
    length: { maximum: 5000 },
    format: { with: /\A(ssh|ecdsa)-.*\Z/ }

  validates :fingerprint,
    uniqueness: true,
    presence: { message: 'cannot be generated' }

  validates :deploy_key_type,
    presence: true,
    if: :private_deploy_key?

  validate :key_meets_restrictions

  delegate :name, :email, to: :user, prefix: true

  after_commit :add_to_authorized_keys, on: :create
  after_create :post_create_hook
  after_create :refresh_user_cache
  after_commit :remove_from_authorized_keys, on: :destroy
  after_destroy :post_destroy_hook
  after_destroy :refresh_user_cache

  alias_attribute :fingerprint_md5, :fingerprint

  scope :preload_users, -> { preload(:user) }
  scope :for_user, -> (user) { where(user: user) }
  scope :order_last_used_at_desc, -> { reorder(::Gitlab::Database.nulls_last_order('last_used_at', 'DESC')) }

  def self.regular_keys
    where(type: ['Key', nil])
  end

  def key=(value)
    write_attribute(:key, value.present? ? Gitlab::SSHPublicKey.sanitize(value) : nil)

    @public_key = nil
  end

  def publishable_key
    # Strip out the keys comment so we don't leak email addresses
    # Replace with simple ident of user_name (hostname)
    self.key.split[0..1].push("#{self.user_name} (#{Gitlab.config.gitlab.host})").join(' ')
  end

  # projects that has this key
  def projects
    user.authorized_projects
  end

  def shell_id
    "key-#{id}"
  end

  # EE overrides this
  def can_delete?
    true
  end

  # rubocop: disable CodeReuse/ServiceClass
  def update_last_used_at
    Keys::LastUsedService.new(self).execute
  end
  # rubocop: enable CodeReuse/ServiceClass

  def add_to_authorized_keys
    return unless Gitlab::CurrentSettings.authorized_keys_enabled?

    AuthorizedKeysWorker.perform_async(:add_key, shell_id, key)
  end

  # rubocop: disable CodeReuse/ServiceClass
  def post_create_hook
    SystemHooksService.new.execute_hooks_for(self, :create)
  end
  # rubocop: enable CodeReuse/ServiceClass

  def remove_from_authorized_keys
    return unless Gitlab::CurrentSettings.authorized_keys_enabled?

    AuthorizedKeysWorker.perform_async(:remove_key, shell_id)
  end

  # rubocop: disable CodeReuse/ServiceClass
  def refresh_user_cache
    return unless user

    Users::KeysCountService.new(user).refresh_cache
  end
  # rubocop: enable CodeReuse/ServiceClass

  # rubocop: disable CodeReuse/ServiceClass
  def post_destroy_hook
    SystemHooksService.new.execute_hooks_for(self, :destroy)
  end
  # rubocop: enable CodeReuse/ServiceClass

  def public_key
    @public_key ||= Gitlab::SSHPublicKey.new(key)
  end

  private

  def generate_fingerprint
    self.fingerprint = nil
    self.fingerprint_sha256 = nil

    return unless public_key.valid?

    self.fingerprint_md5 = public_key.fingerprint
    self.fingerprint_sha256 = public_key.fingerprint("SHA256").gsub("SHA256:", "")
  end

  def key_meets_restrictions
    restriction = Gitlab::CurrentSettings.key_restriction_for(public_key.type)

    if restriction == ApplicationSetting::FORBIDDEN_KEY_VALUE
      errors.add(:key, forbidden_key_type_message)
    elsif public_key.bits < restriction
      errors.add(:key, "must be at least #{restriction} bits")
    end
  end

  def forbidden_key_type_message
    allowed_types = Gitlab::CurrentSettings.allowed_key_types.map(&:upcase)

    "type is forbidden. Must be #{Gitlab::Utils.to_exclusive_sentence(allowed_types)}"
  end

  def private_deploy_key?
    type == 'DeployKey' && !public?
  end
end

Key.prepend_if_ee('EE::Key')
