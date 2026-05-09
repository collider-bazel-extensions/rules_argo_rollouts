"""Maintainer-only chart fetch — fires only when rules_argo_rollouts is the root.

Same shape rules_opa, rules_capsule, rules_crossplane (and the rest
of the family) ships. Without the `is_root` guard, both
rules_argo_rollouts (when consumed as a dep) and the consumer
would each emit a `@argo_rollouts_chart_<v>` repo with the same
name, and Bazel collides them. Tag-based dedup also prevents
duplicate emission within the root module's own extension call.
"""

load("//tools:repositories.bzl", "argo_rollouts_chart_repository")

_version_tag = tag_class(attrs = {
    "version": attr.string(mandatory = True),
})

def _impl(mctx):
    seen = {}
    for mod in mctx.modules:
        if not mod.is_root:
            continue
        for tag in mod.tags.version:
            if tag.version in seen:
                continue
            seen[tag.version] = True
            argo_rollouts_chart_repository(
                name = "argo_rollouts_chart_" + tag.version.replace(".", "_"),
                version = tag.version,
            )

argo_rollouts_chart = module_extension(
    implementation = _impl,
    tag_classes = {"version": _version_tag},
)
