#!/bin/bash

#############################################################################
# Stream Load Tester - Multi-Protocol Stream Publishing Tool
# 
# Description: A comprehensive tool for testing streaming infrastructure
#              by generating multiple concurrent streams to various protocols
#              (RTMP, RTSP, SRT, WebRTC)
#
# Author: Stream Load Tester Project
# Version: 1.0
# Date: October 15, 2025
#############################################################################

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Global Configuration Variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/logs"
CONFIG_DIR="${SCRIPT_DIR}/config"
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"

# Default Configuration
DEFAULT_BITRATE=2000
DEFAULT_DURATION=30
DEFAULT_CONNECTIONS=5
DEFAULT_RAMP_TIME=2
MAX_CONNECTIONS=1000
MAX_BITRATE=50000
MIN_BITRATE=100

# Runtime Variables
PROTOCOL=""
BITRATE=""
SERVER_URL=""
NUM_CONNECTIONS=""
RAMP_TIME=""
STREAM_NAME=""
DURATION=""
LOG_FILE=""
PIDS=()
START_TIME=""
CLEANUP_DONE=false

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

#############################################################################
# Utility Functions
#############################################################################

log() {
    local level="$1"
    local component="$2"
    local message="$3"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[${timestamp}] [${level}] [${component}] ${message}" | tee -a "${LOG_FILE}"
}

log_info() {
    log "INFO" "$1" "$2"
    echo -e "${GREEN}[INFO]${NC} $2"
}

log_warn() {
    log "WARN" "$1" "$2"
    echo -e "${YELLOW}[WARN]${NC} $2"
}

log_error() {
    log "ERROR" "$1" "$2"
    echo -e "${RED}[ERROR]${NC} $2"
}

log_debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        log "DEBUG" "$1" "$2"
        echo -e "${PURPLE}[DEBUG]${NC} $2"
    fi
}

print_banner() {
    echo -e "${CYAN}"
    echo "=============================================================="
    echo "               STREAM LOAD TESTER v1.0"
    echo "        Multi-Protocol Stream Publishing Tool"
    echo "=============================================================="
    echo -e "${NC}"
}

cleanup() {
    # Prevent multiple cleanup calls
    if [[ "$CLEANUP_DONE" == "true" ]]; then
        return 0
    fi
    CLEANUP_DONE=true
    
    log_info "MAIN" "Cleaning up processes..."
    
    # First, try graceful termination (SIGTERM)
    for pid in "${PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            log_info "CLEANUP" "Terminating process $pid"
            kill -TERM "$pid" 2>/dev/null || true
        fi
    done
    
    # Wait a moment for graceful shutdown
    sleep 2
    
    # Force kill any remaining processes (SIGKILL)
    for pid in "${PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            log_warn "CLEANUP" "Force killing process $pid"
            kill -9 "$pid" 2>/dev/null || true
        fi
    done
    
    # Also kill any orphaned ffmpeg or python processes that might have been spawned
    # by matching the stream names or log file reference
    if [[ -n "${STREAM_NAME:-}" ]]; then
        log_info "CLEANUP" "Checking for orphaned stream processes..."
        pkill -f "${STREAM_NAME}" 2>/dev/null || true
    fi
    
    # Final wait to ensure processes are dead
    sleep 1
    
    log_info "MAIN" "Cleanup completed"
    echo -e "${GREEN}Test completed. Check logs at: ${LOG_FILE}${NC}"
}

#############################################################################
# Input Validation Functions
#############################################################################

validate_number() {
    local value="$1"
    local min="$2"
    local max="$3"
    local name="$4"
    
    if ! [[ "$value" =~ ^[0-9]+$ ]]; then
        log_error "VALIDATION" "$name must be a positive integer"
        return 1
    fi
    
    if (( value < min || value > max )); then
        log_error "VALIDATION" "$name must be between $min and $max"
        return 1
    fi
    
    return 0
}

