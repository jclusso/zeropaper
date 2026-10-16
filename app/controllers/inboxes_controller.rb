class InboxesController < ApplicationController
  def show
    @documents = Document.in_inbox.includes(:correspondent, :document_type, :duplicate_of, thumbnail_attachment: :blob).recently_added.limit(200)
  end
end
