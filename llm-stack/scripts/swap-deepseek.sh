#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/model-lib.sh"

# ===== Swap DeepSeek <-> MIMO =====

swap_deepseek() {
    local action=$1
    
    case "$action" in
        --enable|enable)
            log_info "Enabling DeepSeek (disabling MIMO)..."
            
            # Stop MIMO
            log_info "Stopping MIMO..."
            "$SCRIPT_DIR/stop-model.sh" mimo || log_warn "MIMO was not running"
            
            sleep 2
            
            # Start DeepSeek
            log_info "Starting DeepSeek..."
            if ! "$SCRIPT_DIR/start-model.sh" deepseek; then
                log_error "Failed to start DeepSeek"
                log_info "Attempting to restart MIMO..."
                "$SCRIPT_DIR/start-model.sh" mimo
                return 1
            fi
            
            log_info "DeepSeek is now active (MIMO is stopped)"
            log_info "Both models share A30 GPUs 0,1 (tensor-parallel)"
            
            ;;
        --disable|disable)
            log_info "Disabling DeepSeek (enabling MIMO)..."
            
            # Stop DeepSeek
            log_info "Stopping DeepSeek..."
            "$SCRIPT_DIR/stop-model.sh" deepseek || log_warn "DeepSeek was not running"
            
            sleep 2
            
            # Start MIMO
            log_info "Starting MIMO..."
            if ! "$SCRIPT_DIR/start-model.sh" mimo; then
                log_error "Failed to start MIMO"
                log_info "You can retry with: $SCRIPT_DIR/swap-deepseek.sh enable"
                return 1
            fi
            
            log_info "MIMO is now active (DeepSeek is stopped)"
            
            ;;
        --status|status)
            echo ""
            echo "─── MIMO vs DeepSeek Status ───"
            echo ""
            
            if model_is_running "mimo"; then
                echo "✓ MIMO: RUNNING on port $(get_model_port mimo)"
            else
                echo "✗ MIMO: STOPPED"
            fi
            
            if model_is_running "deepseek"; then
                echo "✓ DeepSeek: RUNNING on port $(get_model_port deepseek)"
            else
                echo "✗ DeepSeek: STOPPED"
            fi
            
            echo ""
            echo "Both models share A30 GPUs 0,1 (tensor-parallel-size: 2)"
            echo "Only one can run at a time."
            echo ""
            
            ;;
        *)
            echo "Usage: $0 {--enable|--disable|--status}"
            echo ""
            echo "Commands:"
            echo "  --enable   Enable DeepSeek (stop MIMO)"
            echo "  --disable  Disable DeepSeek (start MIMO)"
            echo "  --status   Show current MIMO/DeepSeek status"
            echo ""
            echo "Note: Both models share A30 GPUs 0,1"
            exit 1
            ;;
    esac
}

# ===== Main =====

if [ $# -eq 0 ]; then
    echo "Usage: $0 {--enable|--disable|--status}"
    echo ""
    echo "Commands:"
    echo "  --enable   Enable DeepSeek (stop MIMO)"
    echo "  --disable  Disable DeepSeek (start MIMO)"
    echo "  --status   Show current MIMO/DeepSeek status"
    exit 1
fi

swap_deepseek "$1"
