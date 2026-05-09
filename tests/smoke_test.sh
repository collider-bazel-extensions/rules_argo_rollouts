#!/usr/bin/env bash
# Argo Rollouts blue-green progression smoke.
#
# Strategy (the value-add of Argo Rollouts over plain Deployments
# is atomic blue-green flips and progressive canary, so the smoke
# exercises the blue-green flip end-to-end):
#
#   1. Apply tests/fixtures/rollout.yaml — a Service `bg-active`
#      + a Rollout `bg-app` with blueGreen strategy and
#      autoPromotionEnabled = true.
#   2. Wait for the Rollout to reach `status.phase = Healthy`
#      (initial RS-1 ready, active service patched to point at
#      RS-1's pods).
#   3. Read the initial stable RS hash from `status.stableRS` and
#      the active service's selector.
#   4. Patch the Rollout's image to nginx:1.26-alpine.
#   5. Wait for the new revision to be created (status.currentPodHash
#      changes), then for `status.phase = Healthy` again. With
#      autoPromotion enabled, the controller flips the active
#      service to the new RS automatically once the new RS's pods
#      are Ready.
#   6. Assert: status.stableRS != initial AND active service's
#      selector now contains the new pod-template-hash.
#
# Both checks together prove the blue-green flip happened: a new
# ReplicaSet was created, took over as stable, and the Service
# selector flipped atomically.
set -euo pipefail

CLUSTER_NAME="cluster"
env_file="$TEST_TMPDIR/${CLUSTER_NAME}.env"
[[ -f "$env_file" ]] || { echo "missing kind env file" >&2; exit 1; }
# shellcheck disable=SC1090
source "$env_file"

KCTL=("$KUBECTL" --kubeconfig="$KUBECONFIG")

NS="bg-smoke"
ROLLOUT="bg-app"
SVC="bg-active"

# Locate the fixture in runfiles.
FIXTURE=""
for cand in \
  "${RUNFILES_DIR:-}/_main/tests/fixtures/rollout.yaml" \
  "$(dirname "$0").runfiles/_main/tests/fixtures/rollout.yaml" \
  "tests/fixtures/rollout.yaml"; do
  [[ -f "$cand" ]] && { FIXTURE="$cand"; break; }
done
[[ -n "$FIXTURE" ]] || { echo "smoke_test: fixture not in runfiles" >&2; exit 1; }

echo "smoke_test: applying fixture $FIXTURE"
"${KCTL[@]}" apply --server-side -f "$FIXTURE" >/dev/null

# Wait for the initial Rollout to be Healthy. Argo Rollouts populates
# `status.phase` once the controller reconciles; "Healthy" means the
# stable RS is at desired replicas + Available.
echo "smoke_test: waiting for initial Rollout/${ROLLOUT} status.phase=Healthy"
deadline=$(( $(date +%s) + 240 ))
phase=""
while (( $(date +%s) < deadline )); do
  phase=$("${KCTL[@]}" -n "$NS" get rollout "$ROLLOUT" -o jsonpath='{.status.phase}' 2>/dev/null || true)
  [[ "$phase" == "Healthy" ]] && break
  sleep 3
done
if [[ "$phase" != "Healthy" ]]; then
  echo "smoke_test: FAIL — initial Rollout never reached Healthy (phase=${phase:-<unset>})" >&2
  "${KCTL[@]}" -n "$NS" get rollout "$ROLLOUT" -o yaml >&2 || true
  "${KCTL[@]}" -n "$NS" get pods,rs -o wide >&2 || true
  exit 1
fi

initial_stable=$("${KCTL[@]}" -n "$NS" get rollout "$ROLLOUT" -o jsonpath='{.status.stableRS}' 2>/dev/null || true)
initial_svc_hash=$("${KCTL[@]}" -n "$NS" get svc "$SVC" -o jsonpath='{.spec.selector.rollouts-pod-template-hash}' 2>/dev/null || true)
echo "smoke_test: initial stableRS=${initial_stable} active-svc-selector-hash=${initial_svc_hash}"

if [[ -z "$initial_stable" ]]; then
  echo "smoke_test: FAIL — Rollout has no status.stableRS after initial Healthy" >&2
  exit 1
fi
if [[ "$initial_stable" != "$initial_svc_hash" ]]; then
  echo "smoke_test: FAIL — active service selector hash ($initial_svc_hash) doesn't match stable RS ($initial_stable) at initial Healthy" >&2
  exit 1
fi

# Trigger a new revision by patching the image. JSON Patch addresses
# the container at /spec/template/spec/containers/0.
echo "smoke_test: patching image to nginx:1.26-alpine to trigger blue-green flip"
"${KCTL[@]}" -n "$NS" patch rollout "$ROLLOUT" --type=json \
    -p '[{"op":"replace","path":"/spec/template/spec/containers/0/image","value":"nginx:1.26-alpine"}]' >/dev/null

# Wait for the new revision: Rollout returns to Healthy AFTER the new
# RS is created, its pods become Ready, the active service flips, and
# the controller marks the new RS stable.
echo "smoke_test: waiting for blue-green flip + Rollout to return to Healthy"
deadline=$(( $(date +%s) + 240 ))
new_stable=""
while (( $(date +%s) < deadline )); do
  current_phase=$("${KCTL[@]}" -n "$NS" get rollout "$ROLLOUT" -o jsonpath='{.status.phase}' 2>/dev/null || true)
  current_stable=$("${KCTL[@]}" -n "$NS" get rollout "$ROLLOUT" -o jsonpath='{.status.stableRS}' 2>/dev/null || true)
  if [[ "$current_phase" == "Healthy" && -n "$current_stable" && "$current_stable" != "$initial_stable" ]]; then
    new_stable="$current_stable"
    break
  fi
  sleep 3
done
if [[ -z "$new_stable" ]]; then
  echo "smoke_test: FAIL — new revision never promoted (still at initial stableRS=$initial_stable)" >&2
  "${KCTL[@]}" -n "$NS" get rollout "$ROLLOUT" -o yaml >&2 || true
  "${KCTL[@]}" -n "$NS" get pods,rs -o wide >&2 || true
  echo "---- argo-rollouts controller logs ----" >&2
  "${KCTL[@]}" -n argo-rollouts logs deploy/argo-rollouts --tail=80 >&2 || true
  exit 1
fi

# The active service's selector must now point at the new RS hash.
new_svc_hash=$("${KCTL[@]}" -n "$NS" get svc "$SVC" -o jsonpath='{.spec.selector.rollouts-pod-template-hash}' 2>/dev/null || true)
if [[ "$new_svc_hash" != "$new_stable" ]]; then
  echo "smoke_test: FAIL — active service selector hash ($new_svc_hash) != new stable RS ($new_stable)" >&2
  "${KCTL[@]}" -n "$NS" get svc "$SVC" -o yaml >&2 || true
  exit 1
fi

echo "smoke_test: OK — blue-green flip succeeded"
echo "  stableRS:           $initial_stable -> $new_stable"
echo "  active svc hash:    $initial_svc_hash -> $new_svc_hash"