validate_url() {
    local url="$1"
    local protocol="$2"
    
    case "$protocol" in
        "rtmp")
            if [[ ! "$url" =~ ^rtmp://.+/.+ ]]; then
                log_error "VALIDATION" "RTMP URL must be in format: rtmp://server:port/application"
                return 1
            fi
            ;;
        "rtsp")
            if [[ ! "$url" =~ ^rtsp://.+/.+ ]]; then
                log_error "VALIDATION" "RTSP URL must be in format: rtsp://server:port/application"
                return 1
            fi
            ;;
        "srt")
            if [[ ! "$url" =~ ^srt://.+\?streamid=.+ ]]; then
                log_error "VALIDATION" "SRT URL must be in format: srt://server:port?streamid=application"
                return 1
            fi
            ;;
        "webrtc")
            if [[ ! "$url" =~ ^https?://.+/.+ ]]; then
                log_error "VALIDATION" "WebRTC URL must be in format: http(s)://server:port/application"
                return 1
            fi
            ;;
    esac
    
    return 0
}

#############################################################################
# User Input Functions
#############################################################################

select_protocol() {
    echo -e "${BLUE}Select Protocol:${NC}"
    echo "1) RTMP"
    echo "2) RTSP"
    echo "3) SRT"
    echo "4) WebRTC"
    echo
    
    while true; do
        read -p "Enter choice [1-4]: " choice
        case "$choice" in
            1) PROTOCOL="rtmp"; break ;;
            2) PROTOCOL="rtsp"; break ;;
            3) PROTOCOL="srt"; break ;;
            4) 
                # Check WebRTC dependencies first
                if ! "${SCRIPT_DIR}/check_dependencies.sh" webrtc; then
                    log_error "PROTOCOL" "WebRTC dependencies not met. Please install required components."
                    echo "Would you like to select a different protocol? (y/n)"
                    read -p "> " retry
                    if [[ "$retry" =~ ^[Yy] ]]; then
                        continue
                    else
                        exit 1
                    fi
                fi
                PROTOCOL="webrtc"
                break
                ;;
            *) echo "Invalid choice. Please enter 1-4." ;;
        esac
    done
    
    log_info "INPUT" "Selected protocol: $PROTOCOL"
}

get_bitrate() {
    echo -e "${BLUE}Stream Configuration:${NC}"
    while true; do
        read -p "Enter bitrate in kbps [$DEFAULT_BITRATE]: " input
        BITRATE="${input:-$DEFAULT_BITRATE}"
        
        if validate_number "$BITRATE" "$MIN_BITRATE" "$MAX_BITRATE" "Bitrate"; then
            break
        fi
    done
    
    log_info "INPUT" "Set bitrate: ${BITRATE}k"
}

