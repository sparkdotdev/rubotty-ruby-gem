# frozen_string_literal: true

require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

desc "Fail if an em dash or en dash appears anywhere in the repository"
task :no_em_dashes do
  # The same style check the main repo runs, kept here so this gem holds to
  # the same bar. Enforced rather than remembered.
  #
  # The characters are built from their codepoints rather than written out,
  # so that this file does not itself trip the check it performs.
  banned = { "em dash" => 0x2014.chr(Encoding::UTF_8), "en dash" => 0x2013.chr(Encoding::UTF_8) }
  offenders = `git ls-files`.split("\n").flat_map do |file|
    next [] unless File.file?(file)

    contents = File.read(file, encoding: "UTF-8")
    banned.filter_map { |name, char| "#{file} (#{name})" if contents.include?(char) }
  end
  abort("Banned dash characters found:\n  #{offenders.join("\n  ")}") if offenders.any?
  puts "No em or en dashes."
end

task default: %i[spec no_em_dashes]
