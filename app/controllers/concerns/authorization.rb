module Authorization
  extend ActiveSupport::Concern

  class_methods do
    def require_admin(**options)
      before_action :require_admin, **options
    end
  end

  private
    def require_admin
      head :forbidden unless Current.user&.admin?
    end
end
