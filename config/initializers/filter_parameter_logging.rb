# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc
]

# A backup key, as the restore form sends it (`backup_key`, caught by `_key`)
# or as a bare `key`, matched exactly like `q` below.
Rails.application.config.filter_parameters += [ /\Akey\z/ ]

# What documents say, what people search and ask for, and the details rules
# match on stay out of the logs too. `q` is matched exactly, since a partial
# match would hide most parameters.
Rails.application.config.filter_parameters += [
  :title, :summary, :content, :query, :question, :filename, :files, :conditions,
  :correspondent_name, :document_type_name, :tag_names, /\Aq\z/
]
