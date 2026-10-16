class RulesController < ApplicationController
  require_admin except: :index

  before_action :set_rule, only: %i[ edit update destroy ]

  def index
    @rules = Rule.ordered.includes(:correspondent, :document_type)
  end

  # Links elsewhere (a correspondent, type or tag page) can prefill the form
  # with rule[...] params.
  def new
    @rule = params.key?(:rule) ? Rule.new(rule_params) : Rule.new
    @rule.conditions = [ { "field" => "content", "operator" => "any", "value" => "" } ] if @rule.conditions.blank?
  end

  def create
    @rule = Rule.new(rule_params)
    if @rule.save
      redirect_to rules_path, notice: [ "Rule added.", existing_documents_note ].compact.join(" ")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @rule.update(rule_params)
      redirect_to rules_path, notice: [ "Rule saved.", existing_documents_note ].compact.join(" ")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @rule.destroy
    redirect_to rules_path, notice: "Rule deleted.", status: :see_other
  end

  private
    def set_rule
      @rule = Rule.find(params[:id])
    end

    # A mark-private rule also runs over the library; says what it found.
    def existing_documents_note
      return unless @rule.privatizes_existing_documents?

      count = @rule.existing_matching_document_ids.size
      return "No existing documents match it." if count.zero?

      "#{count} existing #{"document".pluralize(count)} #{count == 1 ? "matches" : "match"} it and #{count == 1 ? "is" : "are"} being marked private."
    end

    # The form sends names, and a typed name that does not exist yet is
    # created; links that prefill the form send ids.
    def rule_params
      permitted = params.expect(rule: [ :name, :enabled, :match_mode, :correspondent_id, :document_type_id, :mark_private,
        :correspondent_name, :document_type_name, tag_ids: [], tag_names: [], conditions: [ [ :field, :operator, :value ] ] ])
      permitted[:correspondent_id] = Correspondent.where(id: permitted[:correspondent_id]).pick(:id) if permitted.key?(:correspondent_id)
      permitted[:document_type_id] = DocumentType.where(id: permitted[:document_type_id]).pick(:id) if permitted.key?(:document_type_id)
      permitted[:tag_ids] = Tag.where(id: Array(permitted[:tag_ids]).compact_blank).ids if permitted.key?(:tag_ids)
      if action_name != "new"
        permitted[:correspondent_id] = Correspondent.find_or_create_named(permitted.delete(:correspondent_name))&.id if permitted.key?(:correspondent_name)
        permitted[:document_type_id] = DocumentType.find_or_create_named(permitted.delete(:document_type_name))&.id if permitted.key?(:document_type_name)
        if permitted.key?(:tag_names)
          names = Array(permitted.delete(:tag_names)).map(&:squish).compact_blank.uniq(&:downcase)
          permitted[:tag_ids] = names.filter_map { |name| Tag.find_or_create_named(name)&.id }
        end
      end
      permitted = permitted.except(:correspondent_name, :document_type_name, :tag_names)
      if permitted.key?(:conditions)
        # Rows are posted as rule[conditions][<index>][...], so they arrive keyed by index.
        conditions = permitted[:conditions]
        conditions = conditions.values if conditions.respond_to?(:values)
        permitted[:conditions] = Array(conditions).map { |condition| condition.to_h.slice("field", "operator", "value") }
      end
      permitted
    end
end
