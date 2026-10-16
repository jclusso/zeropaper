# Until the first account exists, every page leads to the setup wizard. After
# that, the admin finishes the AI and OCR steps before using the app.
module FirstRun
  extend ActiveSupport::Concern

  included do
    before_action :require_setup
  end

  class_methods do
    def allow_before_setup(**options)
      skip_before_action :require_setup, **options
    end
  end

  private
    def require_setup
      if User.first_run?
        redirect_to new_setup_path
      elsif !Setting.instance.setup_complete? && authenticated? && Current.user.admin?
        redirect_to setup_ai_choice_path
      end
    end
end
