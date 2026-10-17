ActiveSupport::Inflector.inflections(:en) do |inflect|
  inflect.acronym "AI"
end

Rails.autoloaders.main.inflector.inflect("ruby_llm_logger" => "RubyLLMLogger")
