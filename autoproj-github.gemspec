# frozen_string_literal: true

lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "autoproj/github/version"

Gem::Specification.new do |spec|
    spec.name = "autoproj-github"
    spec.version       = Autoproj::Github::VERSION
    spec.authors       = ["Gabriel Arjones"]
    spec.email         = ["arjones@arjones.com"]

    spec.homepage      = "https://github.com/rock-core/autoproj-github"
    spec.summary       = "Set of tools to make working with Autoproj and Github easier"
    spec.license       = "BSD 3-Clause"

    # Prevent pushing this gem to RubyGems.org. To allow pushes either set the
    # 'allowed_push_host' to allow pushing to a single host or delete this section
    # to allow pushing to any host.
    spec.metadata["allowed_push_host"] = "https://rubygems.org"

    spec.metadata["homepage_uri"] = spec.homepage
    spec.metadata["source_code_uri"] = "https://github.com/rock-core/autoproj-github"

    # Specify which files should be added to the gem when it is released.
    # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
    spec.files = Dir.chdir(File.expand_path(__dir__)) do
        `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
    end
    spec.bindir        = "exe"
    spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
    spec.require_paths = ["lib"]

    spec.add_dependency "autoproj"
    spec.add_dependency "octokit"
    spec.add_development_dependency "bundler"
    spec.add_development_dependency "flexmock"
    spec.add_development_dependency "minitest", "~> 5.0"
    spec.add_development_dependency "rake"
end
