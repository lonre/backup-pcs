source 'https://rubygems.org'

group :development do
  gem 'guard-rspec'
  gem 'terminal-notifier-guard' if /darwin/ =~ RUBY_PLATFORM
end

group :test, :development do
  gem 'rake'
  gem 'rspec'
end

gem 'rubysl', platforms: :rbx

# Specify your gem's dependencies in backup-pcs.gemspec
gemspec