get_server_url() {
    echo
    local server=""
    local application=""
    
    case "$PROTOCOL" in
        "rtmp")
            echo -e "${BLUE}RTMP Server Configuration:${NC}"
            echo "Server format: rtmp://[IP]:[port]"
            echo "Example: rtmp://192.168.1.100:1935"
            echo
            while true; do
                read -p "Enter RTMP server URL: " server
                if [[ "$server" =~ ^rtmp://[^/]+$ ]]; then
                    break
                else
                    echo "Invalid format. Must be rtmp://server:port (without trailing slash)"
                fi
            done
            
            echo
            echo "Application name (e.g., 'live', 'app', 'stream')"
            while true; do
                read -p "Enter application name: " application
                if [[ -n "$application" ]]; then
                    break
                else
                    echo "Application name cannot be empty"
                fi
            done
            
            SERVER_URL="${server}/${application}"
            ;;
            
        "rtsp")
            echo -e "${BLUE}RTSP Server Configuration:${NC}"
            echo "Server format: rtsp://[IP]:[port]"
            echo "Example: rtsp://192.168.1.100:554"
            echo
            while true; do
                read -p "Enter RTSP server URL: " server
                if [[ "$server" =~ ^rtsp://[^/]+$ ]]; then
                    break
                else
                    echo "Invalid format. Must be rtsp://server:port (without trailing slash)"
                fi
            done
            
            echo
            echo "Application name (e.g., 'live', 'app', 'stream')"
            while true; do
                read -p "Enter application name: " application
                if [[ -n "$application" ]]; then
                    break
                else
                    echo "Application name cannot be empty"
                fi
            done
            
            SERVER_URL="${server}/${application}"
            ;;
            
        "srt")
            echo -e "${BLUE}SRT Server Configuration:${NC}"
            echo "Server format: srt://[IP]:[port]"
            echo "Example: srt://192.168.1.100:9999"
            echo
            while true; do
                read -p "Enter SRT server URL: " server
                if [[ "$server" =~ ^srt://[^?]+$ ]]; then
                    break
                else
                    echo "Invalid format. Must be srt://server:port (without query parameters)"
                fi
            done
            
            echo
            echo "Application name (will be used as streamid prefix)"
            while true; do
                read -p "Enter application name: " application
                if [[ -n "$application" ]]; then
                    break
                else
                    echo "Application name cannot be empty"
                fi
            done
            
            SERVER_URL="${server}?streamid=${application}"
            ;;
            
        "webrtc")
            echo -e "${BLUE}WebRTC Server Configuration:${NC}"
            echo "Server format: http(s)://[IP]:[port]/[application]"
            echo "Example: https://192.168.1.100:8443/live"
            echo
            while true; do
                read -p "Enter WebRTC server URL (including application): " SERVER_URL
                if [[ "$SERVER_URL" =~ ^https?://.+/.+ ]]; then
                    break
                else
                    echo "Invalid format. Must be http(s)://server:port/application"
                fi
            done
            ;;
    esac
    
    log_info "INPUT" "Set server URL: $SERVER_URL"
}

get_connection_params() {
    echo
    while true; do
        read -p "Number of connections [$DEFAULT_CONNECTIONS]: " input
        NUM_CONNECTIONS="${input:-$DEFAULT_CONNECTIONS}"
        
        if validate_number "$NUM_CONNECTIONS" 1 "$MAX_CONNECTIONS" "Number of connections"; then
            break
        fi
    done
    
    while true; do
        read -p "Ramp-up time in minutes [$DEFAULT_RAMP_TIME]: " input
        RAMP_TIME="${input:-$DEFAULT_RAMP_TIME}"
        
        if validate_number "$RAMP_TIME" 1 60 "Ramp-up time"; then
            break
        fi
    done
    
    log_info "INPUT" "Set connections: $NUM_CONNECTIONS, ramp-up: ${RAMP_TIME}m"
}

get_stream_details() {
    echo
    while true; do
        read -p "Base stream name: " STREAM_NAME
        if [[ -n "$STREAM_NAME" ]]; then
            break
        fi
        echo "Stream name cannot be empty."
    done
    
    while true; do
        read -p "Test duration in minutes [$DEFAULT_DURATION]: " input
        DURATION="${input:-$DEFAULT_DURATION}"
        
        if validate_number "$DURATION" 1 1440 "Duration"; then
            break
        fi
    done
    
    log_info "INPUT" "Set stream name: $STREAM_NAME, duration: ${DURATION}m"
}

#############################################################################
# Stream Generation Functions
#############################################################################

build_stream_url() {
    local stream_name="$1"
    local destination_url=""
    
    # Build destination URL based on protocol
    case "$PROTOCOL" in
        "rtmp"|"rtsp")
            destination_url="${SERVER_URL}/${stream_name}"
            ;;
        "srt")
            if [[ "$SERVER_URL" =~ \?streamid= ]]; then
                # Extract application name from streamid parameter
                local server_base=$(echo "$SERVER_URL" | sed 's/\?streamid=.*//')
                local application=$(echo "$SERVER_URL" | sed 's/.*streamid=\([^&]*\).*/\1/')
                # Wowza format: streamid=#!::m=publish,r=application/_definst_/stream-name
                destination_url="${server_base}?streamid=#!::m=publish,r=${application}/_definst_/${stream_name}"
            else
                destination_url="${SERVER_URL}?streamid=${stream_name}"
            fi
            ;;
    esac
    
    echo "$destination_url"
}

build_multi_output_ffmpeg_command() {
    # Build FFmpeg command with multiple outputs from a single encode
    # Uses the tee protocol to send one encode to multiple destinations
    
    local cmd="ffmpeg -hide_banner -loglevel error"
    cmd+=" -re"  # Read input at native frame rate (important for streaming)
    cmd+=" -f lavfi -i testsrc2=size=1920x1080:rate=30"
    cmd+=" -f lavfi -i sine=frequency=1000:sample_rate=48000"
    
    # Map both input streams (video from input 0, audio from input 1)
    cmd+=" -map 0:v -map 1:a"
    
    # Encode once
    cmd+=" -c:v libx264 -preset veryfast -b:v ${BITRATE}k -g 60 -keyint_min 60"
    cmd+=" -c:a aac -b:a 128k"
    cmd+=" -t $((DURATION * 60))"  # Convert minutes to seconds
    
    # Get the format based on protocol
    local format=""
    case "$PROTOCOL" in
        "rtmp")
            format="flv"
            ;;
        "rtsp")
            format="rtsp"
            ;;
        "srt")
            format="mpegts"
            ;;
    esac
    
    # Build tee output string with all destinations
    local tee_outputs=""
    for (( i=1; i<=NUM_CONNECTIONS; i++ )); do
        local padded_number=$(printf "%03d" "$i")
        local stream_name="${STREAM_NAME}${padded_number}"
        local destination_url=$(build_stream_url "$stream_name")
        
        if [[ -n "$tee_outputs" ]]; then
            tee_outputs+="|"
        fi
        
        # For tee muxer, we only need to escape pipe characters in the URL itself
        # Do NOT escape colons - they're needed for the URL
        local escaped_url="${destination_url//|/\\|}"
        
        tee_outputs+="[f=${format}]${escaped_url}"
    done
    
    # Use tee muxer to send to all destinations
    cmd+=" -f tee \"${tee_outputs}\""
    
    echo "$cmd"
}

