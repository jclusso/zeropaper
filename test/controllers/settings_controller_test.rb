require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "settings have no email, language or raw key fields" do
    get settings_path

    assert_response :success
    assert_select "el-select[name='setting[local_ocr_provider]']"
    assert_no_match(/imap|search_language|ocr_languages|openai_api_key|mistral_api_key|setting\[ocr_provider\]/i, response.body)
    assert_select "a[href='#{new_ai_provider_path}']", text: /Add provider/
  end

  test "lists providers and assigns them to tasks" do
    openai = configure_openai
    anthropic = AIProvider.create!(kind: "anthropic", api_key: "sk-ant-test")

    get settings_path
    assert_select "li", text: /OpenAI/
    assert_select "li", text: /Anthropic/
    assert_select "el-select[name='setting[research_provider_id]']"
    assert_select "input[name='setting[research_model]'][value='gpt-5.6']"

    patch settings_path, params: { setting: { research_provider_id: anthropic.id, research_model: "claude-sonnet-4-5", review_confidence_threshold: "0.5" } }

    assert_redirected_to settings_path
    setting = Setting.instance.reload
    assert_equal anthropic, setting.research_provider
    assert_equal "claude-sonnet-4-5", setting.research_model
    assert_equal openai, setting.extraction_provider
    assert_in_delta 0.5, setting.review_confidence_threshold
  end

  test "a task with a provider but no model is refused" do
    configure_openai

    patch settings_path, params: { setting: { vision_model: "" } }

    assert_response :unprocessable_entity
    assert_select ".callout-danger", text: /OCR model is required/
  end

  test "the OCR section leads with the active engine" do
    get settings_path
    assert_select "#active_ocr", text: "Tesseract (local)"
    assert_select "#ocr p", text: /choose an OCR model under AI tasks/

    configure_openai
    get settings_path
    assert_select "#active_ocr", text: "OpenAI · gpt-5.6-luna"
    assert_select "#ocr p", text: /use the fallback engine/
  end

  test "task descriptions sit in info tips so the rows line up" do
    configure_openai

    get settings_path

    assert_select "[data-controller=info-tip] button[popovertarget=task_tip_vision][aria-label='More about #{Setting::TASKS["vision"]}']"
    assert_select "el-popover#task_tip_vision", text: AIProvidersHelper::TASK_DESCRIPTIONS["vision"]
    assert_select "[data-controller=info-tip]", count: AIProvidersHelper::TASK_DESCRIPTIONS.size
    assert_select "#ai-tasks p.hint", text: AIProvidersHelper::TASK_DESCRIPTIONS["vision"], count: 0
  end

  test "the Docling URL only shows with Docling as the fallback engine" do
    get settings_path
    assert_select "[data-controller=reveal][data-reveal-when-value=docling] [data-reveal-target=content][hidden] input[name='setting[docling_url]'][disabled]"

    Setting.instance.update!(local_ocr_provider: "docling", docling_url: "http://docling:5001")
    get settings_path
    assert_select "[data-reveal-target=content]:not([hidden]) input[name='setting[docling_url]']:not([disabled])"
  end

  test "OCR can be left to the fallback engine" do
    configure_openai

    get settings_path
    assert_select "el-select[name='setting[vision_provider_id]'] el-option[value='']", text: "None (use the fallback engine)"
    assert_select "el-select[name='setting[extraction_provider_id]'] el-option[value='']", count: 0

    patch settings_path, params: { setting: { vision_provider_id: "", vision_model: "" } }

    assert_redirected_to settings_path
    assert_nil Setting.instance.reload.vision_provider
    assert_nil Setting.instance.model_for(:vision)
  end

  test "AI choices are locked while Use AI is off" do
    configure_openai(ai_enabled: false)

    get settings_path

    assert_select "fieldset[disabled][data-gate-target=gated] el-select[name='setting[extraction_provider_id]']"
    assert_select "fieldset[disabled] input[name='setting[blank_page_ai_check]']"
    assert_select "fieldset[disabled] p[data-gate-target=hint]", text: "Turn on Use AI to choose."
    assert_select ".switch-input[name='setting[blank_page_ai_check]']"
    assert_select "label:has(input[name='setting[blank_page_ai_check]']) span[data-gate-target=hint]", text: "Turn on Use AI to choose."
    assert_select "input[name='setting[ai_enabled]'][data-gate-target=toggle]"
    assert_select "fieldset[disabled] el-select[name='setting[local_ocr_provider]']", count: 0
    assert_select "el-select[name='setting[local_ocr_provider]']"
  end

  test "posting AI fields with Use AI off keeps the saved choices" do
    openai = configure_openai(ai_enabled: false)
    anthropic = AIProvider.create!(kind: "anthropic", api_key: "sk-ant-test")

    patch settings_path, params: { setting: {
      ai_enabled: "0", extraction_provider_id: anthropic.id, extraction_model: "claude-haiku-4-5",
      blank_page_ai_check: "1", review_confidence_threshold: "0.4"
    } }

    assert_redirected_to settings_path
    setting = Setting.instance.reload
    refute setting.ai_enabled?
    assert_equal openai, setting.extraction_provider
    assert_equal "gpt-5.6-luna", setting.extraction_model
    refute setting.blank_page_ai_check?
    assert_in_delta 0.4, setting.review_confidence_threshold
  end

  test "turning Use AI on saves the AI choices in the same request" do
    configure_openai(ai_enabled: false)

    patch settings_path, params: { setting: { ai_enabled: "1", blank_page_ai_check: "1" } }

    assert_redirected_to settings_path
    setting = Setting.instance.reload
    assert setting.ai_enabled?
    assert setting.blank_page_ai_check?
  end

  test "members cannot open settings" do
    sign_in_as users(:two)

    get settings_path

    assert_response :forbidden
  end

  test "the AI creation switches save while AI is on and are kept while it is off" do
    configure_openai

    get settings_path
    assert_select "fieldset input[type=checkbox][name='setting[ai_creates_types]']"
    assert_select "fieldset input[type=checkbox][name='setting[ai_creates_tags]']"

    patch settings_path, params: { setting: { ai_enabled: "1", ai_creates_types: "0", ai_creates_tags: "0" } }
    setting = Setting.instance.reload
    refute setting.ai_creates_types?
    refute setting.ai_creates_tags?

    patch settings_path, params: { setting: { ai_enabled: "0", ai_creates_types: "1", ai_creates_tags: "1" } }
    setting.reload
    refute setting.ai_enabled?
    refute setting.ai_creates_types?, "AI-only switches are not changed while AI is off"
    refute setting.ai_creates_tags?
  end

  test "the ingest folders are greyed out while watching is off" do
    get settings_path
    assert_select "#folder fieldset:not([disabled]) code", text: Setting.instance.ingest_path

    Setting.instance.update!(ingest_enabled: false)
    get settings_path
    assert_select "#folder fieldset[disabled].opacity-50 code", text: Setting.instance.ingest_path
  end
end
