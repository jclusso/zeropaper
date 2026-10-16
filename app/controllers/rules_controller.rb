class RulesController < ApplicationController
  require_admin except: :index

  before_action :set_rule, only: %i[ edit update destroy ]

  def index
    @rules = Rule.ordered.includes(:correspondent, :document_type)
  end

  def new
    @rule = Rule.new(conditions: [ { "field" => "content", "operator" => "any", "value" => "" } ])
  end

  def create
    @rule = Rule.new(rule_params)
    if @rule.save
      redirect_to rules_path, notice: "Rule added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @rule.update(rule_params)
      redirect_to rules_path, notice: "Rule saved."
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

    def rule_params
      permitted = params.expect(rule: [ :name, :enabled, :match_mode, :correspondent_id, :document_type_id, :mark_private,
        tag_ids: [], conditions: [ [ :field, :operator, :value ] ] ])
      permitted[:tag_ids] = Array(permitted[:tag_ids]).compact_blank.map(&:to_i) if permitted.key?(:tag_ids)
      if permitted.key?(:conditions)
        # Rows are posted as rule[conditions][<index>][...], so they arrive keyed by index.
        conditions = permitted[:conditions]
        conditions = conditions.values if conditions.respond_to?(:values)
        permitted[:conditions] = Array(conditions).map { |condition| condition.to_h.slice("field", "operator", "value") }
      end
      permitted
    end
end
