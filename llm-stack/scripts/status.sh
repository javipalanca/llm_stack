#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/model-lib.sh"

# ===== Status Report =====

show_status() {
    echo ""
    echo "========================================"
    echo "LLM Stack Status Report"
    echo "========================================"
    echo ""
    
    # Services Status
    echo "─── SERVICES ───"
    for server in blackwell a30; do
        compose_file=$(get_compose_file "$server")
        if [ ! -f "$compose_file" ]; then
            log_warn "Compose file not found: $compose_file"
            continue
        fi
        
        compose_cmd=$(get_docker_compose_cmd "$server")
        echo ""
        echo "Server: $server"
        echo "---"
        
        local services=$($compose_cmd config --services 2>/dev/null || echo "")
        
        for service in $services; do
            if $compose_cmd ps --services --filter "status=running" 2>/dev/null | grep -q "^$service$"; then
                status="✓ RUNNING"
            else
                status="✗ STOPPED"
            fi
            echo "  $service: $status"
        done
    done
    
    echo ""
    echo "─── MODELS ───"
    for model in "${!MODEL_MAP[@]}"; do
        if model_is_running "$model"; then
            port=$(get_model_port "$model")
            status="✓ RUNNING (port $port)"
        else
            status="✗ STOPPED"
        fi
        
        if model_is_downloaded "$model"; then
            dl_status="✓ DOWNLOADED"
        else
            dl_status="✗ NOT DOWNLOADED"
        fi
        
        echo "$model: $status | $dl_status"
    done
    
    # GPU Usage
    echo ""
    echo "─── GPU USAGE ───"
    if check_gpu_available; then
        nvidia-smi --query-gpu=index,name,memory.used,memory.total,utilization.gpu \
                   --format=csv,noheader,nounits | \
        while IFS=',' read -r gpu_idx gpu_name mem_used mem_total gpu_util; do
            mem_percent=$((mem_used * 100 / mem_total))
            echo "GPU $gpu_idx ($gpu_name): ${gpu_util}% util, $mem_used/${mem_total} MB ($mem_percent%)"
        done
    else
        log_warn "GPU monitoring not available"
    fi
    
    # LiteLLM Proxy Health
    echo ""
    echo "─── LITELLM ROUTER ───"
    if curl -sf "http://localhost:4000/health" > /dev/null 2>&1; then
        echo "✓ LiteLLM Router: RUNNING on port 4000"
    else
        echo "✗ LiteLLM Router: NOT RUNNING or UNREACHABLE"
    fi
    
    # Model Port Status
    echo ""
    echo "─── MODEL ENDPOINTS ───"
    for model in "${!MODEL_PORT[@]}"; do
        port=${MODEL_PORT[$model]}
        if curl -sf "http://localhost:$port/health" > /dev/null 2>&1; then
            echo "✓ $model: http://localhost:$port (port $port)"
        else
            if model_is_running "$model"; then
                echo "⏳ $model: Warming up... (port $port)"
            else
                echo "✗ $model: STOPPED (port $port)"
            fi
        fi
    done
    
    echo ""
    echo "========================================"
    echo ""
}

# ===== Main =====

show_status