build_single_stream_ffmpeg_command() {
    # Legacy function for single stream - kept for compatibility
    local stream_name="$1"
    local destination_url=$(build_stream_url "$stream_name")
    
    local cmd="ffmpeg -hide_banner -loglevel error"
    cmd+=" -re"  # Read input at native frame rate
    cmd+=" -f lavfi -i testsrc2=size=1920x1080:rate=30"
    cmd+=" -f lavfi -i sine=frequency=1000:sample_rate=48000"
    cmd+=" -c:v libx264 -preset veryfast -b:v ${BITRATE}k"
    cmd+=" -c:a aac -b:a 128k"
    cmd+=" -t $((DURATION * 60))"
    
    local format=""
    case "$PROTOCOL" in
        "rtmp")
            format="flv"
            ;;
        "rtsp")
            format="rtsp"
            ;;
        "srt")
            format="mpegts"
            ;;
    esac
    
    cmd+=" -f ${format} \"${destination_url}\""
    echo "$cmd"
}

start_stream() {
    local stream_number="$1"
    local padded_number=$(printf "%03d" "$stream_number")
    local stream_name="${STREAM_NAME}${padded_number}"
    
    if [[ "$PROTOCOL" == "webrtc" ]]; then
        # Use Python script for WebRTC
        log_info "STREAM-${padded_number}" "Starting WebRTC stream: $stream_name"
        
        # Check if we have a virtual environment setup
        local python_cmd="python3"
        local webrtc_wrapper="$HOME/.local/bin/stream-load-tester-webrtc"
        
        if [[ -x "$webrtc_wrapper" ]]; then
            python_cmd="$webrtc_wrapper"
            log_debug "STREAM-${padded_number}" "Using virtual environment wrapper"
        fi
        
        "$python_cmd" "${SCRIPT_DIR}/webrtc_publisher.py" \
            --url "$SERVER_URL" \
            --stream-name "$stream_name" \
            --bitrate "$BITRATE" \
            --duration "$DURATION" \
            --log-file "$LOG_FILE" &
        local pid=$!
    else
        # Use FFmpeg for other protocols - single stream mode
        local ffmpeg_cmd=$(build_single_stream_ffmpeg_command "$stream_name")
        log_info "STREAM-${padded_number}" "Starting stream: $stream_name"
        log_debug "STREAM-${padded_number}" "Command: $ffmpeg_cmd"
        
        # Start ffmpeg in background and capture its PID
        eval "$ffmpeg_cmd" </dev/null &
        local pid=$!
    fi
    
    PIDS+=("$pid")
    log_info "STREAM-${padded_number}" "Stream started with PID: $pid"
    
    # Verify the process actually started
    sleep 0.5
    if ! kill -0 "$pid" 2>/dev/null; then
        log_warn "STREAM-${padded_number}" "Process $pid died immediately after starting"
    fi
}

