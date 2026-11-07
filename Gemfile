# frozen_string_literal: true

source "https://rubygems.org"

# The Ruby version lives in .ruby-version alone, the same reasoning the main
# repo's Gemfile gives: a `ruby` directive here writes a RUBY VERSION stanza
# into the lock file, which then has to match the interpreter exactly.

gemspec

# The YAML engine. Declared here rather than in the gemspec because it is a
# private repository with no gem server behind it, and a gemspec runtime
# dependency can only name one that resolves. The gemspec says the same.
gem "yamlcamel-ruby", git: "https://github.com/sparkdotdev/yamlcamel-ruby.git", ref: "847e58df5d36056e6d7b0f46077d17f0a5d1ca17"

group :development, :test do
  gem "rake", "~> 13.0"
  gem "rspec", "~> 3.13"
end
