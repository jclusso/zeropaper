# Sets environment variables for the block and restores them afterwards. A
# nil value removes the variable.
module EnvHelpers
  private
    def with_env(values)
      previous = values.keys.to_h { |key| [ key, ENV[key] ] }
      values.each { |key, value| ENV[key] = value }
      yield
    ensure
      previous.each { |key, value| ENV[key] = value }
    end

    def with_mail_from(address = "ZeroPaper <paper@example.com>", &block)
      with_env({ "MAIL_FROM" => address }, &block)
    end
end
