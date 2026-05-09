"""Public API for rules_argo_rollouts."""

load("@rules_kubectl//:defs.bzl", "kubectl_apply", "kubectl_apply_health_check")

# In v0.1's smoke render (chart 2.9.3, app v1.1.1), the chart emits
# one Deployment (`argo-rollouts` — the controller; the chart has
# the notifications-controller compiled into the same binary in
# this release) plus 5 cluster-scoped CRDs:
#   - rollouts.argoproj.io
#   - analysisruns.argoproj.io
#   - analysistemplates.argoproj.io
#   - clusteranalysistemplates.argoproj.io
#   - experiments.argoproj.io
# Plus ClusterRoles, ClusterRoleBindings, ServiceAccount, and
# ConfigMap glue. Cluster-scoped resources land regardless of the
# `-n` flag passed to kubectl_apply.
_ARGO_ROLLOUTS_DEPLOYS = [
    "argo-rollouts",
]
_ARGO_ROLLOUTS_CRDS = [
    "rollouts.argoproj.io",
    "analysisruns.argoproj.io",
    "analysistemplates.argoproj.io",
    "clusteranalysistemplates.argoproj.io",
    "experiments.argoproj.io",
]

def argo_rollouts_install(
        name,
        namespace = "argo-rollouts",
        wait_timeout = "300s",
        **kwargs):
    """Apply the pinned Argo Rollouts manifest into `namespace` and
    block until the controller Deployment is Available AND the 5
    consumer-facing CRDs are registered before idling.

    Drops into `itest_service.exe`. Wait timeout 300s — Argo Rollouts'
    image is ~120MB; cold pulls clear comfortably under 5 minutes.
    """
    extra_deploys = kwargs.pop("wait_for_deployments", [])
    extra_rollouts = kwargs.pop("wait_for_rollouts", [])
    extra_crds = kwargs.pop("wait_for_crds", [])
    kubectl_apply(
        name = name,
        manifests = ["@rules_argo_rollouts//private/manifests:argo_rollouts.yaml"],
        namespace = namespace,
        create_namespace = True,
        server_side = True,
        wait_for_deployments = list(_ARGO_ROLLOUTS_DEPLOYS) + list(extra_deploys),
        wait_for_rollouts = list(extra_rollouts),
        wait_for_crds = list(_ARGO_ROLLOUTS_CRDS) + list(extra_crds),
        wait_timeout = wait_timeout,
        **kwargs
    )

def argo_rollouts_health_check(
        name,
        namespace = "argo-rollouts",
        **kwargs):
    """Readiness probe paired with `argo_rollouts_install`."""
    extra_deploys = kwargs.pop("wait_for_deployments", [])
    extra_rollouts = kwargs.pop("wait_for_rollouts", [])
    extra_crds = kwargs.pop("wait_for_crds", [])
    kubectl_apply_health_check(
        name = name,
        namespace = namespace,
        wait_for_deployments = list(_ARGO_ROLLOUTS_DEPLOYS) + list(extra_deploys),
        wait_for_rollouts = list(extra_rollouts),
        wait_for_crds = list(_ARGO_ROLLOUTS_CRDS) + list(extra_crds),
        **kwargs
    )
