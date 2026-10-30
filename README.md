# rules_argo_rollouts

Hermetic [Argo Rollouts](https://argoproj.github.io/argo-rollouts/)
install for Bazel test compositions. Pure glue layer over
[`rules_kubectl`](https://github.com/collider-bazel-extensions/rules_kubectl) —
`argo_rollouts_install` is a macro emitting a `kubectl_apply`
target pre-configured with the upstream helm chart's pinned manifest
and the right wait shape.

```python
load("@rules_argo_rollouts//:defs.bzl", "argo_rollouts_install", "argo_rollouts_health_check")

argo_rollouts_install(name = "argo_rollouts_install_bin")     # default ns: argo-rollouts
argo_rollouts_health_check(name = "argo_rollouts_health_bin")
```

That's the whole API. Argo Rollouts is a progressive-delivery
controller — the `Rollout` CR replaces `Deployment` and adds
blue-green, canary, traffic shifting, and metric-driven analysis.
v0.1's smoke exercises the **blue-green flip** end-to-end:
applies a Rollout + Service, waits for Healthy, patches the
image, asserts the new ReplicaSet gets promoted and the active
Service's selector flips to the new pod-template-hash.

**Pinned versions:** Argo Rollouts helm chart `2.9.3` (app
`v1.1.1`). Note: chart version ≠ app version — the chart bumps
independently. Always check `tools/versions.bzl` for the
authoritative pin pair.

> **`Rollout` replaces `Deployment`.** The Rollout CR uses the
> same Pod template shape but lives at
> `apiVersion: argoproj.io/v1alpha1, kind: Rollout` with a
> `spec.strategy` block selecting blueGreen, canary, or no
> strategy. The controller creates the underlying ReplicaSets;
> there's no Deployment in the manifest.

> **No traffic provider in v0.1.** Argo Rollouts works without
> one — the canary strategy still pauses at `setWeight` steps,
> blueGreen still flips the active service. Just no actual L7
> traffic shifting. v0.2+ candidates: compose with `rules_cilium`
> for Cilium L7 traffic management; provide examples with NGINX
> or Istio.

**Supported platforms (v0.1):** any platform where rules_kubectl
runs. Validated on Linux x86\_64 in CI.

---

## Contents

- [Installation](#installation) (Bzlmod-only)
- [Quickstart](#quickstart)
- [Macros](#macros)
- [Defining Rollouts](#defining-rollouts)
- [Hermeticity exceptions](#hermeticity-exceptions)
- [Help wanted](#help-wanted)

---

## Installation

```python
bazel_dep(name = "rules_argo_rollouts", version = "0.1.0")
```

Bzlmod-only. Transitively pulls in `rules_kubectl` ≥ 0.2.0.

---

## Quickstart

```python
load("@rules_itest//:itest.bzl", "itest_service", "service_test")
load("@rules_kind//:defs.bzl", "kind_cluster", "kind_health_check")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_argo_rollouts//:defs.bzl", "argo_rollouts_install", "argo_rollouts_health_check")

# 1. Cluster.
kind_cluster(name = "cluster", k8s_version = "1.35")
kind_health_check(name = "cluster_health", cluster = ":cluster")
itest_service(name = "kind_svc", exe = ":cluster", health_check = ":cluster_health")

# 2. Argo Rollouts.
argo_rollouts_install(name = "argo_rollouts_install_bin")
argo_rollouts_health_check(name = "argo_rollouts_health_bin")
sh_binary(name = "argo_rollouts_install_wrapper", srcs = ["install_wrapper.sh"], data = [":argo_rollouts_install_bin"])
sh_binary(name = "argo_rollouts_health_wrapper",  srcs = ["health_wrapper.sh"],  data = [":argo_rollouts_health_bin"])

itest_service(
    name = "argo_rollouts_svc",
    exe = ":argo_rollouts_install_wrapper",
    deps = [":kind_svc"],
    health_check = ":argo_rollouts_health_wrapper",
)
```

---

## Macros

### `argo_rollouts_install`

```python
argo_rollouts_install(
    name = "argo_rollouts_install_bin",
    namespace = "argo-rollouts",   # default
    wait_timeout = "300s",         # default
)
```

Expands to a `kubectl_apply(...)` target that:

- Applies `@rules_argo_rollouts//private/manifests:argo_rollouts.yaml`.
- `create_namespace = True`.
- `server_side = True`.
- `wait_for_deployments = ["argo-rollouts"]`.
- `wait_for_crds = ["rollouts.argoproj.io", "analysisruns.argoproj.io",
  "analysistemplates.argoproj.io", "clusteranalysistemplates.argoproj.io",
  "experiments.argoproj.io"]`.

### `argo_rollouts_health_check`

Drops into `itest_service.health_check`. Same wait shape with
`--timeout=0s`.

---

## Defining Rollouts

A `Rollout` looks like a `Deployment` plus a `spec.strategy`
block. Two strategies:

### Blue-green

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: bg-app
spec:
  replicas: 2
  strategy:
    blueGreen:
      activeService: bg-active                # required
      previewService: bg-preview              # optional
      autoPromotionEnabled: true              # default true
      scaleDownDelaySeconds: 30               # how long old RS lingers post-flip
  selector:
    matchLabels: { app: bg-app }
  template:
    metadata: { labels: { app: bg-app } }
    spec:
      containers:
        - name: app
          image: nginx:1.25-alpine
```

The Rollout controller creates an `app-<podHash>` ReplicaSet. On
image change, it creates a SECOND ReplicaSet for the new image,
waits for its pods Ready, then atomically flips
`spec.selector.rollouts-pod-template-hash` on the active Service
to point at the new RS. The old RS scales to 0 after
`scaleDownDelaySeconds`.

### Canary

```yaml
spec:
  strategy:
    canary:
      steps:
        - setWeight: 25
        - pause: { duration: 30s }
        - setWeight: 50
        - pause: { duration: 30s }
        - setWeight: 75
        - pause: { duration: 30s }
```

Without a traffic provider configured, `setWeight` simulates
weighted traffic by adjusting the canary RS's replica count
proportionally. With a provider (Istio, NGINX, ALB, SMI, …) it
controls actual L7 routing.

See `tests/fixtures/rollout.yaml` for the full smoke fixture.

---

## Hermeticity exceptions

| Component | Status | Notes |
|---|---|---|
| Argo Rollouts manifest | Fully hermetic. Chart .tgz + sha256 pinned in `tools/versions.bzl`; rendered + committed. | Re-render via `bash tools/render_argo_rollouts.sh <chart-version>`. |
| `kubectl` | Inherited from `rules_kubectl`. | |
| Target cluster | Out of scope. | |
| Argo Rollouts container image | Pulled at runtime. `quay.io/argoproj/argo-rollouts:v1.1.1`. | Future: pre-load via `kind_cluster.images`. |
| `nginx:1.25-alpine` / `nginx:1.26-alpine` (smoke) | Pulled at runtime. | Used as the Rollout's workload image. |

---

## Help wanted

- macOS validation
- Canary progression smoke (image patch → pause at setWeight →
  promote → assert traffic shift). Mirrors the option-2 flow
  proposed alongside this v0.1.
- `kubectl-argo-rollouts` plugin binary toolchain — would let
  smoke tests invoke `kubectl argo rollouts promote` instead of
  patching the API directly.
- Compose with `rules_cilium` for Cilium L7 traffic management
  in the canary strategy.
- Compose with `rules_mimir` (or any rules_-style Prometheus) for
  metric-driven `AnalysisRun`-gated promotions.
- Experiment smoke (`Experiment` CR — parallel preview Rollouts
  for A/B testing).
- Notifications smoke (Slack / webhook on Rollout state changes).
