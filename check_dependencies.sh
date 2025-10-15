#!/bin/bash

#############################################################################
# Dependency Checker for Stream Load Tester
# 
# Description: Validates all required dependencies for the stream load tester
#              including FFmpeg, Python, GStreamer, and WebRTC components
#
# Usage: ./check_dependencies.sh [basic|webrtc|all]
#        basic  - Check basic dependencies (FFmpeg, bash)
#        webrtc - Check WebRTC specific dependencies
#        all    - Check all dependencies
#
# Author: Stream Load Tester Project
# Version: 1.0
# Date: October 15, 2025
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

PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
FFMPEG_HELPERS="$PROJECT_ROOT/scripts/lib/ffmpeg_checks.sh"

if [[ ! -f "$FFMPEG_HELPERS" ]]; then
    echo -e "${RED}Missing FFmpeg helper library at $FFMPEG_HELPERS${NC}"
    exit 1
fi

# shellcheck disable=SC1091
source "$FFMPEG_HELPERS"

# Dependency check results
BASIC_DEPS_OK=true
WEBRTC_DEPS_OK=true
PYTHON_DEPS_OK=true
GSTREAMER_DEPS_OK=true

# Failure collectors (store human-readable failure messages)
BASIC_FAILURES=()
PYTHON_FAILURES=()
GSTREAMER_FAILURES=()

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
                echo -e "${YELLOW}    Fix: Run ./scripts/fix_ffmpeg_codecs.sh${NC}"
                BASIC_DEPS_OK=false
                ;;
            *)
                print_status "  H.264 encoder" "WARN" "Unable to determine availability"
                echo -e "${YELLOW}    Run ./scripts/fix_ffmpeg_codecs.sh --check-only for details${NC}"
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
                echo -e "${YELLOW}    Fix: Run ./scripts/fix_ffmpeg_codecs.sh${NC}"
                BASIC_DEPS_OK=false
                ;;
            *)
                print_status "  AAC encoder" "WARN" "Unable to determine availability"
                echo -e "${YELLOW}    Run ./scripts/fix_ffmpeg_codecs.sh --check-only for details${NC}"
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
                echo -e "${YELLOW}    Fix: Run ./scripts/fix_ffmpeg_codecs.sh${NC}"
                BASIC_DEPS_OK=false
                ;;
            *)
                print_status "  Audio generator" "WARN" "Unable to determine availability"
                echo -e "${YELLOW}    Run ./scripts/fix_ffmpeg_codecs.sh --check-only for details${NC}"
                ;;
        esac
        
    else
        print_status "FFmpeg" "ERROR" "Not installed"
        echo -e "${YELLOW}Install with: sudo apt install ffmpeg${NC}"
        echo -e "${YELLOW}Or run: ./scripts/fix_ffmpeg_codecs.sh${NC}"
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
# Python Dependency Checks
#############################################################################

check_python() {
    echo -e "${BLUE}Checking Python...${NC}"
    
    if command -v python3 >/dev/null 2>&1; then
        local version=$(get_version "python3" "--version")
        local version_num=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
        
        # Check minimum version (3.6+)
        if python3 -c "import sys; sys.exit(0 if sys.version_info >= (3, 6) else 1)" 2>/dev/null; then
            print_status "Python3" "OK" "$version"
        else
            print_status "Python3" "ERROR" "$version (requires 3.6+)"
            PYTHON_DEPS_OK=false
            PYTHON_FAILURES+=("Python3: Version $version (requires 3.6+)")
        fi
        
        # Check pip
        if command -v pip3 >/dev/null 2>&1; then
            print_status "pip3" "OK" "Available"
        else
            print_status "pip3" "WARN" "Not available (may affect WebRTC)"
            PYTHON_FAILURES+=("pip3: Not available (may affect WebRTC)")
        fi
        
    else
        print_status "Python3" "ERROR" "Not installed"
        echo -e "${YELLOW}Install with: sudo apt install python3 python3-pip${NC}"
        PYTHON_DEPS_OK=false
    fi
}

