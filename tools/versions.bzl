"""Maintainer-side: chart .tgz pin.

Argo Rollouts helm chart is published at
`github.com/argoproj/argo-helm/releases/download/argo-rollouts-<v>/argo-rollouts-<v>.tgz`.

NB: chart version != app version. Chart 2.9.3 ships Argo Rollouts
app v1.1.1. Always pin both deliberately.
"""

ARGO_ROLLOUTS_CHART_VERSIONS = {
    "2.9.3": {
        "chart_url": "https://github.com/argoproj/argo-helm/releases/download/argo-rollouts-2.9.3/argo-rollouts-2.9.3.tgz",
        "chart_sha256": "ca43984a8ec1525ecba17475f0850c6f677d65d37e446fc093f3270aacf8151f",
        "app_version": "v1.1.1",
    },
}
