#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/model-lib.sh"

# ===== Search HuggingFace Models =====

search_huggingface_models() {
    local query=$1
    
    log_info "Searching HuggingFace for models matching '$query'..."
    log_info "(This may take a moment...)"
    echo ""

    local url="https://huggingface.co/api/models?search=${query}&limit=20"
    local raw
    raw=$(curl -fsSL "$url" 2>/dev/null || true)

    if [ -n "$raw" ] && command -v jq > /dev/null 2>&1; then
        local parsed
        parsed=$(echo "$raw" | jq -r '.[]?.id' 2>/dev/null | sed '/^$/d' | head -20 || true)
        if [ -n "$parsed" ]; then
            echo "$parsed"
            return 0
        fi
    fi
    
    # Fallback: suggestions when API or jq is unavailable.
    echo "Popular models matching '$query':"
    case "${query,,}" in
        llama*)
            echo "  meta-llama/Llama-3.3-70B-Instruct"
            echo "  meta-llama/Llama-3.1-70B-Instruct"
            echo "  casperhansen/llama-3.3-70b-instruct-awq"
            ;;
        qwen*)
            echo "  Qwen/Qwen3.6-27B"
            echo "  Qwen/Qwen2.5-72B-Instruct"
            ;;
        deepseek*)
            echo "  deepseek-ai/DeepSeek-R1-Distill-Qwen-14B"
            echo "  deepseek-ai/DeepSeek-R1"
            ;;
        mimo*)
            echo "  XiaomiMiMo/MiMo-7B-RL"
            echo "  XiaomiMiMo/MiMo-VL-7B-RL"
            ;;
        llava*)
            echo "  llava-hf/llava-v1.6-vicuna-7b-hf"
            echo "  llava-hf/llava-v1.6-34b-hf"
            ;;
        *)
            echo "  Visit: https://huggingface.co/models?search=$query"
            ;;
    esac
}

# ===== Interactive Model Selection =====

select_model_interactive() {
    echo ""
    echo "Select model to download:"
    echo ""
    
    local -a options
    local idx=1

    for m in $(list_models); do
        echo "  [$idx] $m ($(get_model_repo_id "$m"))"
        options[$idx]=$m
        ((idx++))
    done
    
    echo "  [s] Search HuggingFace for custom model"
    echo "  [q] Quit"
    echo ""
    
    read -p "Choose option (1-${#options[@]}, s, or q): " choice
    
    case "$choice" in
        s|S)
            read -p "Enter search query (llama, qwen, deepseek, etc.): " query
            search_huggingface_models "$query"
            echo ""
            read -p "Enter HuggingFace model ID (e.g., meta-llama/Llama-2-7b-hf): " model_id
            download_hf_model "$model_id"
            ;;
        q|Q)
            log_info "Cancelled"
            return 1
            ;;
        *)
            if [ -n "${options[$choice]:-}" ]; then
                download_model "${options[$choice]}"
            else
                log_error "Invalid choice"
                return 1
            fi
            ;;
    esac
}

# ===== Download Custom HuggingFace Model =====

download_hf_model() {
    local model_id=$1
    local custom_name=${2:-$(basename "$model_id")}

    ensure_hf_cli_available || return 1
    
    log_info "Downloading custom model: $model_id"
    log_info "This model will be stored as: $custom_name"
    
    local model_path="$MODELS_PATH/$custom_name"
    
    if [ -d "$model_path" ] && [ "$(ls -A "$model_path" 2>/dev/null)" ]; then
        log_warn "Model already exists at $model_path"
        read -p "Overwrite? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 0
        fi
        rm -rf "$model_path"
    fi
    
    mkdir -p "$model_path"
    
    if [ -n "${HF_TOKEN:-}" ]; then
        if ! hf_cli download --repo-type model --cache-dir "$HF_CACHE" --local-dir "$model_path" --token "$HF_TOKEN" "$model_id"; then
            log_error "Failed to download model $model_id"
            rm -rf "$model_path"
            return 1
        fi
    else
        if ! hf_cli download --repo-type model --cache-dir "$HF_CACHE" --local-dir "$model_path" "$model_id"; then
            log_error "Failed to download model $model_id"
            rm -rf "$model_path"
            return 1
        fi
    fi

    log_info "Model downloaded successfully to $model_path"
    return 0
}

# ===== Download Predefined Model =====

download_model() {
    local model=$1

    ensure_hf_cli_available || return 1

    if ! validate_model "$model"; then
        return 1
    fi

    local model_name
    local model_path
    model_name=$(get_model_repo_id "$model")
    model_path=$(get_model_path "$model")

    if model_is_downloaded "$model"; then
        log_info "Model $model already downloaded at $model_path"
        return 0
    fi

    log_info "Downloading model $model ($model_name)..."

    mkdir -p "$model_path"

    if [ -n "${HF_TOKEN:-}" ]; then
        if ! hf_cli download --repo-type model --cache-dir "$HF_CACHE" --local-dir "$model_path" --token "$HF_TOKEN" "$model_name"; then
            log_error "Failed to download model $model"
            rm -rf "$model_path"
            return 1
        fi
    else
        if ! hf_cli download --repo-type model --cache-dir "$HF_CACHE" --local-dir "$model_path" "$model_name"; then
            log_error "Failed to download model $model"
            rm -rf "$model_path"
            return 1
        fi
    fi

    log_info "Model $model downloaded successfully to $model_path"
    return 0
}

# ===== Main =====

if [ $# -eq 0 ]; then
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  <model_name>              Download predefined model (llama33, qwen36, mimo, llava, deepseek)"
    echo "  --list                    List available predefined models"
    echo "  --search <query>          Search HuggingFace for models"
    echo "  --interactive, -i         Interactive model selection"
    echo ""
    echo "Examples:"
    echo "  $0 llama33"
    echo "  $0 --search llama"
    echo "  $0 --interactive"
    exit 1
fi

case "$1" in
    --list)
        echo "Available models:"
        for m in $(list_models); do
            path=$(get_model_path "$m")
            if model_is_downloaded "$m"; then
                echo "  ✓ $m ($(get_model_repo_id "$m")) - Already downloaded"
            else
                echo "  ✗ $m ($(get_model_repo_id "$m"))"
            fi
        done
        ;;
    --search)
        if [ $# -lt 2 ]; then
            log_error "Please provide a search query"
            exit 1
        fi
        search_huggingface_models "$2"
        ;;
    --interactive|-i)
        select_model_interactive
        ;;
    --hf)
        if [ $# -lt 2 ]; then
            log_error "Please provide a HuggingFace model ID"
            exit 1
        fi
        download_hf_model "$2" "${3:-}"
        ;;
    *)
        download_model "$1"
        ;;
esac