check_python_webrtc_packages() {
    echo -e "${BLUE}Checking Python WebRTC packages...${NC}"
    
    if ! command -v python3 >/dev/null 2>&1; then
        print_status "Python packages" "ERROR" "Python3 not available"
        PYTHON_DEPS_OK=false
        PYTHON_FAILURES+=("Python3: Not available")
        return
    fi
    
    # Check aiortc
    if python3 -c "import aiortc" 2>/dev/null; then
        local version=$(python3 -c "import aiortc; print(aiortc.__version__)" 2>/dev/null || echo "Unknown")
        print_status "aiortc" "OK" "Version $version"
    else
        print_status "aiortc" "ERROR" "Not installed"
        echo -e "${YELLOW}Install with: pip3 install aiortc${NC}"
        PYTHON_DEPS_OK=false
        PYTHON_FAILURES+=("aiortc: Not installed")
    fi
    
    # Check aiohttp
    if python3 -c "import aiohttp" 2>/dev/null; then
        local version=$(python3 -c "import aiohttp; print(aiohttp.__version__)" 2>/dev/null || echo "Unknown")
        print_status "aiohttp" "OK" "Version $version"
    else
        print_status "aiohttp" "ERROR" "Not installed"
        echo -e "${YELLOW}Install with: pip3 install aiohttp${NC}"
        PYTHON_DEPS_OK=false
        PYTHON_FAILURES+=("aiohttp: Not installed")
    fi
    
    # Check websockets
    if python3 -c "import websockets" 2>/dev/null; then
        local version=$(python3 -c "import websockets; print(websockets.__version__)" 2>/dev/null || echo "Unknown")
        print_status "websockets" "OK" "Version $version"
    else
        print_status "websockets" "ERROR" "Not installed"
        echo -e "${YELLOW}Install with: pip3 install websockets${NC}"
        PYTHON_DEPS_OK=false
        PYTHON_FAILURES+=("websockets: Not installed")
    fi
    
    # Check asyncio (should be built-in)
    if python3 -c "import asyncio" 2>/dev/null; then
        print_status "asyncio" "OK" "Built-in module"
    else
        print_status "asyncio" "ERROR" "Not available (Python issue)"
        PYTHON_DEPS_OK=false
        PYTHON_FAILURES+=("asyncio: Not available (Python issue)")
    fi
}

#############################################################################
# GStreamer Dependency Checks
#############################################################################

check_gstreamer() {
    echo -e "${BLUE}Checking GStreamer...${NC}"
    
    # Check gst-launch
    if command -v gst-launch-1.0 >/dev/null 2>&1; then
        local version=$(get_version "gst-launch-1.0" "--version")
        print_status "GStreamer" "OK" "$version"
    else
        print_status "GStreamer" "ERROR" "Not installed"
        echo -e "${YELLOW}Install with: sudo apt install gstreamer1.0-tools${NC}"
        GSTREAMER_DEPS_OK=false
        return
    fi
    
    # Check gst-inspect
    if command -v gst-inspect-1.0 >/dev/null 2>&1; then
        print_status "gst-inspect" "OK" "Available"
    else
        print_status "gst-inspect" "WARN" "Not available"
    fi
}

