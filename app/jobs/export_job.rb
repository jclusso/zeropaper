class ExportJob < ApplicationJob
  queue_as :default

  def perform(export)
    export.process!
  end
end
