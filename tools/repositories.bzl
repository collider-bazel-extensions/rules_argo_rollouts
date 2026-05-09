"""Maintainer-only chart fetch."""

load("//tools:versions.bzl", "ARGO_ROLLOUTS_CHART_VERSIONS")

_BUILD = """\
package(default_visibility = ["//visibility:public"])

filegroup(
    name = "files",
    srcs = glob(["**/*"]),
)
"""

def _impl(rctx):
    version = rctx.attr.version
    if version not in ARGO_ROLLOUTS_CHART_VERSIONS:
        fail("rules_argo_rollouts: unknown chart version '{}'. Known: {}".format(
            version,
            sorted(ARGO_ROLLOUTS_CHART_VERSIONS.keys()),
        ))
    pin = ARGO_ROLLOUTS_CHART_VERSIONS[version]
    rctx.download_and_extract(
        url = pin["chart_url"],
        sha256 = pin["chart_sha256"],
    )
    rctx.file("WORKSPACE", "workspace(name = \"{}\")\n".format(rctx.name))
    rctx.file("BUILD.bazel", _BUILD)

argo_rollouts_chart_repository = repository_rule(
    implementation = _impl,
    attrs = {
        "version": attr.string(mandatory = True),
    },
)