start_multi_output_stream() {
    # Start a single FFmpeg process that outputs to all streams
    # This is much more CPU efficient than multiple processes
    
    log_info "MAIN" "Starting single FFmpeg process with ${NUM_CONNECTIONS} outputs..."
    
    local ffmpeg_cmd=$(build_multi_output_ffmpeg_command)
    log_debug "MAIN" "Multi-output command: $ffmpeg_cmd"
    
    # Create a temporary log file for FFmpeg errors
    local ffmpeg_log="${LOG_DIR}/ffmpeg_$(date +%Y%m%d_%H%M%S).log"
    
    # Start the multi-output FFmpeg process with error logging
    eval "$ffmpeg_cmd" </dev/null 2>"$ffmpeg_log" &
    local pid=$!
    
    PIDS+=("$pid")
    log_info "MAIN" "Multi-output FFmpeg started with PID: $pid"
    
    # Verify the process actually started
    sleep 2
    if ! kill -0 "$pid" 2>/dev/null; then
        log_error "MAIN" "Multi-output FFmpeg process died immediately after starting"
        log_error "MAIN" "Check FFmpeg log: $ffmpeg_log"
        if [[ -f "$ffmpeg_log" && -s "$ffmpeg_log" ]]; then
            log_error "MAIN" "FFmpeg error output (last 20 lines):"
            tail -n 20 "$ffmpeg_log" | tee -a "$LOG_FILE"
        fi
        return 1
    fi
    
    log_info "MAIN" "FFmpeg process is running, streaming to ${NUM_CONNECTIONS} destinations"
    
    # Log each stream that was started
    for (( i=1; i<=NUM_CONNECTIONS; i++ )); do
        local padded_number=$(printf "%03d" "$i")
        local stream_name="${STREAM_NAME}${padded_number}"
        log_info "STREAM-${padded_number}" "Stream configured: $stream_name"
    done
    
    return 0
}

#############################################################################
# Main Execution Functions
#############################################################################

run_load_test() {
    START_TIME=$(date +%s)
    
    # For WebRTC, we need separate processes (one per connection)
    # For other protocols, we can use a single FFmpeg with multiple outputs (more efficient)
    if [[ "$PROTOCOL" == "webrtc" ]]; then
        log_info "MAIN" "Starting load test: $NUM_CONNECTIONS WebRTC connections over ${RAMP_TIME}m"
        
        # Calculate interval between connections for ramping
        local interval_seconds=0
        if (( NUM_CONNECTIONS > 1 )); then
            interval_seconds=$(( (RAMP_TIME * 60) / (NUM_CONNECTIONS - 1) ))
        fi
        log_info "MAIN" "Connection interval: ${interval_seconds}s"
        
        # Start WebRTC connections with ramping
        for (( i=1; i<=NUM_CONNECTIONS; i++ )); do
            start_stream "$i"
            
            # Wait before starting next connection (except for the last one)
            if (( i < NUM_CONNECTIONS && interval_seconds > 0 )); then
                log_info "MAIN" "Waiting ${interval_seconds}s before next connection..."
                sleep "$interval_seconds"
            fi
        done
    else
        # For RTMP/RTSP/SRT, use single FFmpeg process with multiple outputs
        log_info "MAIN" "Starting load test: $NUM_CONNECTIONS ${PROTOCOL^^} streams (single encode, multiple outputs)"
        log_info "MAIN" "Using efficient single-process mode to reduce CPU usage"
        
        if ! start_multi_output_stream; then
            log_error "MAIN" "Failed to start multi-output stream"
            return 1
        fi
    fi
    
    log_info "MAIN" "All streams started. Test will run for ${DURATION} minutes."
    
    # Monitor the test
    log_debug "MAIN" "About to call monitor_test()"
    monitor_test
    log_debug "MAIN" "Returned from monitor_test()"
}

