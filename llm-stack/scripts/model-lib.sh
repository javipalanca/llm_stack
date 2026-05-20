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

list_models() {
    cat <<'EOF'
llama33
qwen36
mimo25bw
mimo
llava
deepseek
EOF
}

get_model_repo_id() {
    local model=$1
    case "$model" in
        llama33) echo "casperhansen/llama-3.3-70b-instruct-awq" ;;
        qwen36) echo "Qwen/Qwen3.6-27B" ;;
        mimo25bw) echo "XiaomiMiMo/MiMo-V2.5" ;;
        mimo) echo "XiaomiMiMo/MiMo-7B-RL" ;;
        llava) echo "llava-hf/llava-v1.6-vicuna-7b-hf" ;;
        deepseek) echo "deepseek-ai/DeepSeek-R1-Distill-Qwen-14B" ;;
        *) return 1 ;;
    esac
}

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
    if ! get_model_repo_id "$model" > /dev/null 2>&1; then
        log_error "Unknown model: $model"
        log_error "Available models: $(list_models | tr '\n' ' ')"
        return 1
    fi
    return 0
}

# Returns the local directory name (basename of repo, without org prefix)
get_model_local_name() {
    local model=$1
    validate_model "$model" || return 1
    case "$model" in
        llama33) echo "llama-3.3-70b-instruct-awq" ;;
        qwen36) echo "Qwen3.6-27B" ;;
        mimo25bw) echo "MiMo-V2.5" ;;
        mimo) echo "MiMo-7B-RL" ;;
        llava) echo "llava-v1.6-vicuna-7b-hf" ;;
        deepseek) echo "DeepSeek-R1-Distill-Qwen-14B" ;;
        *) return 1 ;;
    esac
}

get_model_path() {
    local model=$1
    local local_name
    validate_model "$model" || return 1
    local_name=$(get_model_local_name "$model")
    echo "$MODELS_PATH/$local_name"
}

get_model_server() {
    local model=$1
    validate_model "$model" || return 1
    case "$model" in
        llama33|qwen36|mimo25bw) echo "blackwell" ;;
        mimo|llava|deepseek) echo "a30" ;;
        *) return 1 ;;
    esac
}

get_model_port() {
    local model=$1
    validate_model "$model" || return 1
    case "$model" in
        llama33) echo "8001" ;;
        qwen36) echo "8002" ;;
        mimo25bw) echo "8006" ;;
        mimo) echo "8003" ;;
        llava) echo "8004" ;;
        deepseek) echo "8005" ;;
        *) return 1 ;;
    esac
}

get_model_service() {
    local model=$1
    validate_model "$model" || return 1
    case "$model" in
        llama33) echo "vllm-llama33" ;;
        qwen36) echo "vllm-qwen36" ;;
        mimo25bw) echo "vllm-mimo25bw" ;;
        mimo) echo "vllm-mimo" ;;
        llava) echo "vllm-llava" ;;
        deepseek) echo "vllm-deepseek" ;;
        *) return 1 ;;
    esac
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

# ===== Hugging Face CLI Helpers =====

hf_cli() {
    if command -v hf > /dev/null 2>&1; then
        hf "$@"
        return
    fi

    if command -v uvx > /dev/null 2>&1; then
        # Run hf without system-wide installation.
        uvx --from huggingface-hub hf "$@"
        return
    fi

    log_error "hf (huggingface-hub CLI) not found. Install locally with uv or pip."
    log_error "Recommended (no system install): uvx --from huggingface-hub hf --help"
    return 1
}

ensure_hf_cli_available() {
    if command -v hf > /dev/null 2>&1; then
        return 0
    fi
    if command -v uvx > /dev/null 2>&1; then
        return 0
    fi

    log_error "Neither hf nor uvx is available in PATH."
    log_error "Install uv: https://docs.astral.sh/uv/getting-started/installation/"
    return 1
}

# Export all functions for sourcing
export -f log_info log_error log_warn
export -f list_models get_model_repo_id get_model_local_name
export -f validate_model get_model_path get_model_server get_model_port get_model_service
export -f get_compose_file get_docker_compose_cmd
export -f model_is_running model_is_downloaded
export -f wait_for_model_health
export -f check_gpu_available get_gpu_memory_usage
export -f port_is_in_use
export -f hf_cli ensure_hf_cli_available
export PROJECT_DIR COMPOSE_DIR CONFIG_DIR MODELS_PATH HF_CACHE HF_TOKEN
