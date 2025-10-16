#!/bin/bash

#############################################################################
# Stream Load Tester - Multi-Protocol Stream Publishing Tool
# 
# Description: A comprehensive tool for testing streaming infrastructure
#              by generating multiple concurrent streams to various protocols
#              (RTMP, RTSP, SRT)
#
# Author: Stream Load Tester Project
# Version: 2.0
# Date: October 16, 2025
#############################################################################

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Global Configuration Variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/logs"
CONFIG_DIR="${SCRIPT_DIR}/config"
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"
PREVIOUS_RUNS_DIR="${SCRIPT_DIR}/previous_runs"

# Default Configuration
DEFAULT_BITRATE=2000
DEFAULT_DURATION=30
DEFAULT_CONNECTIONS=5
DEFAULT_RESOLUTION="1080p"
DEFAULT_VIDEO_CODEC="h264"
DEFAULT_AUDIO_CODEC="aac"
MAX_CONNECTIONS=1000
MAX_BITRATE=50000
MIN_BITRATE=100

# Runtime Variables
PROTOCOL=""
BITRATE=""
SERVER_URL=""
NUM_CONNECTIONS=""
STREAM_NAME=""
DURATION=""
RESOLUTION=""
VIDEO_CODEC=""
AUDIO_CODEC=""
VIDEO_WIDTH=""
VIDEO_HEIGHT=""
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
    echo -e "${BLUE}Tip: For orphaned processes from crashes, run: ./scripts/cleanup.sh${NC}"
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
    echo
    
    while true; do
        read -p "Enter choice [1-3]: " choice
        case "$choice" in
            1) PROTOCOL="rtmp"; break ;;
            2) PROTOCOL="rtsp"; break ;;
            3) PROTOCOL="srt"; break ;;
            *) echo "Invalid choice. Please enter 1-3." ;;
        esac
    done
    
    log_info "INPUT" "Selected protocol: $PROTOCOL"
}

get_resolution() {
    echo
    echo -e "${BLUE}Select Video Resolution:${NC}"
    echo "1) 4K (3840x2160)     - Recommended: H.264: 10000-25000 kbps, H.265: 5000-15000 kbps"
    echo "2) 1080p (1920x1080)  - Recommended: H.264: 3000-8000 kbps, H.265: 1500-5000 kbps"
    echo "3) 720p (1280x720)    - Recommended: H.264: 1500-4000 kbps, H.265: 800-2500 kbps"
    echo "4) 360p (640x360)     - Recommended: H.264: 500-1500 kbps, H.265: 300-1000 kbps"
    echo
    
    while true; do
        read -p "Enter choice [1-4]: " choice
        case "$choice" in
            1) 
                RESOLUTION="4k"
                VIDEO_WIDTH=3840
                VIDEO_HEIGHT=2160
                MIN_BITRATE=3000
                MAX_BITRATE=50000
                DEFAULT_BITRATE=12000
                break 
                ;;
            2) 
                RESOLUTION="1080p"
                VIDEO_WIDTH=1920
                VIDEO_HEIGHT=1080
                MIN_BITRATE=1000
                MAX_BITRATE=15000
                DEFAULT_BITRATE=4000
                break 
                ;;
            3) 
                RESOLUTION="720p"
                VIDEO_WIDTH=1280
                VIDEO_HEIGHT=720
                MIN_BITRATE=500
                MAX_BITRATE=8000
                DEFAULT_BITRATE=2000
                break 
                ;;
            4) 
                RESOLUTION="360p"
                VIDEO_WIDTH=640
                VIDEO_HEIGHT=360
                MIN_BITRATE=200
                MAX_BITRATE=3000
                DEFAULT_BITRATE=800
                break 
                ;;
            *) echo "Invalid choice. Please enter 1-4." ;;
        esac
    done
    
    log_info "INPUT" "Selected resolution: $RESOLUTION (${VIDEO_WIDTH}x${VIDEO_HEIGHT})"
}

get_video_codec() {
    echo
    echo -e "${BLUE}Select Video Codec:${NC}"
    echo "1) H.264 (libx264) - Widely compatible, good compression"
    echo "2) H.265 (libx265) - Better compression, lower bitrate for same quality"
    echo
    
    while true; do
        read -p "Enter choice [1-2]: " choice
        case "$choice" in
            1) VIDEO_CODEC="h264"; break ;;
            2) VIDEO_CODEC="h265"; break ;;
            *) echo "Invalid choice. Please enter 1-2." ;;
        esac
    done
    
    log_info "INPUT" "Selected video codec: $VIDEO_CODEC"
}