monitor_test() {
    local test_duration_seconds=$((DURATION * 60))
    local check_interval=10
    local elapsed=0
    
    log_debug "MONITOR" "Starting monitoring: duration=${test_duration_seconds}s, interval=${check_interval}s"
    log_debug "MONITOR" "PIDS array has ${#PIDS[@]} elements: ${PIDS[*]}"
    
    while (( elapsed < test_duration_seconds )); do
        log_debug "MONITOR" "Sleeping for ${check_interval}s (elapsed: ${elapsed}s)"
        sleep "$check_interval"
        elapsed=$((elapsed + check_interval))
        
        log_debug "MONITOR" "Woke up, checking processes (elapsed: ${elapsed}s)"
        
        # Check how many processes are still running
        local running_count=0
        
        log_debug "MONITOR" "About to loop through PIDS"
        
        for pid in "${PIDS[@]}"; do
            log_debug "MONITOR" "Checking PID: $pid"
            if kill -0 "$pid" 2>/dev/null; then
                running_count=$((running_count + 1))
                log_debug "MONITOR" "PID $pid is still running (count now: $running_count)"
            else
                log_debug "MONITOR" "PID $pid is NOT running"
            fi
        done
        
        log_debug "MONITOR" "Finished checking PIDs"
        
        local remaining_time=$((test_duration_seconds - elapsed))
        
        log_debug "MONITOR" "running_count=$running_count, remaining_time=$remaining_time"
        
        # For multi-output mode (RTMP/RTSP/SRT), we have 1 process serving N streams
        # For WebRTC, we have N processes
        if [[ "$PROTOCOL" != "webrtc" ]]; then
            if (( running_count > 0 )); then
                log_info "MONITOR" "FFmpeg process running, ${NUM_CONNECTIONS} streams active, Time remaining: ${remaining_time}s"
            else
                log_warn "MONITOR" "FFmpeg process ended prematurely"
                break
            fi
        else
            log_info "MONITOR" "Running streams: $running_count/$NUM_CONNECTIONS, Time remaining: ${remaining_time}s"
            
            # If no streams are running, exit early
            if (( running_count == 0 )); then
                log_warn "MONITOR" "All streams have ended prematurely"
                break
            fi
        fi
    done
    
    log_info "MAIN" "Test duration completed"
    log_debug "MONITOR" "Exiting monitor_test() normally"
}

print_summary() {
    local end_time=$(date +%s)
    local total_time=$((end_time - START_TIME))
    
    echo
    echo -e "${CYAN}=============================================================="
    echo "                    TEST SUMMARY"
    echo "==============================================================${NC}"
    echo "Protocol:           $PROTOCOL"
    echo "Server URL:         $SERVER_URL"
    echo "Stream Name:        $STREAM_NAME"
    echo "Bitrate:            ${BITRATE}k"
    echo "Connections:        $NUM_CONNECTIONS"
    
    # Show encoding mode info
    if [[ "$PROTOCOL" == "webrtc" ]]; then
        echo "Encoding Mode:      Multiple processes (${NUM_CONNECTIONS} encodes)"
    else
        echo "Encoding Mode:      Single process (1 encode, ${NUM_CONNECTIONS} outputs)"
    fi
    
    echo "Ramp-up Time:       ${RAMP_TIME}m"
    echo "Test Duration:      ${DURATION}m"
    echo "Actual Runtime:     ${total_time}s"
    echo "Log File:           $LOG_FILE"
    echo -e "${CYAN}==============================================================${NC}"
}

