class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :passkeys, dependent: :destroy
  has_many :conversations, dependent: :destroy
  has_many :uploaded_documents, class_name: "Document", foreign_key: :uploaded_by_id, inverse_of: :uploaded_by, dependent: :nullify

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :name, presence: true
  validates :email_address, presence: true, uniqueness: true
  validates :password, length: { minimum: 8 }, allow_nil: true

  before_validation -> { self.webauthn_id ||= WebAuthn.generate_user_id }, on: :create
  after_update :end_other_sessions, if: :saved_change_to_password_digest?

  scope :alphabetically, -> { order(:name) }

  def self.first_run?
    none?
  end

  def last_admin?
    admin? && User.where(admin: true).count == 1
  end

  private
    # A new password signs out every other browser: all of them after an
    # admin or emailed reset, all but this one when people change their own.
    def end_other_sessions
      sessions.where.not(id: Current.session&.id).destroy_all
    end
end
