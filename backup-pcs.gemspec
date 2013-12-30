# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'backup/pcs/version'

Gem::Specification.new do |spec|
  spec.name          = "backup-pcs"
  spec.version       = Backup::PCS::VERSION
  spec.authors       = ["Lonre Wang"]
  spec.email         = ["me@wanglong.me"]
  spec.description   = %q{Backup Storage for supporting Baidu Personal Cloud Storage(PCS)}
  spec.summary       = %q{Baidu PCS Storage for Backup}
  spec.homepage      = "https://github.com/lonre/backup-pcs"
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency     "baidu-sdk", "~> 0.0.1"
  spec.add_runtime_dependency     "backup",    "~> 3.9"
  spec.add_development_dependency "bundler",   "~> 1.3"
end