get_audio_codec() {
    echo
    echo -e "${BLUE}Select Audio Codec:${NC}"
    echo "1) AAC - Widely compatible, good quality"
    echo "2) Opus - Superior quality, lower bitrate"
    echo
    
    while true; do
        read -p "Enter choice [1-2]: " choice
        case "$choice" in
            1) AUDIO_CODEC="aac"; break ;;
            2) AUDIO_CODEC="opus"; break ;;
            *) echo "Invalid choice. Please enter 1-2." ;;
        esac
    done
    
    log_info "INPUT" "Selected audio codec: $AUDIO_CODEC"
}

get_bitrate() {
    echo
    echo -e "${BLUE}Stream Bitrate Configuration:${NC}"
    echo "Recommended range for $RESOLUTION: ${MIN_BITRATE}-${MAX_BITRATE} kbps"
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
    
    log_info "INPUT" "Set connections: $NUM_CONNECTIONS (all streams start simultaneously)"
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
    cmd+=" -f lavfi -i testsrc2=size=${VIDEO_WIDTH}x${VIDEO_HEIGHT}:rate=30"
    cmd+=" -f lavfi -i sine=frequency=1000:sample_rate=48000"
    
    # Map both input streams (video from input 0, audio from input 1)
    cmd+=" -map 0:v -map 1:a"
    
    # Video encoding based on selected codec
    if [[ "$VIDEO_CODEC" == "h265" ]]; then
        cmd+=" -c:v libx265 -preset veryfast -b:v ${BITRATE}k -g 60 -keyint_min 60 -x265-params keyint=60:min-keyint=60"
    else
        # H.264 encoding with Wowza-compatible settings
        # Select appropriate level based on resolution
        local h264_level="3.1"  # Default for 720p and below
        case "${RESOLUTION,,}" in
            "4k")
                h264_level="5.1"  # Required for 4K (3840x2160)
                ;;
            "1080p")
                h264_level="4.0"  # Optimal for 1080p
                ;;
            "720p")
                h264_level="3.1"  # Standard for 720p
                ;;
            "360p")
                h264_level="3.0"  # Sufficient for 360p
                ;;
        esac
        
        cmd+=" -c:v libx264 -preset veryfast -profile:v baseline -level ${h264_level} -pix_fmt yuv420p"
        cmd+=" -b:v ${BITRATE}k -g 60 -keyint_min 60 -sc_threshold 0"
        cmd+=" -x264-params keyint=60:min-keyint=60:no-scenecut"
    fi
    
    # Audio encoding based on selected codec
    if [[ "$AUDIO_CODEC" == "opus" ]]; then
        cmd+=" -c:a libopus -b:a 128k"
    else
        cmd+=" -c:a aac -b:a 128k"
    fi
    
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
    cmd+=" -f lavfi -i testsrc2=size=${VIDEO_WIDTH}x${VIDEO_HEIGHT}:rate=30"
    cmd+=" -f lavfi -i sine=frequency=1000:sample_rate=48000"
    
    # Video encoding based on selected codec
    if [[ "$VIDEO_CODEC" == "h265" ]]; then
        cmd+=" -c:v libx265 -preset veryfast -b:v ${BITRATE}k -g 60 -keyint_min 60 -x265-params keyint=60:min-keyint=60"
    else
        # H.264 encoding with Wowza-compatible settings
        # Select appropriate level based on resolution
        local h264_level="3.1"  # Default for 720p and below
        case "${RESOLUTION,,}" in
            "4k")
                h264_level="5.1"  # Required for 4K (3840x2160)
                ;;
            "1080p")
                h264_level="4.0"  # Optimal for 1080p
                ;;
            "720p")
                h264_level="3.1"  # Standard for 720p
                ;;
            "360p")
                h264_level="3.0"  # Sufficient for 360p
                ;;
        esac
        
        cmd+=" -c:v libx264 -preset veryfast -profile:v baseline -level ${h264_level} -pix_fmt yuv420p"
        cmd+=" -b:v ${BITRATE}k -g 60 -keyint_min 60 -sc_threshold 0"
        cmd+=" -x264-params keyint=60:min-keyint=60:no-scenecut"
    fi
    
    # Audio encoding based on selected codec
    if [[ "$AUDIO_CODEC" == "opus" ]]; then
        cmd+=" -c:a libopus -b:a 128k"
    else
        cmd+=" -c:a aac -b:a 128k"
    fi
    
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
    
    # Use FFmpeg for all protocols - single stream mode
    local ffmpeg_cmd=$(build_single_stream_ffmpeg_command "$stream_name")
    log_info "STREAM-${padded_number}" "Starting stream: $stream_name"
    log_debug "STREAM-${padded_number}" "Command: $ffmpeg_cmd"
    
    # Start ffmpeg in background and capture its PID
    eval "$ffmpeg_cmd" </dev/null &
    local pid=$!
    
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
    
    # Use single FFmpeg process with multiple outputs for efficiency
    log_info "MAIN" "Starting load test: $NUM_CONNECTIONS ${PROTOCOL^^} streams (single encode, multiple outputs)"
    log_info "MAIN" "Using efficient single-process mode to reduce CPU usage"
    
    if ! start_multi_output_stream; then
        log_error "MAIN" "Failed to start multi-output stream"
        return 1
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
        if (( running_count > 0 )); then
            log_info "MONITOR" "FFmpeg process running, ${NUM_CONNECTIONS} streams active, Time remaining: ${remaining_time}s"
        else
            log_warn "MONITOR" "FFmpeg process ended prematurely"
            break
        fi
    done
    
    log_info "MAIN" "Test duration completed"
    log_debug "MONITOR" "Exiting monitor_test() normally"
}