#############################################################################
# Command Line Argument Parsing
#############################################################################

show_help() {
    echo "Stream Load Tester v1.0"
    echo
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  -p, --protocol PROTOCOL     Protocol to use (rtmp, rtsp, srt, webrtc)"
    echo "  -b, --bitrate BITRATE       Bitrate in kbps (default: $DEFAULT_BITRATE)"
    echo "  -u, --url URL               Server URL with application (format depends on protocol)"
    echo "  -c, --connections COUNT     Number of connections (default: $DEFAULT_CONNECTIONS)"
    echo "  -r, --ramp-time MINUTES     Ramp-up time in minutes (default: $DEFAULT_RAMP_TIME)"
    echo "  -s, --stream-name NAME      Base stream name (numbers will be appended)"
    echo "  -d, --duration MINUTES      Test duration in minutes (default: $DEFAULT_DURATION)"
    echo "  -l, --log-level LEVEL       Log level (DEBUG, INFO, WARN, ERROR)"
    echo "  -h, --help                  Show this help message"
    echo "  -v, --version               Show version information"
    echo
    echo "URL Formats by Protocol:"
    echo "  RTMP:   rtmp://server:port/application"
    echo "  RTSP:   rtsp://server:port/application"
    echo "  SRT:    srt://server:port?streamid=application (Wowza format used automatically)"
    echo "  WebRTC: https://server:port/application"
    echo
    echo "Note: SRT streams will be published using Wowza's format:"
    echo "      srt://server:port?streamid=#!::m=publish,r=application/_definst_/stream-name"
    echo
    echo "Examples:"
    echo "  # Interactive mode"
    echo "  $0"
    echo
    echo "  # Command line mode - RTMP"
    echo "  $0 --protocol rtmp --bitrate 2000 --url 'rtmp://192.168.1.100:1935/live' \\"
    echo "     --connections 10 --ramp-time 5 --stream-name 'test' --duration 30"
    echo
    echo "  # Command line mode - SRT (provide application name, Wowza format applied automatically)"
    echo "  $0 --protocol srt --bitrate 3000 --url 'srt://192.168.1.100:9999?streamid=live' \\"
    echo "     --connections 5 --stream-name 'stream' --duration 60"
}

show_version() {
    echo "Stream Load Tester v1.0"
    echo "Multi-Protocol Stream Publishing Tool"
    echo "October 15, 2025"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--protocol)
                PROTOCOL="$2"
                shift 2
                ;;
            -b|--bitrate)
                BITRATE="$2"
                shift 2
                ;;
            -u|--url)
                SERVER_URL="$2"
                shift 2
                ;;
            -c|--connections)
                NUM_CONNECTIONS="$2"
                shift 2
                ;;
            -r|--ramp-time)
                RAMP_TIME="$2"
                shift 2
                ;;
            -s|--stream-name)
                STREAM_NAME="$2"
                shift 2
                ;;
            -d|--duration)
                DURATION="$2"
                shift 2
                ;;
            -l|--log-level)
                export LOG_LEVEL="$2"
                shift 2
                ;;
            --debug)
                export DEBUG="true"
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--version)
                show_version
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

#############################################################################
# Main Function
#############################################################################

