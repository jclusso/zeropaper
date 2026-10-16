# Each processing run stamps the document; a run that is no longer the
# current one (stopped or restarted) gives up at its next step.
class AddProcessingRunToDocuments < ActiveRecord::Migration[8.1]
  def change
    add_column :documents, :processing_run, :string
  end
end
