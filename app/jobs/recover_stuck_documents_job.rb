class RecoverStuckDocumentsJob < ApplicationJob
  queue_as :default

  def perform
    Document.recover_stuck
  end
end
