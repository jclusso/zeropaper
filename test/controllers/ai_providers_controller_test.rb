require "test_helper"

class AIProvidersControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "the key field does not invite password managers" do
    get new_ai_provider_path

    assert_response :success
    assert_select "input[name='ai_provider[api_key]'][type=text][autocomplete=off][data-1p-ignore][data-lpignore=true]"
    assert_select "input[type=password]", count: 0
  end

  test "adds a provider" do
    assert_difference -> { AIProvider.count } do
      post ai_providers_path, params: { ai_provider: { kind: "anthropic", api_key: "sk-ant-test", name: "" } }
    end

    assert_redirected_to settings_path(anchor: "ai")
    provider = AIProvider.last
    assert_equal "Anthropic", provider.name
    assert_equal "sk-ant-test", provider.api_key
  end

  test "shows what a provider is missing" do
    assert_no_difference -> { AIProvider.count } do
      post ai_providers_path, params: { ai_provider: { kind: "ollama", api_key: "", base_url: "" } }
    end

    assert_response :unprocessable_entity
    assert_select ".callout-danger", text: /Base URL is required/
  end

  test "editing keeps the saved key when the field is left blank" do
    provider = AIProvider.create!(kind: "openai", api_key: "sk-saved")

    patch ai_provider_path(provider), params: { ai_provider: { kind: "openai", name: "Work OpenAI", api_key: "" } }

    assert_redirected_to settings_path(anchor: "ai")
    assert_equal "Work OpenAI", provider.reload.name
    assert_equal "sk-saved", provider.api_key
  end

  test "removing a provider clears the tasks that used it" do
    provider = configure_openai

    delete ai_provider_path(provider)

    assert_redirected_to settings_path(anchor: "ai")
    assert_nil Setting.instance.reload.extraction_provider
    refute AIProvider.exists?(provider.id)
  end

  test "verify reports the provider's answer" do
    provider = AIProvider.create!(kind: "openai", api_key: "sk-test")
    AIProvider.any_instance.stubs(:verify).returns(AIProvider::Check.new(false, "OpenAI rejected the API key."))

    post ai_provider_check_path(provider)

    assert_redirected_to settings_path(anchor: "ai")
    assert_equal "OpenAI rejected the API key.", flash[:alert]
  end

  test "model picker lists the provider's models for a task" do
    provider = AIProvider.create!(kind: "openai", api_key: "sk-test")

    get ai_provider_models_path(provider, task: "vision")

    assert_response :success
    assert_select "turbo-frame#model_vision input[name='setting[vision_model]'][value='gpt-6-luna']"
    assert_select "turbo-frame#model_vision el-option[value='gpt-6-luna']"
  end

  test "members cannot manage providers" do
    sign_in_as users(:two)

    get new_ai_provider_path

    assert_response :forbidden
  end
end
