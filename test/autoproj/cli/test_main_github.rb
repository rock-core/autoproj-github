# frozen_string_literal: true

require "fileutils"
require "test_helper"
require "yaml"

module Autoproj
    # Main daemon module
    module CLI
        describe MainGithub do
            attr_reader :cli

            include Autoproj::Github::TestHelpers

            before do
                autoproj_create_ws
                ws.config.set("github_api_key", "abcdefgh")
                ws.config.save
            end

            def add_pull_request(owner, name, number, body, **options)
                autoproj_add_pull_request(
                    options.merge(
                        base_owner: owner,
                        base_name: name,
                        body: body,
                        number: number
                    )
                )
            end

            def run_cli(*args)
                in_ws do
                    MainGithub.start(["overrides", *args])
                end
            end

            def generated_file
                File.join(ws.overrides_dir, "999-github.yml")
            end

            def generated_overrides
                YAML.safe_load(File.read(generated_file))
            end

            describe "does not send api requests" do
                before do
                    flexmock(Octokit::Client)
                        .should_receive(:new)
                        .never
                end

                it "interrupts if given url is invalid" do
                    assert_raises(Interrupt) do
                        run_cli("foobar")
                    end
                end

                it "aborts if user does not want to overwrite current overrides" do
                    FileUtils.touch generated_file
                    flexmock(MainGithub)
                        .new_instances
                        .should_receive(:confirm)
                        .with("Overwrite 999-github.yml?")
                        .and_raise(Interrupt)

                    assert_raises(Interrupt) do
                        run_cli("http://github.com/rock-core/base-types/pull/1")
                    end
                end
            end

            describe "calls github api" do
                before do
                    flexmock(Octokit::Client)
                        .should_receive(:new)
                        .with(access_token: "abcdefgh")
                        .and_return(mock_client).once
                end

                it "does nothing if PR has no dependencies" do
                    add_pull_request("rock-core", "base-types", 1, "")
                    run_cli("http://github.com/rock-core/base-types/pull/1")

                    assert generated_overrides.empty?
                end

                it "creates overrides dir if it doesn't exist" do
                    FileUtils.rm_rf ws.overrides_dir
                    refute File.exist? ws.overrides_dir

                    add_pull_request("rock-core", "base-types", 1, "")
                    run_cli("http://github.com/rock-core/base-types/pull/1")

                    assert generated_overrides.empty?
                end

                it "does nothing if PR dependencies does not affect a known package" do
                    body = <<~EOFBODY
                        Depends on:
                        - [ ] rock-core/base-types#1
                    EOFBODY

                    add_pull_request("rock-core", "base-orogen-types", 1, body)
                    add_pull_request("rock-core", "base-types", 1, "")
                    run_cli("http://github.com/rock-core/base-orogen-types/pull/1")

                    assert generated_overrides.empty?
                end

                it "updates configuration when requested to do so" do
                    mock = flexmock(MainGithub).new_instances
                    mock.should_receive(:perform_update).pass_thru.once.ordered
                    mock.should_receive(:generate_overrides)
                        .with(
                            [],
                            "http://github.com/rock-core/base-types/pull/1",
                            auto_update: true
                        ).pass_thru.once.ordered

                    add_pull_request("rock-core", "base-types", 1, "")
                    run_cli(
                        "--update",
                        "http://github.com/rock-core/base-types/pull/1"
                    )

                    assert generated_overrides.empty?
                end

                it "does not ask about overwriting if already requested to do so" do
                    flexmock(MainGithub)
                        .new_instances
                        .should_receive(:confirm)
                        .never

                    add_pull_request("rock-core", "base-types", 1, "")
                    FileUtils.touch generated_file

                    run_cli(
                        "--overwrite",
                        "http://github.com/rock-core/base-types/pull/1"
                    )

                    assert generated_overrides.empty?
                end

                it "generates overrides with known packages" do
                    body = <<~EOFBODY
                        Depends on:
                        - [ ] rock-core/base-types#1
                    EOFBODY

                    add_pull_request("rock-core", "base-orogen-types", 1, body,
                                     head_owner: "foreigner",
                                     head_name: "base-types",
                                     head_branch: "feature")

                    add_pull_request("rock-core", "base-types", 1, "",
                                     head_owner: "foreigner",
                                     head_name: "base-orogen-types",
                                     head_branch: "other_feature")

                    autoproj_add_package("base/types", "rock-core", "base-types")
                    autoproj_add_package(
                        "base/orogen/types",
                        "rock-core",
                        "base-orogen-types"
                    )

                    autoproj_save_workspace
                    run_cli("http://github.com/rock-core/base-orogen-types/pull/1")

                    expected_overrides = [
                        {
                            "base/types" => {
                                "github" => "foreigner/base-orogen-types",
                                "branch" => "other_feature",
                                "commit" => nil,
                                "tag" => nil
                            }
                        }, {
                            "base/orogen/types" => {
                                "github" => "foreigner/base-types",
                                "branch" => "feature",
                                "commit" => nil,
                                "tag" => nil
                            }
                        }
                    ]

                    assert_equal expected_overrides, generated_overrides
                end
            end
        end
    end
end
