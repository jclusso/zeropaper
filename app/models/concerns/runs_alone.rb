# Runs a record's work in one process at a time, and only until it is done.
# A second run of the same record, such as a job enqueued twice, returns at
# once. The lock is a PostgreSQL advisory lock, which goes with the
# connection, so a run whose worker died can be started again.
module RunsAlone
  extend ActiveSupport::Concern

  FINISHED = %w[ready failed].freeze

  private
    def run_alone
      self.class.with_connection do |connection|
        lock = "#{self.class.name}/#{id}"
        next unless connection.select_value(self.class.sanitize_sql_array([ "SELECT pg_try_advisory_lock(hashtextextended(?, 0))", lock ]))

        begin
          yield unless reload.status.in?(FINISHED)
        ensure
          connection.select_value(self.class.sanitize_sql_array([ "SELECT pg_advisory_unlock(hashtextextended(?, 0))", lock ]))
        end
      end
    end
end
