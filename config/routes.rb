Rails.application.routes.draw do
  resource :setup, only: %i[ new create ]
  namespace :setup do
    resource :ai_choice, only: %i[ show update ]
    resource :models, only: %i[ show update ]
    resource :ocr, only: %i[ show update ]
  end
  resource :session, only: %i[ new create destroy ]
  namespace :sessions do
    resource :passkey_challenge, only: :create
    resource :passkey, only: :create
  end
  resources :passwords, param: :token, only: %i[ new create edit update ]

  resource :profile, only: %i[ show update ]
  resources :passkeys, only: %i[ create destroy ]
  namespace :passkeys do
    resource :challenge, only: :create
  end

  resources :documents do
    scope module: :documents do
      resource :thumbnail, only: :show
      resource :file, only: :show
      resources :pages, only: %i[ index show ]
      resource :page_removal, only: :create
      resource :original_restoration, only: :create
      resource :privacy, only: %i[ create destroy ]
      resource :reprocessing, only: :create
      resource :processing, only: :destroy
      resource :review, only: :create
      resource :duplicate_dismissal, only: :create
      resource :comparison, only: :show
    end
  end

  resource :inbox, only: :show
  resource :search, only: :show

  resources :conversations, only: %i[ index show create destroy ] do
    resources :messages, only: :create, module: :conversations
  end

  # Correspondents, document types and tags share merging: a merge page per
  # record, plus similar-name suggestions and dismissals per kind.
  { correspondents: :correspondent, document_types: :document_type, tags: :tag }.each do |kind, singular|
    scope kind.to_s, module: kind, as: singular do
      resources :similar_names, only: :index
      resources :merge_dismissals, only: :create
    end
    resources kind, except: :show do
      scope module: kind do
        resource :merge, only: %i[ new create ]
      end
    end
  end
  resources :rules, except: :show

  resource :settings, only: %i[ show update ]
  resources :ai_providers, except: %i[ index show ] do
    scope module: :ai_providers do
      resource :check, only: :create
      resources :models, only: :index
    end
  end
  resources :users, except: :show
  resources :exports, only: %i[ index create show ]
  resources :restores, only: %i[ new create show ]

  get "up" => "rails/health#show", as: :rails_health_check

  root "documents#index"
end
