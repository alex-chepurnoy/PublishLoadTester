#!/bin/bash

#############################################################################
# Dependency Checker for Stream Load Tester
# 
# Description: Validates required dependencies for the stream load tester
#              (Bash and FFmpeg with required codecs)
#
# Usage: ./scripts/check_dependencies.sh
#
# Author: Stream Load Tester Project
# Version: 3.0
# Date: October 16, 2025
#############################################################################

# Note: We use -u (error on unset vars) but NOT -e or -o pipefail
# because this is a checking script that needs to gracefully handle
# command failures and report them, not exit immediately.
set -u

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
FFMPEG_HELPERS="$SCRIPT_DIR/lib/ffmpeg_checks.sh"

if [[ ! -f "$FFMPEG_HELPERS" ]]; then
    echo -e "${RED}Missing FFmpeg helper library at $FFMPEG_HELPERS${NC}"
    exit 1
fi

# shellcheck disable=SC1091
source "$FFMPEG_HELPERS"

# Dependency check results
BASIC_DEPS_OK=true

# Failure collectors (store human-readable failure messages)
BASIC_FAILURES=()

#############################################################################
# Utility Functions
#############################################################################

print_status() {
    local component="$1"
    local status="$2"
    local message="$3"
    
    if [[ "$status" == "OK" ]]; then
        echo -e "  ${GREEN}[✓]${NC} $component: $message"
    elif [[ "$status" == "WARN" ]]; then
        echo -e "  ${YELLOW}[!]${NC} $component: $message"
    else
        echo -e "  ${RED}[✗]${NC} $component: $message"
    fi
}

check_command() {
    local cmd="$1"
    local package="$2"
    
    if command -v "$cmd" >/dev/null 2>&1; then
        return 0
    else
        echo -e "${RED}Command '$cmd' not found.${NC}"
        echo -e "${YELLOW}Please install: $package${NC}"
        return 1
    fi
}

get_version() {
    local cmd="$1"
    local version_flag="$2"
    
    # If ffmpeg helper has set a specific binary, prefer that for ffmpeg queries
    if [[ "$cmd" == "ffmpeg" && -n "${FFMPEG_BIN:-}" ]]; then
        "${FFMPEG_BIN}" $version_flag 2>&1 | head -n 1 || echo "Unknown version"
        return
    fi

    if command -v "$cmd" >/dev/null 2>&1; then
        $cmd $version_flag 2>&1 | head -n 1 || echo "Unknown version"
    else
        echo "Not installed"
    fi
}

#############################################################################
# Basic Dependency Checks
#############################################################################

check_bash() {
    echo -e "${BLUE}Checking Bash...${NC}"
    
    # Check bash version
    if [[ -n "${BASH_VERSION:-}" ]]; then
        local major_version=$(echo "$BASH_VERSION" | cut -d. -f1)
        if (( major_version >= 4 )); then
            print_status "Bash" "OK" "Version $BASH_VERSION"
        else
            print_status "Bash" "ERROR" "Version $BASH_VERSION (requires 4.0+)"
            BASIC_DEPS_OK=false
            BASIC_FAILURES+=("Bash: Version $BASH_VERSION (requires 4.0+)")
        fi
    else
        print_status "Bash" "ERROR" "Not running in Bash shell"
        BASIC_DEPS_OK=false
        BASIC_FAILURES+=("Bash: Not running in Bash shell")
    fi
}

check_python() {
    echo -e "${BLUE}Checking Python3...${NC}"
    
    if command -v python3 >/dev/null 2>&1; then
        local version=$(python3 --version 2>&1 || echo "Unknown version")
        print_status "Python3" "OK" "$version"
    else
        print_status "Python3" "ERROR" "Not installed (required for orchestrator)"
        BASIC_DEPS_OK=false
        BASIC_FAILURES+=("Python3: Not installed (required for result parsing)")
        echo -e "${YELLOW}    Required for: Orchestrator result parsing and CSV generation${NC}"
        echo -e "${YELLOW}    Fix: Run ./scripts/install.sh --yes${NC}"
    fi
}

