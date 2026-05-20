#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/model-lib.sh"

# ===== Test Model =====

test_model() {
    local model=$1
    local prompt="${2:-What is an LLM? Please provide a brief explanation.}"
    
    if ! validate_model "$model"; then
        return 1
    fi
    
    local port=$(get_model_port "$model")
    local endpoint="http://localhost:$port/v1/completions"
    
    if ! curl -sf "http://localhost:$port/health" > /dev/null 2>&1; then
        log_error "Model $model is not running or unreachable on port $port"
        return 1
    fi
    
    log_info "Testing model $model at $endpoint"
    log_info "Prompt: $prompt"
    echo ""
    
    local start_time=$(date +%s%N)
    
    local response=$(curl -s -X POST "$endpoint" \
        -H "Content-Type: application/json" \
        -d @- <<EOF
{
    "model": "$model",
    "prompt": "$prompt",
    "max_tokens": 100,
    "temperature": 0.7,
    "top_p": 0.9
}
EOF
)
    
    local end_time=$(date +%s%N)
    local elapsed_ms=$(((end_time - start_time) / 1000000))
    
    if echo "$response" | jq . > /dev/null 2>&1; then
        local completion=$(echo "$response" | jq -r '.choices[0].text')
        local usage=$(echo "$response" | jq '.usage')
        
        log_info "Response received in ${elapsed_ms}ms"
        echo ""
        echo "Response:"
        echo "---"
        echo "$completion"
        echo "---"
        echo ""
        echo "Usage:"
        echo "$usage" | jq .
        return 0
    else
        log_error "Invalid response from model"
        echo "$response"
        return 1
    fi
}

# ===== Test All Models =====

test_all_models() {
    local failed=()
    local passed=()
    
    echo "Testing all models..."
    echo ""
    
    for model in $(list_models); do
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        if test_model "$model"; then
            passed+=("$model")
        else
            failed+=("$model")
        fi
        sleep 2
    done
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Test Summary:"
    echo "Passed: ${#passed[@]} - ${passed[@]}"
    echo "Failed: ${#failed[@]} - ${failed[@]}"
    
    [ ${#failed[@]} -eq 0 ]
}

# ===== Main =====

if [ $# -eq 0 ]; then
    echo "Usage: $0 <model_name|--all> [prompt]"
    echo ""
    echo "Available models:"
    for m in $(list_models); do
        echo "  $m"
    done
    echo ""
    echo "Examples:"
    echo "  $0 llama33"
    echo "  $0 llama33 'What is AI?'"
    echo "  $0 --all"
    exit 1
fi

if [ "$1" = "--all" ]; then
    test_all_models
else
    test_model "$1" "${2:-}"
fi
