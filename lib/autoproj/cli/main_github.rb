# frozen_string_literal: true

require "autoproj"
require "autoproj/build_option"
require "autoproj/cli/update"
require "autoproj/github/retriever"
require "autoproj/exceptions"
require "octokit"
require "thor"
require "yaml"

module Autoproj
    module CLI
        # CLI interface for autoproj-github
        class MainGithub < Thor
            DEFAULT_OVERRIDES_FILE = "999-github.yml"
            VALID_URL_RX = /github.com/i.freeze
            PARSE_URL_RX = %r{(?:[:/]([A-Za-z\d\-_]+))/(.+?)(?:.git$|$)+$}m.freeze

            desc "overrides PR_URL", "Generates overrides for the given PR URL"
            option :output, type: "string",
                            desc: "output file name",
                            default: DEFAULT_OVERRIDES_FILE

            option :overwrite, type: "boolean",
                               desc: "overwrite current overrides if needed",
                               default: false

            option :update, type: "boolean",
                            desc: "update package sets if needed",
                            default: false
            def overrides(url)
                owner, name, number = validate_url(url)

                declare_configuration_options
                confirm_overwrite unless options[:overwrite]
                perform_update if options[:update]

                generate_overrides(
                    overrides_for_pull_request(owner, name, number),
                    url,
                    auto_update: options[:update]
                )

                Autoproj.message "Overrides file saved to #{generated_file}"
            end

            no_commands do # rubocop: disable Metrics/BlockLength
                def confirm_overwrite
                    return unless File.exist? generated_file

                    confirm "Overwrite #{DEFAULT_OVERRIDES_FILE}?"
                end

                def generate_overrides(overrides, url, auto_update: false)
                    if options[:output] =~ /\\|\//
                        Autoproj.error "Invalid output filename"
                        raise Interrupt
                    end

                    if requires_package_set_override?(overrides)
                        unless auto_update
                            confirm "This Pull Requst depends on a package "\
                                    "set update. Do it now?"
                        end

                        export_overrides(overrides)
                        update_package_set(url)
                    else
                        export_overrides(overrides)
                    end
                end

                def validate_url(url)
                    owner, name, number =
                        Github::Retriever.url_to_owner_name_and_number(url)
                    return [owner, name, number] if owner && name && number

                    Autoproj.error "Invalid Github Pull Request URL"
                    raise Interrupt
                end

                def update_package_set(url)
                    Process.exec(
                        Gem.ruby,
                        $PROGRAM_NAME,
                        "github",
                        "overrides",
                        "--output",
                        options[:output],
                        "--update",
                        "--overwrite",
                        url
                    )
                end

                def perform_update
                    begin
                        Update.new(ws).run(
                            [], autoproj: false,
                                packages: false,
                                config: true,
                                deps: false,
                                osdeps: false
                        )
                    rescue Autoproj::PackageNotFound
                        # We don't care about package definitions,
                        # we just want to update the package sets
                        #
                        # The user should update everythink later
                        # as part of the PR 'testing' process
                    end

                    @packages = ws.manifest.each_package_definition.to_a +
                                ws.manifest.each_remote_package_set.to_a
                end

                def export_overrides(overrides)
                    FileUtils.mkdir_p ws.overrides_dir
                    File.open(generated_file, "w") do |f|
                        f.write(overrides.to_yaml)
                    end
                end

                def package_set_by_repository_id(repository_id)
                    ws.manifest.each_remote_package_set.find do |p|
                        p.vcs.options[:repository_id] == repository_id
                    end
                end

                def branch_of(package)
                    package.autobuild.importer.branch ||
                        package.autobuild.importer.remote_branch ||
                        "master"
                end

                def requires_package_set_override?(overrides)
                    overrides.each.any? do |override|
                        id = override.keys.first
                        next false unless id.start_with? "pkg_set:"

                        repository_id = id.gsub(/^pkg_set:/, "")
                        pkg_set = package_set_by_repository_id(repository_id)

                        next false unless pkg_set
                        next true if pkg_set.autobuild.importer.commit
                        next true if pkg_set.autobuild.importer.tag

                        branch_of(pkg_set) != override[id]["branch"]
                    end
                end

                def generated_file
                    File.join(ws.overrides_dir, options[:output])
                end

                def confirm(msg, default: "yes")
                    return default unless ws.config.interactive?

                    opt = Autoproj::BuildOption.new(
                        "",
                        "boolean",
                        { doc: msg },
                        nil
                    )
                    return if opt.ask(default)

                    Autoproj.message "Aborting..."
                    raise Interrupt
                end

                def declare_configuration_options
                    doc = <<~EOFDOC.chomp
                        This plugin requires a valid Github personal access token to
                        work. If you don't have one, please, login to your Github account and
                        generate it on https://github.com/settings/tokens. Make sure you
                        enable at least the "repo" scope.

                        "Enter your Github token for authentication"
                    EOFDOC

                    ws.config.declare "github_api_key", "string", doc: doc
                    while ws.config.get("github_api_key").empty?
                        ws.config.configure "github_api_key"
                    end

                    ws.config.save
                end

                def ws
                    unless @ws
                        @ws = Autoproj::Workspace.default
                        @ws.load_config
                    end
                    @ws
                end

                def client
                    api_key = ws.config.get("github_api_key")
                    @client ||= Octokit::Client.new(access_token: api_key)
                end

                def packages
                    @packages ||= Autoproj.silent { ws_load }
                end

                def ws_load
                    begin
                        ws.setup
                        ws.load_package_sets
                        ws.setup_all_package_directories
                        ws.finalize_package_setup
                        ws.finalize_setup
                    rescue Autoproj::PackageNotFound
                        # We don't care about package definitions,
                        # we just want to update the package sets
                        #
                        # The user should update everythink later
                        # as part of the PR 'testing' process
                    end

                    ws.manifest.each_package_definition.to_a +
                        ws.manifest.each_remote_package_set.to_a
                end

                def parse_repo_url_from_pkg(pkg)
                    importer = pkg.autobuild.importer
                    return unless importer.kind_of? Autobuild::Git
                    return unless importer.repository =~ VALID_URL_RX
                    return unless (match = PARSE_URL_RX.match(importer.repository))

                    [match[1], match[2]]
                end

                def repository_of(pkg)
                    _, name = parse_repo_url_from_pkg(pkg)
                    name
                end

                def owner_of(pkg)
                    owner, = parse_repo_url_from_pkg(pkg)
                    owner
                end

                def packages_affected_by_pull_request(pull_request)
                    packages.select do |pkg|
                        repository_of(pkg) == pull_request.base_name &&
                            owner_of(pkg) == pull_request.base_owner
                    end
                end

                def retrieve_required_pull_requests(owner, name, number)
                    retriever = Github::Retriever.new(client)

                    begin
                        all_prs = retriever.retrieve_dependencies(owner, name, number)
                        all_prs << Github::PullRequest.new(
                            client, owner, name, number
                        )
                    rescue StandardError => e
                        Autoproj.error e.message
                        raise Interrupt
                    end
                end

                def overrides_for_pull_request(owner, name, number)
                    retrieve_required_pull_requests(owner, name, number).flat_map do |pr|
                        # TODO: Warn if a required pull request have no effect on the
                        #       build (i.e: does not produce an override entry).
                        #
                        #       Generally, this might indicate that a definition/override
                        #       entry is missing in a package set
                        packages_affected_by_pull_request(pr).map do |pkg|
                            key = if pkg.kind_of? Autoproj::PackageSet
                                      "pkg_set:#{pkg.vcs.options[:repository_id]}"
                                  else
                                      pkg.name
                                  end
                            {
                                key => {
                                    "github" => "#{pr.head_owner}/#{pr.head_name}",
                                    "branch" => pr.head_branch,
                                    "commit" => nil,
                                    "tag" => nil
                                }
                            }
                        end
                    end
                end
            end
        end
    end
end
