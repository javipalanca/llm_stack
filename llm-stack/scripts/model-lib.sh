#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
COMPOSE_DIR="$PROJECT_DIR/compose"
CONFIG_DIR="$PROJECT_DIR/config"

# Load environment
if [ -f "$PROJECT_DIR/.env" ]; then
    set -a
    source "$PROJECT_DIR/.env"
    set +a
else
    echo "Error: .env file not found at $PROJECT_DIR/.env"
    echo "Please copy .env.example to .env and update with your values."
    exit 1
fi

# ===== Model Definitions =====
declare -A MODEL_MAP=(
    [llama33]="llama-3.3-70b-instruct-awq"
    [qwen36]="qwen3.6-35b-a3b-claude-4.7-opus-reasoning-distilled"
    [mimo]="mimo-v2.5-pro"
    [llava]="llava"
    [deepseek]="deepseek-r1-distill-qwen-32b"
)

declare -A MODEL_SERVER=(
    [llama33]="blackwell"
    [qwen36]="blackwell"
    [mimo]="a30"
    [llava]="a30"
    [deepseek]="a30"
)

declare -A MODEL_PORT=(
    [llama33]="8001"
    [qwen36]="8002"
    [mimo]="8003"
    [llava]="8004"
    [deepseek]="8005"
)

declare -A MODEL_SERVICE=(
    [llama33]="vllm-llama33"
    [qwen36]="vllm-qwen36"
    [mimo]="vllm-mimo"
    [llava]="vllm-llava"
    [deepseek]="vllm-deepseek"
)

# ===== Utility Functions =====

log_info() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $*"
}

log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

log_warn() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] WARN: $*" >&2
}

validate_model() {
    local model=$1
    if [[ ! -v MODEL_MAP[$model] ]]; then
        log_error "Unknown model: $model"
        log_error "Available models: ${!MODEL_MAP[@]}"
        return 1
    fi
    return 0
}

get_model_path() {
    local model=$1
    validate_model "$model" || return 1
    echo "$MODELS_PATH/${MODEL_MAP[$model]}"
}

get_model_server() {
    local model=$1
    validate_model "$model" || return 1
    echo "${MODEL_SERVER[$model]}"
}

get_model_port() {
    local model=$1
    validate_model "$model" || return 1
    echo "${MODEL_PORT[$model]}"
}

get_model_service() {
    local model=$1
    validate_model "$model" || return 1
    echo "${MODEL_SERVICE[$model]}"
}

get_compose_file() {
    local server=$1
    echo "$COMPOSE_DIR/docker-compose.$server.yml"
}

get_docker_compose_cmd() {
    local server=$1
    local compose_file=$(get_compose_file "$server")
    if [ ! -f "$compose_file" ]; then
        log_error "Compose file not found: $compose_file"
        return 1
    fi
    echo "docker-compose -f $compose_file"
}

model_is_running() {
    local model=$1
    local server=$(get_model_server "$model")
    local service=$(get_model_service "$model")
    
    local compose_cmd=$(get_docker_compose_cmd "$server")
    local status=$($compose_cmd ps --services --filter "status=running" 2>/dev/null | grep -w "^$service$" 2>/dev/null || echo "")
    
    [ -n "$status" ]
}

model_is_downloaded() {
    local model=$1
    local path=$(get_model_path "$model")
    [ -d "$path" ] && [ "$(ls -A "$path" 2>/dev/null)" ]
}

wait_for_model_health() {
    local model=$1
    local port=$(get_model_port "$model")
    local max_attempts=30
    local attempt=1
    
    log_info "Waiting for $model to be healthy..."
    
    while [ $attempt -le $max_attempts ]; do
        if curl -sf "http://localhost:$port/health" > /dev/null 2>&1; then
            log_info "$model is healthy"
            return 0
        fi
        
        log_info "  Attempt $attempt/$max_attempts..."
        sleep 2
        ((attempt++))
    done
    
    log_error "$model failed to become healthy after ${max_attempts}0 seconds"
    return 1
}

# ===== GPU Check Functions =====

check_gpu_available() {
    if ! command -v nvidia-smi &> /dev/null; then
        log_warn "nvidia-smi not found. GPU checks skipped."
        return 0
    fi
    
    if ! nvidia-smi &> /dev/null; then
        log_error "NVIDIA GPU not accessible. Check NVIDIA drivers and docker runtime."
        return 1
    fi
    
    return 0
}

get_gpu_memory_usage() {
    if ! command -v nvidia-smi &> /dev/null; then
        return 1
    fi
    nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader,nounits
}

# ===== Port Check Functions =====

port_is_in_use() {
    local port=$1
    lsof -i :$port > /dev/null 2>&1
}

# Export all functions for sourcing
export -f log_info log_error log_warn
export -f validate_model get_model_path get_model_server get_model_port get_model_service
export -f get_compose_file get_docker_compose_cmd
export -f model_is_running model_is_downloaded
export -f wait_for_model_health
export -f check_gpu_available get_gpu_memory_usage
export -f port_is_in_use
export MODEL_MAP MODEL_SERVER MODEL_PORT MODEL_SERVICE
export PROJECT_DIR COMPOSE_DIR CONFIG_DIR MODELS_PATH HF_CACHE HF_TOKEN
