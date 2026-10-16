# Finding the queued or running job for one document or answer looks jobs up
# by their concurrency key, so it no longer scans every job's arguments.
class IndexUnfinishedJobsByConcurrencyKey < ActiveRecord::Migration[8.1]
  def change
    add_index :solid_queue_jobs, :concurrency_key, where: "finished_at IS NULL", name: "index_solid_queue_jobs_on_unfinished_concurrency_key"
  end
end
