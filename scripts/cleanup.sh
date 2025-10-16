#!/bin/bash

#############################################################################
# Cleanup Utility for Stream Load Tester
# 
# Description: Utility script to clean up processes, logs, and temporary files
#              left by the stream load tester
#
# Usage: ./cleanup.sh [options]
#
# Author: Stream Load Tester Project
# Version: 1.0
# Date: October 15, 2025
#############################################################################

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="${SCRIPT_DIR}/logs"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Flags
FORCE=false
VERBOSE=false
LOGS_ONLY=false
PROCESSES_ONLY=false

show_help() {
    echo "Cleanup Utility for Stream Load Tester"
    echo
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  -f, --force         Force cleanup without confirmation"
    echo "  -v, --verbose       Verbose output"
    echo "  -l, --logs-only     Clean up logs only"
    echo "  -p, --processes-only Clean up processes only"
    echo "  -h, --help          Show this help message"
    echo
    echo "Examples:"
    echo "  $0                  # Interactive cleanup"
    echo "  $0 --force          # Force cleanup everything"
    echo "  $0 --logs-only      # Clean up old logs only"
    echo "  $0 --processes-only # Kill remaining processes only"
}

log() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${BLUE}[DEBUG]${NC} $1"
    fi
}

info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

cleanup_processes() {
    info "Cleaning up stream load tester processes..."
    
    local processes_found=false
    
    # Find FFmpeg processes with our test pattern
    if pgrep -f "testsrc2.*sine" >/dev/null 2>&1; then
        processes_found=true
        warn "Found running FFmpeg test streams"
        
        if [[ "$FORCE" == "true" ]]; then
            info "Killing FFmpeg test streams..."
            pkill -f "testsrc2.*sine" || true
        else
            echo "Kill running FFmpeg test streams? (y/N)"
            read -r response
            if [[ "$response" =~ ^[Yy] ]]; then
                info "Killing FFmpeg test streams..."
                pkill -f "testsrc2.*sine" || true
            fi
        fi
    fi
    
    # Check for any orphaned stream_load_tester processes
    if pgrep -f "stream_load_tester.sh" >/dev/null 2>&1; then
        processes_found=true
        warn "Found running stream_load_tester.sh processes"
        
        if [[ "$FORCE" == "true" ]]; then
            info "Killing stream_load_tester.sh processes..."
            pkill -f "stream_load_tester.sh" || true
        else
            echo "Kill running stream_load_tester.sh processes? (y/N)"
            read -r response
            if [[ "$response" =~ ^[Yy] ]]; then
                info "Killing stream_load_tester.sh processes..."
                pkill -f "stream_load_tester.sh" || true
            fi
        fi
    fi
    
    if [[ "$processes_found" == "false" ]]; then
        info "No stream load tester processes found"
    else
        # Wait a moment for processes to terminate
        sleep 2
        
        # Check if any processes are still running
        local remaining=0
        remaining+=$(pgrep -f "testsrc2.*sine" | wc -l || echo 0)
        remaining+=$(pgrep -f "stream_load_tester.sh" | wc -l || echo 0)
        
        if (( remaining > 0 )); then
            warn "$remaining processes still running after cleanup attempt"
            warn "You may need to use 'kill -9' manually"
        else
            info "All processes cleaned up successfully"
        fi
    fi
}

