# SPDX-License-Identifier: GPL-2.0-or-later

load("//build/kernel/kleaf:workspace.bzl", "define_kleaf_workspace")

define_kleaf_workspace(common_kernel_package = "//common")

local_repository(
    name = "rules_pkg",
    path = "external/bazelbuild-rules_pkg",
)

# Optional epilog for analysis testing.
# https://bazel.build/rules/testing
load(
    "//build/kernel/kleaf:workspace_epilog.bzl",
    "define_kleaf_workspace_epilog",
)

define_kleaf_workspace_epilog()
