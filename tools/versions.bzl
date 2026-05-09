"""Maintainer-side: chart .tgz pin.

Argo Rollouts helm chart is published at
`github.com/argoproj/argo-helm/releases/download/argo-rollouts-<v>/argo-rollouts-<v>.tgz`.

NB: chart version != app version, AND `argoproj.github.io/argo-helm/index.yaml`
is stale (still advertises chart 2.9.x as latest as of 2026-05-09 — that
chart pins the 2021-era app v1.1.1, which depends on the
`extensions/v1beta1.Ingress` API removed in Kubernetes 1.22+ and crash-
loops on modern clusters). The github.com/argoproj/argo-helm/releases
list is the authoritative source — pull chart versions from there.

Chart 2.40.9 ships Argo Rollouts app v1.9.0 (2026-03-26 release).
"""

ARGO_ROLLOUTS_CHART_VERSIONS = {
    "2.40.9": {
        "chart_url": "https://github.com/argoproj/argo-helm/releases/download/argo-rollouts-2.40.9/argo-rollouts-2.40.9.tgz",
        "chart_sha256": "9028af96514d3e7443b68c56ecf17beae279e73982ffd6ee33bfeb6c70d42f22",
        "app_version": "v1.9.0",
    },
}
