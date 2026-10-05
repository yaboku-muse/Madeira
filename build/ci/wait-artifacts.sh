#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Madeira Converter Exception: see LICENSE-EXCEPTION.md
set -euo pipefail
wait_for() {
    local run="$1" name="$2" n status conclusion
    [ -n "$run" ] || return 0
    [[ "$run" =~ ^[0-9]+$ ]] || { echo "Run IDs must be numeric" >&2; exit 1; }
    for n in $(seq 1 240); do
        if gh api "repos/$GITHUB_REPOSITORY/actions/runs/$run/artifacts" \
            --jq ".artifacts[] | select(.name == \"$name\" and .expired == false) | .id" | grep -q '[0-9]'; then
            echo "Found $name from run $run"
            return 0
        fi
        status=$(gh api "repos/$GITHUB_REPOSITORY/actions/runs/$run" --jq .status)
        [ "$status" != completed ] || { echo "Run $run completed without $name" >&2; exit 1; }
        conclusion=$(gh api "repos/$GITHUB_REPOSITORY/actions/runs/$run/jobs" \
            --jq ".jobs[] | select(.name == \"$name\" and .status == \"completed\") | .conclusion")
        case "$conclusion" in
            failure|cancelled|timed_out|skipped|action_required)
                echo "Component $name in run $run ended with $conclusion without an artifact" >&2
                exit 1 ;;
        esac
        echo "Waiting for $name from live run $run"
        sleep 30
    done
    echo "Timed out waiting for $name from run $run" >&2
    exit 1
}
wait_for "${LLVM_RUN:-}" llvm-ios
wait_for "${RUNTIME_RUN:-}" native-runtime
wait_for "${FEX_RUN:-}" fex-ios
