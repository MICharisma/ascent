# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc
]

# Where a voter stands or lives is used once to find their places and never kept, logs included.
Rails.application.config.filter_parameters += [ /\Aaddress\z/, /\Alatitude\z/, /\Alongitude\z/ ]