cleanup_logs() {
    info "Cleaning up log files..."
    
    if [[ ! -d "$LOG_DIR" ]]; then
        info "Log directory does not exist: $LOG_DIR"
        return
    fi
    
    # Count log files
    local log_count=0
    if ls "$LOG_DIR"/*.log >/dev/null 2>&1; then
        log_count=$(ls "$LOG_DIR"/*.log | wc -l)
    fi
    
    if (( log_count == 0 )); then
        info "No log files found to clean up"
        return
    fi
    
    info "Found $log_count log files"
    
    # Show disk usage
    if command -v du >/dev/null 2>&1; then
        local size=$(du -sh "$LOG_DIR" 2>/dev/null | cut -f1 || echo "unknown")
        info "Log directory size: $size"
    fi
    
    # Ask for confirmation unless force is used
    if [[ "$FORCE" == "true" ]]; then
        info "Removing all log files..."
        rm -f "$LOG_DIR"/*.log
        info "Log files removed"
    else
        echo "Remove all log files in $LOG_DIR? (y/N)"
        read -r response
        if [[ "$response" =~ ^[Yy] ]]; then
            info "Removing log files..."
            rm -f "$LOG_DIR"/*.log
            info "Log files removed"
        else
            info "Log files kept"
            
            # Offer to remove old logs only
            echo "Remove log files older than 7 days? (y/N)"
            read -r response
            if [[ "$response" =~ ^[Yy] ]]; then
                info "Removing old log files..."
                find "$LOG_DIR" -name "*.log" -type f -mtime +7 -delete 2>/dev/null || true
                info "Old log files removed"
            fi
        fi
    fi
}

cleanup_temp_files() {
    info "Cleaning up temporary files..."
    
    # Remove any temporary files that might be created
    local temp_patterns=(
        "/tmp/stream_load_tester_*"
        "${SCRIPT_DIR}/*.tmp"
        "${SCRIPT_DIR}/*.pid"
    )
    
    local files_found=false
    
    for pattern in "${temp_patterns[@]}"; do
        if ls $pattern >/dev/null 2>&1; then
            files_found=true
            log "Found temporary files matching: $pattern"
            rm -f $pattern 2>/dev/null || true
        fi
    done
    
    if [[ "$files_found" == "true" ]]; then
        info "Temporary files cleaned up"
    else
        info "No temporary files found"
    fi
}

show_system_status() {
    info "Current system status:"
    
    # Show running processes
    local ffmpeg_count=0
    local script_count=0
    
    ffmpeg_count=$(pgrep -f "testsrc2.*sine" | wc -l || echo 0)
    script_count=$(pgrep -f "stream_load_tester.sh" | wc -l || echo 0)
    
    echo "  FFmpeg test streams: $ffmpeg_count"
    echo "  Stream load tester scripts: $script_count"
    
    # Show log directory status
    if [[ -d "$LOG_DIR" ]]; then
        local log_count=0
        if ls "$LOG_DIR"/*.log >/dev/null 2>&1; then
            log_count=$(ls "$LOG_DIR"/*.log | wc -l)
        fi
        echo "  Log files: $log_count"
        
        if command -v du >/dev/null 2>&1; then
            local size=$(du -sh "$LOG_DIR" 2>/dev/null | cut -f1 || echo "unknown")
            echo "  Log directory size: $size"
        fi
    else
        echo "  Log directory: not found"
    fi
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--force)
                FORCE=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -l|--logs-only)
                LOGS_ONLY=true
                shift
                ;;
            -p|--processes-only)
                PROCESSES_ONLY=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

main() {
    echo -e "${BLUE}Stream Load Tester Cleanup Utility${NC}"
    echo "====================================="
    echo
    
    # Parse command line arguments
    parse_args "$@"
    
    # Show current status
    show_system_status
    echo
    
    # Perform cleanup based on options
    if [[ "$PROCESSES_ONLY" == "true" ]]; then
        cleanup_processes
    elif [[ "$LOGS_ONLY" == "true" ]]; then
        cleanup_logs
    else
        # Full cleanup
        if [[ "$FORCE" != "true" ]]; then
            warn "This will clean up all stream load tester processes and files"
            echo "Continue? (y/N)"
            read -r response
            if [[ ! "$response" =~ ^[Yy] ]]; then
                info "Cleanup cancelled"
                exit 0
            fi
        fi
        
        cleanup_processes
        echo
        cleanup_logs
        echo
        cleanup_temp_files
    fi
    
    echo
    info "Cleanup completed"
    
    # Show final status
    echo
    show_system_status
}

# Execute main function
main "$@"