check_ffmpeg() {
    echo -e "${BLUE}Checking FFmpeg...${NC}"
    
    if ffmpeg_is_available; then
        local version=$(get_version "ffmpeg" "-version")
        print_status "FFmpeg" "OK" "$version"
        
        # Check for required codecs
        echo "  Checking codecs..."
        ffmpeg_reset_capability_cache
        
        ffmpeg_has_any_encoder "${FFMPEG_H264_ENCODERS[@]}"
        local h264_status=$?
        case $h264_status in
            0)
                print_status "  H.264 encoder" "OK" "Available"
                ;;
            1)
                print_status "  H.264 encoder" "ERROR" "Not available"
                echo -e "${YELLOW}    Fix: Run ./scripts/ensure_ffmpeg_requirements.sh${NC}"
                BASIC_DEPS_OK=false
                ;;
            *)
                print_status "  H.264 encoder" "WARN" "Unable to determine availability"
                echo -e "${YELLOW}    Run ./scripts/ensure_ffmpeg_requirements.sh${NC}"
                ;;
        esac
        
        # Check for H.265 encoder (optional but recommended)
        ffmpeg_has_any_encoder "${FFMPEG_H265_ENCODERS[@]}"
        local h265_status=$?
        case $h265_status in
            0)
                print_status "  H.265 encoder" "OK" "Available"
                ;;
            1)
                print_status "  H.265 encoder" "WARN" "Not available (optional)"
                echo -e "${YELLOW}    Note: H.265 support recommended for better compression${NC}"
                ;;
            *)
                print_status "  H.265 encoder" "WARN" "Unable to determine availability"
                ;;
        esac
        
        # Check for VP9 encoder (optional but recommended)
        ffmpeg_has_any_encoder "${FFMPEG_VP9_ENCODERS[@]}"
        local vp9_status=$?
        case $vp9_status in
            0)
                print_status "  VP9 encoder" "OK" "Available"
                ;;
            1)
                print_status "  VP9 encoder" "WARN" "Not available (optional)"
                echo -e "${YELLOW}    Note: VP9 support recommended for open-source codec testing${NC}"
                ;;
            *)
                print_status "  VP9 encoder" "WARN" "Unable to determine availability"
                ;;
        esac

        ffmpeg_has_any_encoder "${FFMPEG_AAC_ENCODERS[@]}"
        local aac_status=$?
        case $aac_status in
            0)
                print_status "  AAC encoder" "OK" "Available"
                ;;
            1)
                print_status "  AAC encoder" "ERROR" "Not available"
                echo -e "${YELLOW}    Fix: Run ./scripts/ensure_ffmpeg_requirements.sh${NC}"
                BASIC_DEPS_OK=false
                ;;
            *)
                print_status "  AAC encoder" "WARN" "Unable to determine availability"
                echo -e "${YELLOW}    Run ./scripts/ensure_ffmpeg_requirements.sh${NC}"
                ;;
        esac
        
        # Check for Opus encoder (optional but recommended)
        ffmpeg_has_any_encoder "libopus"
        local opus_status=$?
        case $opus_status in
            0)
                print_status "  Opus encoder" "OK" "Available"
                ;;
            1)
                print_status "  Opus encoder" "WARN" "Not available (optional)"
                echo -e "${YELLOW}    Note: Opus support recommended for better audio quality${NC}"
                ;;
            *)
                print_status "  Opus encoder" "WARN" "Unable to determine availability"
                ;;
        esac

        ffmpeg_has_any_filter "${FFMPEG_TESTSRC_FILTERS[@]}"
        local testsrc_status=$?
        case $testsrc_status in
            0)
                print_status "  Test sources" "OK" "testsrc2 available"
                ;;
            1)
                print_status "  Test sources" "WARN" "testsrc2 not available"
                ;;
            *)
                print_status "  Test sources" "WARN" "Unable to determine availability"
                ;;
        esac

        ffmpeg_has_any_filter "${FFMPEG_SINE_FILTERS[@]}"
        local sine_status=$?
        case $sine_status in
            0)
                print_status "  Audio generator" "OK" "sine available"
                ;;
            1)
                print_status "  Audio generator" "ERROR" "sine generator not available"
                echo -e "${YELLOW}    Fix: Run ./scripts/ensure_ffmpeg_requirements.sh${NC}"
                BASIC_DEPS_OK=false
                ;;
            *)
                print_status "  Audio generator" "WARN" "Unable to determine availability"
                echo -e "${YELLOW}    Run ./scripts/ensure_ffmpeg_requirements.sh${NC}"
                ;;
        esac
        
    else
        print_status "FFmpeg" "ERROR" "Not installed"
        echo -e "${YELLOW}Install with: ./scripts/ensure_ffmpeg_requirements.sh${NC}"
        BASIC_DEPS_OK=false
        BASIC_FAILURES+=("FFmpeg: Not installed")
    fi
}

