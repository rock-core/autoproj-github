# rubocop:disable Naming/FileName
# frozen_string_literal: true

require "autoproj/overrides_generator"

module Autoproj
    module CLI
        # Autoproj's main CLI class
        class Main
            desc "overrides", "subcommands to control the overrides generator"
            subcommand "overrides", Autoproj::CLI::MainOverridesGenerator
        end
    end
end
# rubocop:enable Naming/FileName
