#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/model-lib.sh"

# ===== Restart Model =====

restart_model() {
    local model=$1
    
    if ! validate_model "$model"; then
        return 1
    fi
    
    log_info "Restarting model $model..."
    
    if ! "$SCRIPT_DIR/stop-model.sh" "$model"; then
        log_warn "Failed to stop model $model (may not have been running)"
    fi
    
    sleep 2
    
    if ! "$SCRIPT_DIR/start-model.sh" "$model"; then
        log_error "Failed to start model $model after restart"
        return 1
    fi
    
    log_info "Model $model restarted successfully"
    return 0
}

# ===== Main =====

if [ $# -eq 0 ]; then
    echo "Usage: $0 <model_name>"
    echo "Available models:"
    for m in "${!MODEL_MAP[@]}"; do
        echo "  $m (${MODEL_MAP[$m]})"
    done
    exit 1
fi

restart_model "$1"
