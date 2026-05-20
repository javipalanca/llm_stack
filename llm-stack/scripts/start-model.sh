#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/model-lib.sh"

# ===== Start Model =====

start_model() {
    local model=$1
    
    if ! validate_model "$model"; then
        return 1
    fi
    
    # Conflict check
    if [ "$model" = "deepseek" ] && model_is_running "mimo"; then
        log_warn "MIMO is currently running. DeepSeek and MIMO share the same GPUs (A30:0,1)."
        log_warn "To run DeepSeek, stop MIMO first: ./stop-model.sh mimo"
        read -p "Do you want to continue anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 1
        fi
    fi
    
    if [ "$model" = "mimo" ] && model_is_running "deepseek"; then
        log_warn "DeepSeek is currently running. MIMO and DeepSeek share the same GPUs (A30:0,1)."
        log_warn "To run MIMO, stop DeepSeek first: ./stop-model.sh deepseek"
        read -p "Do you want to continue anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 1
        fi
    fi
    
    # Download if needed
    if ! model_is_downloaded "$model"; then
        log_info "Model $model not found locally. Downloading..."
        if ! "$SCRIPT_DIR/download-model.sh" "$model"; then
            log_error "Failed to download model $model"
            return 1
        fi
    fi
    
    # Get server and compose file
    local server=$(get_model_server "$model")
    local service=$(get_model_service "$model")
    local compose_cmd=$(get_docker_compose_cmd "$server")
    
    # Check if already running
    if model_is_running "$model"; then
        log_info "Model $model is already running"
        return 0
    fi
    
    # Start service
    log_info "Starting model $model on server $server..."
    
    if [ "$model" = "deepseek" ]; then
        $compose_cmd --profile deepseek up -d "$service"
    else
        $compose_cmd up -d "$service"
    fi
    
    if ! wait_for_model_health "$model"; then
        log_error "Failed to start model $model"
        $compose_cmd logs "$service" | tail -20
        return 1
    fi
    
    local port=$(get_model_port "$model")
    log_info "Model $model started successfully on port $port"
    
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

start_model "$1"
