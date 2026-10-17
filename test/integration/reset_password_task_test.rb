require "test_helper"
require "rake"

class ResetPasswordTaskTest < ActionDispatch::IntegrationTest
  include EnvHelpers

  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("users:reset_password")
    @user = users(:one)
  end

  test "prints a link that opens the reset form and changes nothing by itself" do
    session = @user.sessions.create!
    @user.passkeys.create!(external_id: "abc", public_key: "key", name: "Laptop")

    out = nil
    assert_no_changes -> { @user.reload.password_digest } do
      out, = capture_io { run_task("EMAIL" => " #{@user.email_address.upcase} ", "APP_URL" => nil, "APP_HOST" => nil) }
    end
    url = URI(out.lines.last.strip)

    assert_equal "example.com", url.host
    assert Session.exists?(session.id)
    assert_equal 1, @user.passkeys.count

    get url.path
    assert_response :success
    assert_select "input[type=password][name=password]"

    put url.path.delete_suffix("/edit"), params: { password: "a much longer password", password_confirmation: "a much longer password" }
    assert_redirected_to new_session_path
    refute Session.exists?(session.id)
    assert_empty @user.passkeys.reload

    get url.path
    assert_redirected_to new_password_path
  end

  test "uses the first APP_HOST for the link" do
    out, = capture_io { run_task("EMAIL" => @user.email_address, "APP_URL" => nil, "APP_HOST" => "docs.example.com, other.example.com") }

    assert_match %r{\Ahttp://docs\.example\.com/passwords/[^/]+/edit\z}, out.lines.last.strip
  end

  test "uses APP_URL with its port before APP_HOST" do
    out, = capture_io { run_task("EMAIL" => @user.email_address, "APP_URL" => "http://nas.local:3000", "APP_HOST" => "docs.example.com") }

    assert_match %r{\Ahttp://nas\.local:3000/passwords/[^/]+/edit\z}, out.lines.last.strip
  end

  test "prints the path when the app's address is not known" do
    Rails.application.config.action_mailer.stubs(:default_url_options).returns({})

    out, = capture_io { run_task("EMAIL" => @user.email_address, "APP_URL" => nil, "APP_HOST" => nil) }

    assert_match %r{\A/passwords/[^/]+/edit\z}, out.lines[1].strip
    assert_match "Set APP_URL or APP_HOST", out
  end

  test "in production the mailer's localhost is never used for the link" do
    Rails.stubs(:env).returns(ActiveSupport::EnvironmentInquirer.new("production"))
    Rails.application.config.action_mailer.stubs(:default_url_options).returns(host: "localhost")

    out, = capture_io { run_task("EMAIL" => @user.email_address, "APP_URL" => nil, "APP_HOST" => nil) }

    assert_match %r{\A/passwords/[^/]+/edit\z}, out.lines[1].strip
  end

  test "an unknown email exits non-zero" do
    error = nil
    _, err = capture_io do
      error = assert_raises(SystemExit) { run_task("EMAIL" => "missing@example.com") }
    end

    refute error.success?
    assert_match "No user has the email address missing@example.com", err
  end

  test "a missing email exits non-zero" do
    error = nil
    _, err = capture_io do
      error = assert_raises(SystemExit) { run_task("EMAIL" => nil) }
    end

    refute error.success?
    assert_match "EMAIL=someone@example.com", err
  end

  private
    def run_task(env)
      task = Rake::Task["users:reset_password"]
      task.reenable
      with_env(env) { task.invoke }
    end
end
