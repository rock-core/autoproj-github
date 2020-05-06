# frozen_string_literal: true

require "test_helper"

module Autoproj
    # Main daemon module
    module OverridesGenerator
        describe Retriever do
            attr_reader :retriever

            include Autoproj::OverridesGenerator::TestHelpers

            before do
                @retriever = Retriever.new(mock_client)
                @pull_requests = {}
            end

            def add_pull_request(owner, name, number, body, state: "open")
                autoproj_add_pull_request(
                    base_owner: owner,
                    base_name: name,
                    body: body,
                    number: number,
                    state: state
                )
            end

            describe "PULL_REQUEST_URL_RX" do
                it "parses owner, name and number from PR url" do
                    owner, name, number = Retriever::PULL_REQUEST_URL_RX.match(
                        "https://github.com////g-arjones._1//demo.pkg_1//pull//122"
                    )[1..-1]

                    assert_equal "g-arjones._1", owner
                    assert_equal "demo.pkg_1", name
                    assert_equal "122", number
                end
            end

            describe "OWNER_NAME_AND_NUMBER_RX" do
                it "parses owner, name and number from PR path" do
                    owner, name, number =
                        Retriever::OWNER_NAME_AND_NUMBER_RX.match(
                            "g-arjones._1/demo.pkg_1#122"
                        )[1..-1]

                    assert_equal "g-arjones._1", owner
                    assert_equal "demo.pkg_1", name
                    assert_equal "122", number
                end
            end
            describe "NUMBER_RX" do
                it "parses the PR number from relative PR path" do
                    number =
                        Retriever::NUMBER_RX.match(
                            "#122"
                        )[1]

                    assert_equal "122", number
                end
            end
            describe "#parse_task_list" do
                it "parses the list of pending tasks" do
                    body = <<~EOFBODY
                        Depends on:

                        - [ ] one
                        - [ ] two
                        - [x] three
                        - [ ] four
                    EOFBODY

                    tasks = []
                    tasks << "one"
                    tasks << "two"
                    tasks << "four"

                    assert_equal tasks, retriever.parse_task_list(body)
                end
                it "only parses the first list" do
                    body = <<~EOFBODY
                        Depends on:
                        - [ ] one._1

                        List of something else, not dependencies:
                        - [ ] two
                    EOFBODY

                    tasks = []
                    tasks << "one._1"
                    assert_equal tasks, retriever.parse_task_list(body)
                end
                it "allows multilevel task lists" do
                    body = <<~EOFBODY
                        Depends on:
                        - 1. Feature 1:
                          - [ ] one
                          - [ ] two

                        - [ ] Feature 2:
                          - [x] three
                          - [ ] four
                    EOFBODY

                    tasks = []
                    tasks << "one"
                    tasks << "two"
                    tasks << "Feature"
                    tasks << "four"
                    assert_equal tasks, retriever.parse_task_list(body)
                end
            end
            describe "#task_to_pull_request" do
                it "returns a pull request when given a url" do
                    pr = add_pull_request("g-arjones._1", "demo.pkg_1", 22, "")
                    assert_equal pr, retriever.task_to_pull_request(
                        "https://github.com/g-arjones._1/demo.pkg_1/pull/22", pr
                    )
                end
                it "returns a pull request when given a full path" do
                    pr = add_pull_request("g-arjones._1", "demo.pkg_1", 22, "")
                    assert_equal pr, retriever.task_to_pull_request(
                        "g-arjones._1/demo.pkg_1#22", pr
                    )
                end
                it "returns a pull request when given a relative path" do
                    pr = add_pull_request("g-arjones._1", "demo.pkg_1", 22, "")
                    assert_equal pr, retriever.task_to_pull_request(
                        "#22", pr
                    )
                end
                it "returns nil when the task item does not look like a PR reference" do
                    assert_nil retriever.task_to_pull_request(
                        "Feature", nil
                    )
                end
                it "returns nil if the github resource does not exist" do
                    client = flexmock(Octokit::Client.new)
                    @retriever = Retriever.new(client)

                    client.should_receive(:pull_request)
                          .with("g-arjones/demo_pkg", 22).and_raise(Octokit::NotFound)

                    assert_nil retriever.task_to_pull_request(
                        "https://github.com/g-arjones/demo_pkg/pull/22", nil
                    )
                end
            end

            describe "#retrieve_dependencies" do
                it "recursively fetches pull request dependencies" do
                    body_driver_gps_ublox = <<~EOFBODY
                        Depends on:
                        - [ ] foreigner/drivers-orogen-gps_ublox#22
                    EOFBODY
                    pr_drivers_gps_ublox = add_pull_request(
                        "foreigner", "drivers-gps_ublox",
                        11, body_driver_gps_ublox
                    )

                    body_driver_orogen_gps_ublox = <<~EOFBODY
                        Depends on:
                        - [ ] rock-core/drivers-orogen-iodrivers_base#33
                        - [ ] foreigner/foreigner.common-package_set#44
                    EOFBODY
                    pr_driver_orogen_gps_ublox = add_pull_request(
                        "foreigner", "drivers-orogen-gps_ublox",
                        22, body_driver_orogen_gps_ublox
                    )

                    pr_driver_orogen_iodrivers_base = add_pull_request(
                        "rock-core", "drivers-orogen-iodrivers_base",
                        33, nil
                    )
                    pr_package_set = add_pull_request(
                        "foreigner", "foreigner.common-package_set",
                        44, nil
                    )

                    depends = retriever.retrieve_dependencies(
                        pr_drivers_gps_ublox.base_owner,
                        pr_drivers_gps_ublox.base_name,
                        pr_drivers_gps_ublox.number
                    )
                    assert_equal [pr_driver_orogen_gps_ublox,
                                  pr_driver_orogen_iodrivers_base,
                                  pr_package_set], depends
                end
                it "breaks cyclic dependencies" do
                    body_driver_gps_ublox = <<~EOFBODY
                        Depends on:
                        - [ ] foreigner/drivers-orogen-gps_ublox#22
                    EOFBODY
                    pr_drivers_gps_ublox = add_pull_request(
                        "foreigner", "drivers-gps_ublox",
                        11, body_driver_gps_ublox
                    )

                    body_driver_orogen_gps_ublox = <<~EOFBODY
                        Depends on:
                        - [ ] foreigner/drivers-gps_ublox#11
                    EOFBODY
                    pr_driver_orogen_gps_ublox = add_pull_request(
                        "foreigner", "drivers-orogen-gps_ublox",
                        22, body_driver_orogen_gps_ublox
                    )

                    depends = retriever.retrieve_dependencies(
                        pr_drivers_gps_ublox.base_owner,
                        pr_drivers_gps_ublox.base_name,
                        pr_drivers_gps_ublox.number
                    )
                    assert_equal [pr_driver_orogen_gps_ublox], depends
                end
                it "does not add same PR twice" do
                    body_driver_gps_ublox = <<~EOFBODY
                        Depends on:
                        - [ ] foreigner/drivers-orogen-gps_ublox#22
                        - [ ] rock-core/base-cmake#44
                    EOFBODY
                    pr_drivers_gps_ublox = add_pull_request(
                        "foreigner", "drivers-gps_ublox",
                        11, body_driver_gps_ublox
                    )

                    body_driver_orogen_gps_ublox = <<~EOFBODY
                        Depends on:
                        - [ ] rock-core/base-cmake#44
                    EOFBODY
                    pr_driver_orogen_gps_ublox = add_pull_request(
                        "foreigner", "drivers-orogen-gps_ublox",
                        22, body_driver_orogen_gps_ublox
                    )

                    pr_base_cmake = add_pull_request(
                        "rock-core", "base-cmake",
                        44, nil
                    )

                    depends = retriever.retrieve_dependencies(
                        pr_drivers_gps_ublox.base_owner,
                        pr_drivers_gps_ublox.base_name,
                        pr_drivers_gps_ublox.number
                    )
                    assert_equal [pr_driver_orogen_gps_ublox,
                                  pr_base_cmake], depends
                end
            end
        end
    end
end
