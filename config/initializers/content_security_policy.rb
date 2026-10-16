# Be sure to restart your server when you modify this file.

# Pages only load what ZeroPaper serves itself. Inline scripts and styles need
# the per-session nonce (importmap, the theme script in the head, and Turbo's
# progress bar read it from the csp-nonce meta tag). Images come only from
# this app, so OCR text or model answers cannot make the browser call out.
# 'wasm-unsafe-eval' lets PDF.js compile its WebAssembly image decoders; it
# does not allow JavaScript eval.
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.script_src :self, :wasm_unsafe_eval
    policy.style_src :self
    policy.img_src :self, :data, :blob
    policy.font_src :self
    policy.connect_src :self, *config.action_cable.url
    policy.worker_src :self, :blob
    policy.object_src :none
    policy.frame_ancestors :none
    policy.base_uri :self
    policy.form_action :self
  end

  # The nonce stays the same for a browser session, so scripts on pages Turbo
  # Drive swaps in still match the policy of the page that loaded first. It
  # is kept in the session because nothing else creates one before sign-in.
  config.content_security_policy_nonce_generator = ->(request) { request.session[:csp_nonce] ||= SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src style-src]
end