#############################################################################
# Previous Run Management
#############################################################################

generate_config_name() {
    # Generate automatic name based on test configuration
    local proto="${PROTOCOL^^}"
    local res="${RESOLUTION}"
    local vcodec="${VIDEO_CODEC^^}"
    local acodec="${AUDIO_CODEC^^}"
    local bitrate="${BITRATE}k"
    local connections="${NUM_CONNECTIONS}conn"
    
    echo "${proto}_${res}_${vcodec}_${acodec}_${bitrate}_${connections}"
}

save_test_configuration() {
    echo
    echo -e "${CYAN}=============================================================="
    echo "                 SAVE TEST CONFIGURATION"
    echo "==============================================================${NC}"
    echo
    echo "Would you like to save this test configuration for future use? (y/N)"
    read -r save_response
    
    if [[ ! "$save_response" =~ ^[Yy] ]]; then
        log_info "MAIN" "Configuration not saved"
        return
    fi
    
    # Create previous_runs directory if it doesn't exist
    mkdir -p "$PREVIOUS_RUNS_DIR"
    
    # Generate automatic name
    local auto_name=$(generate_config_name)
    
    echo
    echo "Auto-generated name: ${CYAN}${auto_name}${NC}"
    echo "Would you like to append custom text? (Leave empty to use auto-generated name)"
    echo -n "Custom suffix: "
    read -r custom_suffix
    
    local final_name="${auto_name}"
    if [[ -n "$custom_suffix" ]]; then
        # Remove spaces and special chars from custom suffix
        custom_suffix=$(echo "$custom_suffix" | tr -s ' ' '_' | tr -cd '[:alnum:]_-')
        final_name="${auto_name}_${custom_suffix}"
    fi
    
    local config_file="${PREVIOUS_RUNS_DIR}/${final_name}.conf"
    
    # Check if file already exists
    if [[ -f "$config_file" ]]; then
        echo -e "${YELLOW}Configuration '${final_name}' already exists.${NC}"
        echo "Overwrite? (y/N)"
        read -r overwrite_response
        if [[ ! "$overwrite_response" =~ ^[Yy] ]]; then
            log_info "MAIN" "Configuration not saved"
            return
        fi
    fi
    
    # Save configuration
    cat > "$config_file" <<EOF
# Stream Load Tester Configuration
# Saved: $(date '+%Y-%m-%d %H:%M:%S')

PROTOCOL="$PROTOCOL"
RESOLUTION="$RESOLUTION"
VIDEO_CODEC="$VIDEO_CODEC"
AUDIO_CODEC="$AUDIO_CODEC"
BITRATE="$BITRATE"
SERVER_URL="$SERVER_URL"
NUM_CONNECTIONS="$NUM_CONNECTIONS"
STREAM_NAME="$STREAM_NAME"
DURATION="$DURATION"
EOF
    
    echo
    log_info "MAIN" "Configuration saved as: ${final_name}"
    echo -e "${GREEN}Saved to: ${config_file}${NC}"
}

