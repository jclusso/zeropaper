require "test_helper"

class SetupWizardTest < ActionDispatch::IntegrationTest
  setup do
    Session.delete_all
    Passkey.delete_all
    Conversation.delete_all
    User.delete_all
    Setting.instance.update!(setup_completed_at: nil, ai_enabled: false)
  end

  test "account, then AI with a provider, then OCR" do
    get root_path
    assert_redirected_to new_setup_path

    create_account
    assert_redirected_to setup_ai_choice_path
    follow_redirect!
    assert_select "input[name='use_ai'][value='1']"

    get root_path
    assert_redirected_to setup_ai_choice_path, "the wizard is required until it is finished"

    AIProvider.any_instance.stubs(:verify).returns(AIProvider::Check.new(true, "Connected to OpenAI."))
    patch setup_ai_choice_path, params: { use_ai: "1", ai_provider: { kind: "openai", api_key: "sk-test", name: "" } }
    assert_redirected_to setup_models_path

    setting = Setting.instance.reload
    provider = AIProvider.sole
    assert setting.ai_enabled?
    assert_equal provider, setting.provider_for(:extraction)
    assert_equal "gpt-6-luna", setting.model_for(:extraction)
    assert_equal "gpt-6.1-sol", setting.model_for(:research)

    get setup_models_path
    assert_response :success
    assert_select "input[name='setting[research_model]'][value='gpt-6.1-sol']"

    patch setup_models_path, params: { setting: { research_provider_id: provider.id, research_model: "gpt-5.6-sol" } }
    assert_redirected_to setup_ocr_path
    assert_equal "gpt-5.6-sol", setting.reload.model_for(:research)

    get setup_ocr_path
    assert_select "input[name='setting[local_ocr_provider]'][value='tesseract']"
    assert_select "input[name='setting[ocr_provider]']", count: 0
    assert_select "#active_ocr", text: setting.reload.active_ocr_label
    assert_select "[data-reveal-target=content] input[name='setting[docling_url]'][disabled]"

    patch setup_ocr_path, params: { setting: { local_ocr_provider: "tesseract" } }
    assert_redirected_to root_path
    setting.reload
    assert setting.setup_complete?
    assert_equal "tesseract", setting.local_ocr_provider

    follow_redirect!
    assert_response :success
  end

  test "a provider that fails verification stays on the AI step" do
    create_account
    AIProvider.any_instance.stubs(:verify).returns(AIProvider::Check.new(false, "OpenAI rejected the API key."))

    patch setup_ai_choice_path, params: { use_ai: "1", ai_provider: { kind: "openai", api_key: "sk-bad" } }

    assert_response :unprocessable_entity
    assert_select ".callout-danger", text: /rejected the API key/
    refute Setting.instance.reload.ai_enabled?
  end

  test "choosing to stay local skips models and goes to the fallback engine" do
    create_account

    patch setup_ai_choice_path, params: { use_ai: "0", ai_provider: { kind: "openai" } }
    assert_redirected_to setup_ocr_path
    refute Setting.instance.reload.ai_enabled?
    assert_empty AIProvider.all

    get setup_models_path
    assert_redirected_to setup_ai_choice_path

    get setup_ocr_path
    assert_select "input[name='setting[ocr_provider]']", count: 0
    assert_select "#active_ocr", text: "Tesseract (local)"
    assert_select "input[name='setting[local_ocr_provider]'][value='docling']:not([disabled])"
    assert_select "[data-reveal-target=content][hidden] input[name='setting[docling_url]']"

    patch setup_ocr_path, params: { setting: { local_ocr_provider: "docling", docling_url: "" } }
    assert_response :unprocessable_entity
    refute Setting.instance.reload.setup_complete?

    patch setup_ocr_path, params: { setting: { local_ocr_provider: "tesseract" } }
    assert_redirected_to root_path
    assert Setting.instance.reload.setup_complete?
    assert_equal "tesseract", Setting.instance.local_ocr_provider
  end

  test "Docling with its URL can be the fallback engine" do
    create_account
    patch setup_ai_choice_path, params: { use_ai: "0", ai_provider: { kind: "openai" } }

    patch setup_ocr_path, params: { setting: { local_ocr_provider: "docling", docling_url: "http://docling:5001" } }

    assert_redirected_to root_path
    setting = Setting.instance.reload
    assert_equal "docling", setting.local_ocr_provider
    assert_equal "http://docling:5001", setting.docling_url
  end

  private
    def create_account
      post setup_path, params: { user: { name: "Ada", email_address: "ada@example.com", password: "a long password", password_confirmation: "a long password" } }
    end
end
