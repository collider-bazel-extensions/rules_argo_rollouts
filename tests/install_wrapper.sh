#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="cluster"

if [[ -z "${RUNFILES_DIR:-}" ]]; then
  if [[ -d "${0}.runfiles" ]]; then RUNFILES_DIR="${0}.runfiles"
  elif [[ -d "$(dirname "$0").runfiles" ]]; then RUNFILES_DIR="$(dirname "$0").runfiles"
  fi
  export RUNFILES_DIR
fi
INSTALL_BIN="${RUNFILES_DIR}/_main/tests/argo_rollouts_install_bin.sh"
[[ -x "$INSTALL_BIN" ]] || { echo "wrapper: argo_rollouts_install_bin not at $INSTALL_BIN" >&2; exit 1; }

env_file="$TEST_TMPDIR/${CLUSTER_NAME}.env"
deadline=$(( $(date +%s) + 60 ))
while [[ ! -f "$env_file" ]]; do
  if (( $(date +%s) >= deadline )); then
    echo "install_wrapper: kind env file never appeared at $env_file" >&2
    exit 1
  fi
  sleep 1
done

set -a
# shellcheck disable=SC1090
source "$env_file"
set +a

on_install_fail() {
  local rc=$?
  echo "===== install_wrapper: install_bin exited $rc — dumping cluster state =====" >&2
  echo "---- pods/deploy (-n argo-rollouts) ----" >&2
  "$KUBECTL" --kubeconfig="$KUBECONFIG" -n argo-rollouts get pods,deploy -o wide >&2 || true
  echo "---- describe deploy/argo-rollouts ----" >&2
  "$KUBECTL" --kubeconfig="$KUBECONFIG" -n argo-rollouts describe deploy/argo-rollouts >&2 || true
  echo "---- argo-rollouts logs (--tail=200) ----" >&2
  "$KUBECTL" --kubeconfig="$KUBECONFIG" -n argo-rollouts logs deploy/argo-rollouts --tail=200 >&2 || true
  "$KUBECTL" --kubeconfig="$KUBECONFIG" -n argo-rollouts logs deploy/argo-rollouts --previous --tail=200 >&2 || true
  exit "$rc"
}
trap on_install_fail ERR

"$INSTALL_BIN"
