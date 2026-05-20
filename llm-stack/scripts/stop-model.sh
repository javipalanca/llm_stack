#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/model-lib.sh"

# ===== Stop Model =====

stop_model() {
    local model=$1
    
    if ! validate_model "$model"; then
        return 1
    fi
    
    local server=$(get_model_server "$model")
    local service=$(get_model_service "$model")
    local compose_cmd=$(get_docker_compose_cmd "$server")
    
    if ! model_is_running "$model"; then
        log_info "Model $model is not running"
        return 0
    fi
    
    log_info "Stopping model $model..."
    $compose_cmd stop "$service"
    
    log_info "Model $model stopped successfully"
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

stop_model "$1"
