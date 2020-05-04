# frozen_string_literal: true

require "autoproj/overrides_generator/pull_request"

module Autoproj
    module OverridesGenerator
        # A class that retrievers overrides from a pull request
        class Retriever
            DEPENDS_ON_RX = /(?:.*depends?(?:\s+on)?\s*\:?\s*\n)(.*)/mi.freeze
            OPEN_TASK_RX = %r{(?:-\s*\[\s*\]\s*)([A-Za-z\d+_\-\:\/\#\.]+)}.freeze

            PULL_REQUEST_URL_RX = %r{https?\:\/\/(?:\w+\.)?github.com(?:\/+)
                ([A-Za-z\d+_\-\.]+)(?:\/+)([A-Za-z\d+_\-\.]+)
                (?:\/+)pull(?:\/+)(\d+)}x.freeze

            OWNER_NAME_AND_NUMBER_RX = %r{([A-Za-z\d+_\-\.]+)\/
                ([A-Za-z\d+_\-\.]+)\#(\d+)}x.freeze

            NUMBER_RX = /\#(\d+)/.freeze

            # @return [Octokit::Client]
            attr_reader :client

            # @param [Octokit::Client] client
            def initialize(client)
                @client = client
            end

            # @param [String] body
            # @return [Array<String>]
            def parse_task_list(body)
                return [] unless (m = DEPENDS_ON_RX.match(body))

                lines = m[1].each_line.map do |l|
                    l.strip!
                    l unless l.empty?
                end.compact

                valid = []
                lines.each do |l|
                    break unless l =~ /^-/

                    valid << l
                end

                valid.join("\n").scan(OPEN_TASK_RX).flatten
            end

            def pull_request(owner, name, number)
                OverridesGenerator::PullRequest.new(client, owner, name, number)
            end

            def self.url_to_owner_name_and_number(url)
                if (match = PULL_REQUEST_URL_RX.match(url))
                    owner, name, number = match[1..-1]
                end
                [owner, name, number.to_i]
            end

            # @param [String] task
            # @param [Autoproj::OverridesGenerator::PullRequest] pull_request
            # @return [Autoproj::OverridesGenerator::PullRequest, nil]
            def task_to_pull_request(task, pull_request)
                if (match = PULL_REQUEST_URL_RX.match(task))
                    owner, name, number = match[1..-1]
                elsif (match = OWNER_NAME_AND_NUMBER_RX.match(task))
                    owner, name, number = match[1..-1]
                elsif (match = NUMBER_RX.match(task))
                    owner = pull_request.base_owner
                    name = pull_request.base_name
                    number = match[1]
                else
                    return nil
                end

                number = number.to_i
                pull_request(owner, name, number)
            rescue Octokit::NotFound
                nil
            end

            # @param [Array<Autoproj::OverridesGenerator::PullRequest] visited
            # @param [Autoproj::OverridesGenerator::PullRequest] pull_request
            # @return [Boolean]
            def visited?(visited, pull_request)
                visited.any? do |pr|
                    pr.base_owner == pull_request.base_owner &&
                        pr.base_name == pull_request.base_name &&
                        pr.number == pull_request.number
                end
            end

            # @param [Autoproj::OverridesGenerator::PullRequest] pull_request
            # @return [Array<Autoproj::OverridesGenerator::PullRequest>]
            def retrieve_dependencies(owner, name, number, visited = [], deps = [])
                pull_request = pull_request(owner, name, number)
                visited << pull_request
                dependencies = parse_task_list(pull_request.body).map do |task|
                    task_to_pull_request(task, pull_request)
                end.compact

                dependencies.each do |pr|
                    next if visited?(visited, pr)

                    deps << pr
                    retrieve_dependencies(
                        pr.base_owner, pr.base_name, pr.number, visited, deps
                    )
                end
                deps
            end
        end
    end
end