check_gstreamer_plugins() {
    echo -e "${BLUE}Checking GStreamer plugins...${NC}"
    
    if ! command -v gst-inspect-1.0 >/dev/null 2>&1; then
        print_status "GStreamer plugins" "ERROR" "gst-inspect not available"
        GSTREAMER_DEPS_OK=false
        return
    fi
    
    # Check core plugins
    local core_plugins=("videotestsrc" "audiotestsrc" "x264enc" "avenc_aac")
    
    for plugin in "${core_plugins[@]}"; do
        if gst-inspect-1.0 "$plugin" >/dev/null 2>&1; then
            print_status "  $plugin" "OK" "Available"
        else
            print_status "  $plugin" "WARN" "Not available"
            GSTREAMER_FAILURES+=("$plugin: Not available")
        fi
    done
    
    # Check WebRTC specific plugins
    local webrtc_plugins=("webrtcbin" "dtlssrtpenc" "dtlssrtpdec" "srtpenc" "srtpdec")
    
    echo "  WebRTC plugins:"
    for plugin in "${webrtc_plugins[@]}"; do
        if gst-inspect-1.0 "$plugin" >/dev/null 2>&1; then
            print_status "    $plugin" "OK" "Available"
        else
            print_status "    $plugin" "ERROR" "Not available"
            echo -e "${YELLOW}    Install with: sudo apt install gstreamer1.0-plugins-bad${NC}"
            GSTREAMER_DEPS_OK=false
            GSTREAMER_FAILURES+=("$plugin: Not available")
        fi
    done
    
    # Check network plugins
    local network_plugins=("udpsrc" "udpsink" "tcpserversrc" "tcpserversink")
    
    echo "  Network plugins:"
    for plugin in "${network_plugins[@]}"; do
        if gst-inspect-1.0 "$plugin" >/dev/null 2>&1; then
            print_status "    $plugin" "OK" "Available"
        else
            print_status "    $plugin" "WARN" "Not available"
            GSTREAMER_FAILURES+=("$plugin: Not available")
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

check_network() {
    echo -e "${BLUE}Checking network capabilities...${NC}"
    
    # Check if we can resolve DNS
    if command -v nslookup >/dev/null 2>&1; then
        if nslookup google.com >/dev/null 2>&1; then
            print_status "DNS resolution" "OK" "Working"
        else
            print_status "DNS resolution" "WARN" "May have issues"
        fi
    else
        print_status "DNS resolution" "WARN" "Cannot test (nslookup not available)"
    fi
    
    # Check common ports availability (basic check)
    local common_ports=("1935" "554" "9999" "8443")
    echo "  Checking if common streaming ports are not in use:"
    
    for port in "${common_ports[@]}"; do
        if command -v netstat >/dev/null 2>&1; then
            if netstat -ln 2>/dev/null | grep -q ":$port "; then
                print_status "    Port $port" "WARN" "In use (may conflict)"
            else
                print_status "    Port $port" "OK" "Available"
            fi
        else
            print_status "    Port checking" "WARN" "netstat not available"
            break
        fi
    done
}

#############################################################################
# Installation Suggestions
#############################################################################

suggest_ubuntu_installation() {
    echo
    echo -e "${BLUE}Ubuntu/Debian Installation Commands:${NC}"
    echo
    echo "# Basic dependencies:"
    echo "sudo apt update"
    echo "sudo apt install ffmpeg gstreamer1.0-tools gstreamer1.0-plugins-good"
    echo "sudo apt install gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly"
    echo
    echo "# Python and WebRTC dependencies:"
    echo "sudo apt install python3 python3-pip"
    echo "pip3 install aiortc aiohttp websockets"
    echo
    echo "# Additional GStreamer WebRTC plugins:"
    echo "sudo apt install gstreamer1.0-nice gstreamer1.0-plugins-bad"
}

suggest_other_distros() {
    echo
    echo -e "${BLUE}Other Linux Distributions:${NC}"
    echo
    echo "# RHEL/CentOS/Fedora:"
    echo "sudo dnf install ffmpeg gstreamer1-tools gstreamer1-plugins-good"
    echo "sudo dnf install gstreamer1-plugins-bad-free gstreamer1-plugins-ugly"
    echo "sudo dnf install python3 python3-pip"
    echo
    echo "# Arch Linux:"
    echo "sudo pacman -S ffmpeg gstreamer gst-plugins-good gst-plugins-bad"
    echo "sudo pacman -S gst-plugins-ugly python python-pip"
}

#############################################################################
# Main Functions
#############################################################################

check_basic_dependencies() {
    echo -e "${GREEN}=== Checking Basic Dependencies ===${NC}"
    echo
    
    check_bash
    echo
    check_ffmpeg
    echo
    check_basic_tools
    echo
    check_system_resources
    echo
    check_network
}

check_webrtc_dependencies() {
    echo -e "${GREEN}=== Checking WebRTC Dependencies ===${NC}"
    echo
    
    check_python
    echo
    check_python_webrtc_packages
    echo
    check_gstreamer
    echo
    check_gstreamer_plugins
}

print_summary() {
    echo
    echo -e "${GREEN}=== Dependency Check Summary ===${NC}"
    echo
    
    if [[ "$BASIC_DEPS_OK" == "true" ]]; then
        print_status "Basic dependencies" "OK" "All requirements met"
    else
        print_status "Basic dependencies" "ERROR" "Some requirements missing"
        # Print exact failures
        if (( ${#BASIC_FAILURES[@]} > 0 )); then
            echo
            echo "  Basic failures:"
            for f in "${BASIC_FAILURES[@]}"; do
                echo "    - $f"
            done
        fi
    fi
    
    if [[ "$PYTHON_DEPS_OK" == "true" ]]; then
        print_status "Python dependencies" "OK" "All requirements met"
    else
        print_status "Python dependencies" "ERROR" "Some requirements missing"
        if (( ${#PYTHON_FAILURES[@]} > 0 )); then
            echo
            echo "  Python failures:"
            for f in "${PYTHON_FAILURES[@]}"; do
                echo "    - $f"
            done
        fi
    fi
    
    if [[ "$GSTREAMER_DEPS_OK" == "true" ]]; then
        print_status "GStreamer dependencies" "OK" "All requirements met"
    else
        print_status "GStreamer dependencies" "ERROR" "Some requirements missing"
        if (( ${#GSTREAMER_FAILURES[@]} > 0 )); then
            echo
            echo "  GStreamer failures:"
            for f in "${GSTREAMER_FAILURES[@]}"; do
                echo "    - $f"
            done
        fi
    fi
    
    # Overall WebRTC status
    if [[ "$PYTHON_DEPS_OK" == "true" && "$GSTREAMER_DEPS_OK" == "true" ]]; then
        WEBRTC_DEPS_OK=true
        print_status "WebRTC support" "OK" "Ready for WebRTC streaming"
    else
        WEBRTC_DEPS_OK=false
        print_status "WebRTC support" "ERROR" "WebRTC streaming not available"
    fi
}

show_help() {
    echo "Dependency Checker for Stream Load Tester"
    echo
    echo "Usage: $0 [OPTION]"
    echo
    echo "Options:"
    echo "  basic    Check basic dependencies (FFmpeg, bash, tools)"
    echo "  webrtc   Check WebRTC specific dependencies (Python, GStreamer)"
    echo "  all      Check all dependencies (default)"
    echo "  help     Show this help message"
    echo
    echo "Exit codes:"
    echo "  0 - All checked dependencies are satisfied"
    echo "  1 - Some dependencies are missing"
    echo "  2 - Invalid usage"
}

main() {
    local check_type="${1:-all}"
    
    case "$check_type" in
        "basic")
            check_basic_dependencies
            if [[ "$BASIC_DEPS_OK" == "true" ]]; then
                echo -e "${GREEN}✓ Basic dependencies check passed${NC}"
                exit 0
            else
                echo -e "${RED}✗ Basic dependencies check failed${NC}"
                suggest_ubuntu_installation
                exit 1
            fi
            ;;
        "webrtc")
            check_webrtc_dependencies
            print_summary
            if [[ "$WEBRTC_DEPS_OK" == "true" ]]; then
                echo -e "${GREEN}✓ WebRTC dependencies check passed${NC}"
                exit 0
            else
                echo -e "${RED}✗ WebRTC dependencies check failed${NC}"
                suggest_ubuntu_installation
                exit 1
            fi
            ;;
        "all")
            check_basic_dependencies
            echo
            check_webrtc_dependencies
            print_summary
            
            echo
            if [[ "$BASIC_DEPS_OK" == "true" && "$WEBRTC_DEPS_OK" == "true" ]]; then
                echo -e "${GREEN}✓ All dependencies check passed${NC}"
                echo -e "${GREEN}  Stream Load Tester is ready to use!${NC}"
                exit 0
            elif [[ "$BASIC_DEPS_OK" == "true" ]]; then
                echo -e "${YELLOW}✓ Basic streaming (RTMP/RTSP/SRT) is ready${NC}"
                echo -e "${RED}✗ WebRTC streaming is not available${NC}"
                suggest_ubuntu_installation
                exit 1
            else
                echo -e "${RED}✗ Dependencies check failed${NC}"
                suggest_ubuntu_installation
                exit 1
            fi
            ;;
        "help"|"-h"|"--help")
            show_help
            exit 0
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