check_basic_tools() {
    echo -e "${BLUE}Checking basic tools...${NC}"
    
    # Check essential tools
    local tools=("grep" "awk" "sed" "cut" "head" "tail" "date" "sleep" "kill")
    
    for tool in "${tools[@]}"; do
        if command -v "$tool" >/dev/null 2>&1; then
            print_status "$tool" "OK" "Available"
        else
            print_status "$tool" "ERROR" "Not available"
            BASIC_DEPS_OK=false
            BASIC_FAILURES+=("$tool: Not available")
        fi
    done
}

#############################################################################
# System Checks
#############################################################################

check_system_resources() {
    echo -e "${BLUE}Checking system resources...${NC}"
    
    # Check available memory
    if command -v free >/dev/null 2>&1; then
        local mem_gb=$(free -g | awk '/^Mem:/{print $2}')
        if (( mem_gb >= 2 )); then
            print_status "Memory" "OK" "${mem_gb}GB available"
        else
            print_status "Memory" "WARN" "${mem_gb}GB available (recommended: 2GB+)"
        fi
    else
        print_status "Memory" "WARN" "Cannot check memory"
    fi
    
    # Check disk space
    if command -v df >/dev/null 2>&1; then
        local disk_gb=$(df -BG . | awk 'NR==2{print $4}' | sed 's/G//')
        if (( disk_gb >= 1 )); then
            print_status "Disk space" "OK" "${disk_gb}GB available"
        else
            print_status "Disk space" "WARN" "${disk_gb}GB available (recommended: 1GB+)"
        fi
    else
        print_status "Disk space" "WARN" "Cannot check disk space"
    fi
    
    # Check CPU cores
    if command -v nproc >/dev/null 2>&1; then
        local cores=$(nproc)
        print_status "CPU cores" "OK" "$cores cores available"
    else
        print_status "CPU cores" "WARN" "Cannot check CPU cores"
    fi
}

#############################################################################
# Main Functions
#############################################################################

check_basic_dependencies() {
    echo -e "${GREEN}=== Checking Dependencies ===${NC}"
    echo
    
    check_bash
    echo
    check_python
    echo
    check_ffmpeg
    echo
    check_basic_tools
    echo
    check_system_resources
}

print_summary() {
    echo
    echo -e "${GREEN}=== Dependency Check Summary ===${NC}"
    echo
    
    if [[ "$BASIC_DEPS_OK" == "true" ]]; then
        print_status "All dependencies" "OK" "All requirements met"
    else
        print_status "Dependencies" "ERROR" "Some requirements missing"
        # Print exact failures
        if (( ${#BASIC_FAILURES[@]} > 0 )); then
            echo
            echo "  Failures:"
            for f in "${BASIC_FAILURES[@]}"; do
                echo "    - $f"
            done
        fi
    fi
}

show_help() {
    echo "Dependency Checker for Stream Load Tester"
    echo
    echo "Usage: $0"
    echo
    echo "This script checks for:"
    echo "  - Bash 4.0+"
    echo "  - Python 3 (for orchestrator result parsing)"
    echo "  - FFmpeg with H.264 and AAC encoders (required)"
    echo "  - FFmpeg with H.265 and Opus encoders (optional)"
    echo "  - FFmpeg with testsrc2 and sine filters"
    echo "  - Basic system tools"
    echo
    echo "Exit codes:"
    echo "  0 - All dependencies are satisfied"
    echo "  1 - Some dependencies are missing"
}

main() {
    local check_type="${1:-all}"
    
    case "$check_type" in
        "help"|"-h"|"--help")
            show_help
            exit 0
            ;;
        "all"|"basic"|"")
            check_basic_dependencies
            print_summary
            
            echo
            if [[ "$BASIC_DEPS_OK" == "true" ]]; then
                echo -e "${GREEN}✓ All dependencies check passed${NC}"
                echo -e "${GREEN}  Stream Load Tester is ready to use!${NC}"
                exit 0
            else
                echo -e "${RED}✗ Dependencies check failed${NC}"
                echo
                echo -e "${YELLOW}To fix missing dependencies, run:${NC}"
                echo -e "${YELLOW}  ./scripts/ensure_ffmpeg_requirements.sh${NC}"
                exit 1
            fi
            ;;
        *)
            echo "Invalid option: $check_type"
            show_help
            exit 2
            ;;
    esac
}

# Execute main function
main "$@"