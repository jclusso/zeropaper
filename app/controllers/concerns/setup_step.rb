# The admin-only steps of the setup wizard after the account exists.
module SetupStep
  extend ActiveSupport::Concern

  included do
    allow_before_setup
    require_admin
    layout "authentication"
    before_action :set_setting
  end

  private
    def set_setting
      @setting = Setting.instance
    end
end
