# rubocop:disable Naming/FileName
# frozen_string_literal: true

require "autoproj/github"

module Autoproj
    module CLI
        # Autoproj's main CLI class
        class Main
            desc "github", "subcommands to control github plugin"
            subcommand "github", Autoproj::CLI::MainGithub
        end
    end
end
# rubocop:enable Naming/FileName