list_previous_runs() {
    if [[ ! -d "$PREVIOUS_RUNS_DIR" ]]; then
        return 1
    fi
    
    local configs=("$PREVIOUS_RUNS_DIR"/*.conf)
    
    # Check if any configs exist
    if [[ ! -f "${configs[0]}" ]]; then
        return 1
    fi
    
    return 0
}

show_previous_runs_menu() {
    echo
    echo -e "${CYAN}=============================================================="
    echo "                  PREVIOUS TEST RUNS"
    echo "==============================================================${NC}"
    echo
    
    local configs=("$PREVIOUS_RUNS_DIR"/*.conf)
    local config_names=()
    
    for config in "${configs[@]}"; do
        if [[ -f "$config" ]]; then
            local basename=$(basename "$config" .conf)
            config_names+=("$basename")
        fi
    done
    
    if [[ ${#config_names[@]} -eq 0 ]]; then
        echo "No previous runs found."
        return 1
    fi
    
    echo "Found ${#config_names[@]} previous test configuration(s):"
    echo
    
    for i in "${!config_names[@]}"; do
        echo "  $((i+1)). ${config_names[$i]}"
    done
    
    echo
    echo "  0. Start new test"
    echo
    echo -n "Select a configuration (0-${#config_names[@]}): "
    read -r selection
    
    if [[ "$selection" == "0" ]]; then
        return 1
    fi
    
    if [[ ! "$selection" =~ ^[0-9]+$ ]] || (( selection < 1 || selection > ${#config_names[@]} )); then
        echo -e "${RED}Invalid selection${NC}"
        return 1
    fi
    
    local selected_config="${config_names[$((selection-1))]}"
    load_and_run_configuration "$selected_config"
    return 0
}

load_and_run_configuration() {
    local config_name="$1"
    local config_file="${PREVIOUS_RUNS_DIR}/${config_name}.conf"
    
    if [[ ! -f "$config_file" ]]; then
        log_error "MAIN" "Configuration file not found: $config_file"
        return 1
    fi
    
    echo
    echo -e "${CYAN}=============================================================="
    echo "              CONFIGURATION PREVIEW"
    echo "==============================================================${NC}"
    
    # Load configuration
    source "$config_file"
    
    # Calculate VIDEO_WIDTH and VIDEO_HEIGHT from RESOLUTION
    case "${RESOLUTION,,}" in
        "4k")
            VIDEO_WIDTH=3840
            VIDEO_HEIGHT=2160
            ;;
        "1080p")
            VIDEO_WIDTH=1920
            VIDEO_HEIGHT=1080
            ;;
        "720p")
            VIDEO_WIDTH=1280
            VIDEO_HEIGHT=720
            ;;
        "360p")
            VIDEO_WIDTH=640
            VIDEO_HEIGHT=360
            ;;
    esac
    
    # Display configuration
    echo "Protocol:           $PROTOCOL"
    echo "Resolution:         $RESOLUTION (${VIDEO_WIDTH}x${VIDEO_HEIGHT})"
    echo "Video Codec:        $VIDEO_CODEC"
    echo "Audio Codec:        $AUDIO_CODEC"
    echo "Bitrate:            ${BITRATE}k"
    echo "Connections:        $NUM_CONNECTIONS"
    echo "Duration:           ${DURATION}m"
    echo
    echo "Server URL:         $SERVER_URL"
    echo "Stream Name:        $STREAM_NAME"
    echo -e "${CYAN}==============================================================${NC}"
    
    echo
    echo "Options:"
    echo "  1. Run with these settings"
    echo "  2. Change server URL, app name, and stream name"
    echo "  0. Cancel"
    echo
    echo -n "Select option (0-2): "
    read -r option
    
    case "$option" in
        1)
            # Run with existing settings
            log_info "MAIN" "Running test with saved configuration: $config_name"
            ;;
        2)
            # Modify server details
            echo
            echo -e "${CYAN}Update Server Configuration${NC}"
            echo
            
            # Get new server URL based on protocol
            case "${PROTOCOL,,}" in
                "rtmp")
                    echo "Enter new RTMP server URL (format: rtmp://server:port/application)"
                    echo "Current: $SERVER_URL"
                    echo -n "New URL (press Enter to keep current): "
                    read -r new_url
                    if [[ -n "$new_url" ]]; then
                        SERVER_URL="$new_url"
                    fi
                    ;;
                "rtsp")
                    echo "Enter new RTSP server URL (format: rtsp://server:port/application)"
                    echo "Current: $SERVER_URL"
                    echo -n "New URL (press Enter to keep current): "
                    read -r new_url
                    if [[ -n "$new_url" ]]; then
                        SERVER_URL="$new_url"
                    fi
                    ;;
                "srt")
                    echo "Enter new SRT server URL (format: srt://server:port?streamid=application)"
                    echo "Current: $SERVER_URL"
                    echo -n "New URL (press Enter to keep current): "
                    read -r new_url
                    if [[ -n "$new_url" ]]; then
                        SERVER_URL="$new_url"
                    fi
                    ;;
            esac
            
            echo
            echo "Enter new stream name"
            echo "Current: $STREAM_NAME"
            echo -n "New stream name (press Enter to keep current): "
            read -r new_stream
            if [[ -n "$new_stream" ]]; then
                STREAM_NAME="$new_stream"
            fi
            
            echo
            log_info "MAIN" "Updated configuration:"
            log_info "MAIN" "  Server URL: $SERVER_URL"
            log_info "MAIN" "  Stream Name: $STREAM_NAME"
            ;;
        0)
            log_info "MAIN" "Test cancelled"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid option${NC}"
            exit 1
            ;;
    esac
    
    # Set START_TIME and create log file
    START_TIME=$(date +%s)
    LOG_FILE="$LOG_DIR/stream_test_$(date +%Y%m%d_%H%M%S).log"
    mkdir -p "$LOG_DIR"
    touch "$LOG_FILE"
    
    echo
    log_info "MAIN" "Starting test from saved configuration: $config_name"
}

print_summary() {
    local end_time=$(date +%s)
    local total_time=$((end_time - START_TIME))
    
    echo
    echo -e "${CYAN}=============================================================="
    echo "                    TEST SUMMARY"
    echo "==============================================================${NC}"
    echo "Protocol:           $PROTOCOL"
    echo "Resolution:         $RESOLUTION (${VIDEO_WIDTH}x${VIDEO_HEIGHT})"
    echo "Video Codec:        $VIDEO_CODEC"
    echo "Audio Codec:        $AUDIO_CODEC"
    echo "Server URL:         $SERVER_URL"
    echo "Stream Name:        $STREAM_NAME"
    echo "Bitrate:            ${BITRATE}k"
    echo "Connections:        $NUM_CONNECTIONS"
    
    # Show encoding mode info
    echo "Encoding Mode:      Single process (1 encode, ${NUM_CONNECTIONS} outputs)"
    echo "Stream Start:       All streams start simultaneously"
    
    echo "Test Duration:      ${DURATION}m"
    echo "Actual Runtime:     ${total_time}s"
    echo "Log File:           $LOG_FILE"
    echo -e "${CYAN}==============================================================${NC}"
}

#############################################################################
# Command Line Argument Parsing
#############################################################################

show_help() {
    echo "Stream Load Tester v2.0"
    echo
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  -p, --protocol PROTOCOL     Protocol to use (rtmp, rtsp, srt)"
    echo "  -r, --resolution RES        Resolution (4k, 1080p, 720p, 360p) (default: $DEFAULT_RESOLUTION)"
    echo "  --video-codec CODEC         Video codec (h264, h265) (default: $DEFAULT_VIDEO_CODEC)"
    echo "  --audio-codec CODEC         Audio codec (aac, opus) (default: $DEFAULT_AUDIO_CODEC)"
    echo "  -b, --bitrate BITRATE       Bitrate in kbps (default: varies by resolution)"
    echo "  -u, --url URL               Server URL with application (format depends on protocol)"
    echo "  -c, --connections COUNT     Number of connections (default: $DEFAULT_CONNECTIONS)"
    echo "  -s, --stream-name NAME      Base stream name (numbers will be appended)"
    echo "  -d, --duration MINUTES      Test duration in minutes (default: $DEFAULT_DURATION)"
    echo "  -l, --log-level LEVEL       Log level (DEBUG, INFO, WARN, ERROR)"
    echo "  --debug                     Enable debug mode"
    echo "  -h, --help                  Show this help message"
    echo "  -v, --version               Show version information"
    echo
    echo "Resolution Bitrate Recommendations:"
    echo "  4K (3840x2160):     H.264: 10000-25000 kbps, H.265: 5000-15000 kbps"
    echo "  1080p (1920x1080):  H.264: 3000-8000 kbps,   H.265: 1500-5000 kbps"
    echo "  720p (1280x720):    H.264: 1500-4000 kbps,   H.265: 800-2500 kbps"
    echo "  360p (640x360):     H.264: 500-1500 kbps,    H.265: 300-1000 kbps"
    echo "  (Tool accepts 200-50000 kbps for maximum flexibility)"
    echo
    echo "URL Formats by Protocol:"
    echo "  RTMP:   rtmp://server:port/application"
    echo "  RTSP:   rtsp://server:port/application"
    echo "  SRT:    srt://server:port?streamid=application (Wowza format used automatically)"
    echo
    echo "Note: SRT streams will be published using Wowza's format:"
    echo "      srt://server:port?streamid=#!::m=publish,r=application/_definst_/stream-name"
    echo
    echo "Examples:"
    echo "  # Interactive mode"
    echo "  $0"
    echo
    echo "  # Command line mode - RTMP with 4K H.265"
    echo "  $0 --protocol rtmp --resolution 4k --video-codec h265 --audio-codec opus \\"
    echo "     --bitrate 12000 --url 'rtmp://192.168.1.100:1935/live' \\"
    echo "     --connections 10 --stream-name 'test' --duration 30"
    echo
    echo "  # Command line mode - SRT (provide application name, Wowza format applied automatically)"
    echo "  $0 --protocol srt --bitrate 3000 --url 'srt://192.168.1.100:9999?streamid=live' \\"
    echo "     --connections 5 --stream-name 'stream' --duration 60"
}

show_version() {
    echo "Stream Load Tester v2.0"
    echo "Multi-Protocol Stream Publishing Tool"
    echo "October 16, 2025"
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
            -s|--stream-name)
                STREAM_NAME="$2"
                shift 2
                ;;
            -d|--duration)
                DURATION="$2"
                shift 2
                ;;
            -r|--resolution)
                RESOLUTION="$2"
                shift 2
                ;;
            --video-codec)
                VIDEO_CODEC="$2"
                shift 2
                ;;
            --audio-codec)
                AUDIO_CODEC="$2"
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
    
    # Check dependencies first
    log_info "MAIN" "Checking dependencies..."
    
    if ! "${SCRIPTS_DIR}/check_dependencies.sh" >/dev/null 2>&1; then
        log_warn "MAIN" "Dependencies not met. Running installation script..."
        echo
        echo -e "${YELLOW}Dependencies are missing or incomplete.${NC}"
        echo -e "${YELLOW}Running automatic installation...${NC}"
        echo
        
        # Run installation script with auto-confirm
        if ! "${SCRIPTS_DIR}/install.sh" --yes 2>&1 | tee -a "$LOG_FILE"; then
            log_error "MAIN" "Installation failed"
            log_error "MAIN" "Please run './scripts/install.sh' manually or install dependencies yourself"
            exit 1
        fi
        
        echo
        log_info "MAIN" "Installation completed successfully"
        
        # Re-check dependencies after installation
        if ! "${SCRIPTS_DIR}/check_dependencies.sh" >/dev/null 2>&1; then
            log_error "MAIN" "Dependencies still not met after installation"
            log_error "MAIN" "Please check the error messages above and install missing dependencies manually"
            exit 1
        fi
    fi
    
    log_info "MAIN" "All dependencies verified"
    
    # Ensure FFmpeg requirements are met (double-check)
    log_info "MAIN" "Verifying FFmpeg configuration..."
    
    if ! "${SCRIPTS_DIR}/ensure_ffmpeg_requirements.sh" --quiet 2>&1 | tee -a "$LOG_FILE"; then
        log_error "MAIN" "Failed to ensure FFmpeg requirements"
        log_error "MAIN" "Please install FFmpeg with H.264 and AAC support manually"
        exit 1
    fi
    
    log_info "MAIN" "FFmpeg configuration verified"
    
    # Check for previous runs (only if no command line args provided)
    if [[ -z "$PROTOCOL" ]]; then
        if list_previous_runs; then
            if show_previous_runs_menu; then
                # Configuration was loaded and will be executed
                # Skip interactive mode
                PROTOCOL="${PROTOCOL}" # Already set by load_and_run_configuration
            fi
        fi
    fi
    
    # If running in interactive mode, get user input
    if [[ -z "$PROTOCOL" ]]; then
        select_protocol
        get_resolution
        get_video_codec
        get_audio_codec
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
        RESOLUTION="${RESOLUTION:-$DEFAULT_RESOLUTION}"
        VIDEO_CODEC="${VIDEO_CODEC:-$DEFAULT_VIDEO_CODEC}"
        AUDIO_CODEC="${AUDIO_CODEC:-$DEFAULT_AUDIO_CODEC}"
        
        # Set resolution-dependent values
        case "$RESOLUTION" in
            "4k")
                VIDEO_WIDTH=3840
                VIDEO_HEIGHT=2160
                MIN_BITRATE=3000
                MAX_BITRATE=50000
                BITRATE="${BITRATE:-12000}"
                ;;
            "1080p")
                VIDEO_WIDTH=1920
                VIDEO_HEIGHT=1080
                MIN_BITRATE=1000
                MAX_BITRATE=15000
                BITRATE="${BITRATE:-4000}"
                ;;
            "720p")
                VIDEO_WIDTH=1280
                VIDEO_HEIGHT=720
                MIN_BITRATE=500
                MAX_BITRATE=8000
                BITRATE="${BITRATE:-2000}"
                ;;
            "360p")
                VIDEO_WIDTH=640
                VIDEO_HEIGHT=360
                MIN_BITRATE=200
                MAX_BITRATE=3000
                BITRATE="${BITRATE:-800}"
                ;;
            *)
                log_error "MAIN" "Invalid resolution: $RESOLUTION. Must be 4k, 1080p, 720p, or 360p"
                exit 1
                ;;
        esac
        
        # Validate video codec
        if [[ "$VIDEO_CODEC" != "h264" && "$VIDEO_CODEC" != "h265" ]]; then
            log_error "MAIN" "Invalid video codec: $VIDEO_CODEC. Must be h264 or h265"
            exit 1
        fi
        
        # Validate audio codec
        if [[ "$AUDIO_CODEC" != "aac" && "$AUDIO_CODEC" != "opus" ]]; then
            log_error "MAIN" "Invalid audio codec: $AUDIO_CODEC. Must be aac or opus"
            exit 1
        fi
        
        NUM_CONNECTIONS="${NUM_CONNECTIONS:-$DEFAULT_CONNECTIONS}"
        DURATION="${DURATION:-$DEFAULT_DURATION}"
        
        # Validate all parameters
        validate_number "$BITRATE" "$MIN_BITRATE" "$MAX_BITRATE" "Bitrate" || exit 1
        validate_number "$NUM_CONNECTIONS" 1 "$MAX_CONNECTIONS" "Number of connections" || exit 1
        validate_number "$DURATION" 1 1440 "Duration" || exit 1
        validate_url "$SERVER_URL" "$PROTOCOL" || exit 1
    fi
    
    # Show configuration summary
    echo
    echo -e "${YELLOW}Configuration Summary:${NC}"
    echo "Protocol:           $PROTOCOL"
    echo "Resolution:         $RESOLUTION (${VIDEO_WIDTH}x${VIDEO_HEIGHT})"
    echo "Video Codec:        $VIDEO_CODEC"
    echo "Audio Codec:        $AUDIO_CODEC"
    echo "Bitrate:            ${BITRATE}k"
    echo "Server URL:         $SERVER_URL"
    echo "Connections:        $NUM_CONNECTIONS (start simultaneously)"
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
    
    # Offer to save configuration
    save_test_configuration
    
    # Note: cleanup() will be called automatically via the EXIT trap
    # For orphaned processes from crashes/disconnects, use: ./scripts/cleanup.sh
}

# Execute main function with all arguments
main "$@"