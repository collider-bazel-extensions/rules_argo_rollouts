#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?usage: tools/render_argo_rollouts.sh <chart-version>}"
TARGET="//tools:render_writeback_$(echo "$VERSION" | tr '.' '_')"

echo "[render_argo_rollouts] $TARGET"
exec bazel run "$TARGET"
