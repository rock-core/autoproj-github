# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "autoproj/overrides_generator"
require "autoproj/test"
require "minitest/autorun"
require "minitest/spec"
require "fileutils"
require "yaml"
require "octokit"
require "open3"
require "rubygems/package"

module Autoproj
    module OverridesGenerator
        # Helpers to ease tests
        module TestHelpers
            attr_reader :ws
            attr_reader :mock_client
            attr_reader :sources

            def setup
                super
                @mock_client = flexmock(Octokit::Client.new)
            end

            def autoproj_create_ws
                @ws = ws_create
                @sources = {}

                ws
            end

            def autoproj_save_workspace
                autoproj_dir = File.join(ws.root_dir, "autoproj")
                sources.keys.each do |pkg_set|
                    pkg_set_dir = File.join(autoproj_dir, pkg_set)

                    ws_create_local_package_set(
                        pkg_set,
                        pkg_set_dir,
                        source_data: {
                            "version_control" => sources[pkg_set]
                        }
                    )

                    File.open(File.join(pkg_set_dir, "packages.autobuild"), "w") do |file|
                        sources[pkg_set].map(&:keys).flatten.each do |pkg|
                            file.write("cmake_package '#{pkg}'\n")
                        end
                    end
                end

                File.open(File.join(autoproj_dir, "manifest"), "w") do |file|
                    YAML.dump(
                        { "package_sets" => sources.keys },
                        file
                    )
                end
            end

            def autoproj_run_git(dir, *args)
                _, err, status = Open3.capture3("git", *args, chdir: dir)
                raise err unless status.success?
            end

            def autoproj_git_init(dir, dummy: true)
                dir = File.join(@ws.root_dir, dir)
                if dummy
                    FileUtils.mkdir_p dir
                    FileUtils.touch(File.join(dir, "dummy"))
                end
                autoproj_run_git(dir, "init")
                autoproj_run_git(dir, "remote", "add", "autobuild", dir)
                autoproj_run_git(dir, "add", ".")
                autoproj_run_git(dir, "commit", "-m", "Initial commit")
                autoproj_run_git(dir, "push", "-f", "autobuild", "master")
            end

            def autoproj_add_package(pkg_name, owner, repo_name, pkg_set: "pkg_set")
                autoproj_git_init(pkg_name)

                raw = {
                    "type" => "git",
                    "url" => "git@github.com/#{owner}/#{repo_name}.git"
                }

                sources[pkg_set] ||= []
                sources[pkg_set] << { pkg_name => raw }
            end

            def autoproj_add_pull_request(**options)
                pr =
                    {
                        state: options[:state],
                        number: options[:number],
                        title: options[:title],
                        updated_at: options[:updated_at] || Time.now,
                        body: options[:body],
                        base: {
                            ref: options[:base_branch],
                            sha: options[:base_sha],
                            user: {
                                login: options[:base_owner]
                            },
                            repo: {
                                name: options[:base_name]
                            }
                        },
                        head: {
                            ref: options[:head_branch],
                            sha: options[:head_sha],
                            user: {
                                login: options[:head_owner]
                            },
                            repo: {
                                name: options[:head_name]
                            }
                        }
                    }

                mock_client.should_receive(:pull_request)
                           .with(
                               "#{options[:base_owner]}/#{options[:base_name]}",
                               options[:number]
                           ).and_return(pr)

                PullRequest.new(
                    mock_client,
                    options[:base_owner],
                    options[:base_name],
                    options[:number]
                )
            end
        end
    end
end