main() {
    # Set up signal handlers - cleanup will kill all child processes
    trap cleanup EXIT INT TERM
    
    # Create log file
    LOG_FILE="${LOG_DIR}/stream_test_$(date +%Y%m%d_%H%M%S).log"
    mkdir -p "$LOG_DIR"
    
    # Parse command line arguments
    parse_args "$@"
    
    # Print banner
    print_banner
    
    # Check dependencies (capture output and exit code to make failures visible)
    log_info "MAIN" "Checking dependencies..."

    # Print environment useful for dependency checks (always visible)
    echo "--- Environment diagnostics ---" | tee -a "$LOG_FILE"
    echo "PATH=$PATH" | tee -a "$LOG_FILE"
    echo "which ffmpeg: $(command -v ffmpeg || echo 'none')" | tee -a "$LOG_FILE"
    (command -v ffmpeg >/dev/null 2>&1 && ffmpeg -version 2>&1 | head -n1 || echo 'ffmpeg not present') | tee -a "$LOG_FILE"
    echo "which python3: $(command -v python3 || echo 'none')" | tee -a "$LOG_FILE"
    (command -v python3 >/dev/null 2>&1 && python3 --version 2>&1 || echo 'python3 not present') | tee -a "$LOG_FILE"
    echo "--- End diagnostics ---" | tee -a "$LOG_FILE"
    # Run checker once and capture its exit code while mirroring output to the log
    local checker_status=0
    local tee_status=0
    local status_array=()

    set +e  # Allow the pipeline to fail without aborting so we can inspect PIPESTATUS
    "${SCRIPT_DIR}/check_dependencies.sh" basic 2>&1 | tee -a "$LOG_FILE"
    status_array=("${PIPESTATUS[@]}")
    set -e

    checker_status=${status_array[0]:-1}
    tee_status=${status_array[1]:-0}

    if (( tee_status != 0 )); then
        log_warn "MAIN" "Failed to write dependency check output to log (tee exited with ${tee_status})."
    fi

    if (( checker_status != 0 )); then
        log_error "MAIN" "Basic dependencies not met (check exited with code ${checker_status}). See above for details."
        exit 1
    fi
    
    # If running in interactive mode, get user input
    if [[ -z "$PROTOCOL" ]]; then
        select_protocol
        get_bitrate
        get_server_url
        get_connection_params
        get_stream_details
    else
        # Validate command line arguments
        if [[ -z "$SERVER_URL" || -z "$STREAM_NAME" ]]; then
            log_error "MAIN" "Server URL and stream name are required in command line mode"
            show_help
            exit 1
        fi
        
        # Set defaults for missing values
        BITRATE="${BITRATE:-$DEFAULT_BITRATE}"
        NUM_CONNECTIONS="${NUM_CONNECTIONS:-$DEFAULT_CONNECTIONS}"
        RAMP_TIME="${RAMP_TIME:-$DEFAULT_RAMP_TIME}"
        DURATION="${DURATION:-$DEFAULT_DURATION}"
        
        # Validate all parameters
        validate_number "$BITRATE" "$MIN_BITRATE" "$MAX_BITRATE" "Bitrate" || exit 1
        validate_number "$NUM_CONNECTIONS" 1 "$MAX_CONNECTIONS" "Number of connections" || exit 1
        validate_number "$RAMP_TIME" 1 60 "Ramp-up time" || exit 1
        validate_number "$DURATION" 1 1440 "Duration" || exit 1
        validate_url "$SERVER_URL" "$PROTOCOL" || exit 1
    fi
    
    # Show configuration summary
    echo
    echo -e "${YELLOW}Configuration Summary:${NC}"
    echo "Protocol:           $PROTOCOL"
    echo "Bitrate:            ${BITRATE}k"
    echo "Server URL:         $SERVER_URL"
    echo "Connections:        $NUM_CONNECTIONS"
    echo "Ramp-up Time:       ${RAMP_TIME}m"
    echo "Stream Name:        $STREAM_NAME"
    echo "Duration:           ${DURATION}m"
    echo "Log File:           $LOG_FILE"
    echo
    
    # Confirm before starting
    if [[ "${FORCE:-false}" != "true" ]]; then
        read -p "Start the test? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy] ]]; then
            echo "Test cancelled."
            exit 0
        fi
    fi
    
    # Run the load test
    log_info "MAIN" "Starting stream load test"
    run_load_test
    
    # Print summary
    print_summary
    
    log_info "MAIN" "Stream load test completed"
    
    # Note: cleanup() will be called automatically via the EXIT trap
}

# Execute main function with all arguments
main "$@"