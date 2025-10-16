#!/bin/bash

#############################################################################
# FFmpeg Requirements Installer
# 
# Description: Ensures FFmpeg is installed with required codecs and filters
#              for Stream Load Tester. Automatically installs if missing.
#
# Requirements:
#   - H.264 encoder (libx264 or hardware encoder)
#   - AAC audio encoder
#   - testsrc2 filter (test video source)
#   - sine filter (test audio source)
#
# Author: Stream Load Tester Project
# Version: 1.0
# Date: October 16, 2025
#############################################################################

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source the FFmpeg helper library
if [[ ! -f "$SCRIPT_DIR/lib/ffmpeg_checks.sh" ]]; then
    echo "ERROR: Missing FFmpeg helper library at $SCRIPT_DIR/lib/ffmpeg_checks.sh"
    exit 1
fi

# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/ffmpeg_checks.sh"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Flags
QUIET_MODE=false
AUTO_FIX=true

#############################################################################
# Logging Functions
#############################################################################

info() {
    if [[ "$QUIET_MODE" != "true" ]]; then
        echo -e "${GREEN}[INFO]${NC} $1"
    fi
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" >&2
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

#############################################################################
# Check Functions
#############################################################################

check_ffmpeg_requirements() {
    # Returns 0 if all requirements met, otherwise returns number of missing items
    ffmpeg_reset_capability_cache

    if ! ffmpeg_is_available; then
        return 4  # All 4 requirements missing
    fi

    local missing=0

    ffmpeg_has_any_encoder "${FFMPEG_H264_ENCODERS[@]}" || ((missing++))
    ffmpeg_has_any_encoder "${FFMPEG_AAC_ENCODERS[@]}" || ((missing++))
    ffmpeg_has_any_filter "${FFMPEG_TESTSRC_FILTERS[@]}" || ((missing++))
    ffmpeg_has_any_filter "${FFMPEG_SINE_FILTERS[@]}" || ((missing++))

    return $missing
}

#############################################################################
# Installation Functions
#############################################################################

detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        echo "$ID"
    elif command -v lsb_release >/dev/null 2>&1; then
        lsb_release -si | tr '[:upper:]' '[:lower:]'
    else
        echo "unknown"
    fi
}

install_ffmpeg_ubuntu_debian() {
    info "Detected Ubuntu/Debian system"
    info "Installing FFmpeg with required codecs..."
    
    # Update package lists
    sudo apt-get update -qq || {
        error "Failed to update package lists"
        return 1
    }
    
    # Try to install FFmpeg with codec packages
    local packages=(
        "ffmpeg"
        "libavcodec-extra"
    )
    
    info "Installing packages: ${packages[*]}"
    if sudo apt-get install -y -qq "${packages[@]}" 2>/dev/null; then
        info "Successfully installed FFmpeg packages"
        return 0
    fi
    
    # If that fails, try just ffmpeg
    warn "Failed to install extra codecs, trying basic FFmpeg install..."
    if sudo apt-get install -y -qq ffmpeg; then
        info "Installed basic FFmpeg"
        # Will fall back to static build if codecs missing
        return 0
    fi
    
    error "Failed to install FFmpeg via apt"
    return 1
}

install_ffmpeg_fedora_rhel() {
    info "Detected Fedora/RHEL system"
    
    # Check if RPM Fusion is enabled
    if ! rpm -q rpmfusion-free-release >/dev/null 2>&1; then
        info "Enabling RPM Fusion repository for FFmpeg..."
        sudo dnf install -y \
            "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
            2>/dev/null || {
            error "Failed to enable RPM Fusion"
            return 1
        }
    fi
    
    info "Installing FFmpeg..."
    sudo dnf install -y ffmpeg || {
        error "Failed to install FFmpeg"
        return 1
    }
    
    info "Successfully installed FFmpeg"
    return 0
}

install_ffmpeg_arch() {
    info "Detected Arch Linux system"
    info "Installing FFmpeg..."
    
    sudo pacman -Sy --noconfirm ffmpeg || {
        error "Failed to install FFmpeg"
        return 1
    }
    
    info "Successfully installed FFmpeg"
    return 0
}

install_ffmpeg_static() {
    info "Installing static FFmpeg build (universal method)..."
    
    local temp_dir
    temp_dir=$(mktemp -d)
    local arch
    arch=$(uname -m)
    local ffmpeg_url=""
    
    case "$arch" in
        x86_64)
            ffmpeg_url="https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz"
            ;;
        aarch64|arm64)
            ffmpeg_url="https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-arm64-static.tar.xz"
            ;;
        armv7l)
            ffmpeg_url="https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-armhf-static.tar.xz"
            ;;
        *)
            error "Unsupported architecture: $arch"
            rm -rf "$temp_dir"
            return 1
            ;;
    esac
    
    info "Downloading FFmpeg for $arch..."
    cd "$temp_dir" || return 1
    
    if command -v wget >/dev/null 2>&1; then
        wget -q "$ffmpeg_url" -O ffmpeg-static.tar.xz || {
            error "Failed to download FFmpeg"
            rm -rf "$temp_dir"
            return 1
        }
    elif command -v curl >/dev/null 2>&1; then
        curl -sL "$ffmpeg_url" -o ffmpeg-static.tar.xz || {
            error "Failed to download FFmpeg"
            rm -rf "$temp_dir"
            return 1
        }
    else
        error "Neither wget nor curl available for download"
        rm -rf "$temp_dir"
        return 1
    fi
    
    info "Extracting and installing..."
    tar -xf ffmpeg-static.tar.xz || {
        error "Failed to extract FFmpeg"
        rm -rf "$temp_dir"
        return 1
    }
    
    cd ffmpeg-*-static || {
        error "Failed to find extracted directory"
        rm -rf "$temp_dir"
        return 1
    }
    
    # Backup existing ffmpeg if present
    if command -v ffmpeg >/dev/null 2>&1; then
        local existing_ffmpeg
        existing_ffmpeg=$(command -v ffmpeg)
        sudo cp "$existing_ffmpeg" "${existing_ffmpeg}.backup" 2>/dev/null || true
    fi
    
    # Install static binaries
    sudo cp ffmpeg /usr/local/bin/ffmpeg || {
        error "Failed to install ffmpeg binary"
        rm -rf "$temp_dir"
        return 1
    }
    sudo cp ffprobe /usr/local/bin/ffprobe || true
    sudo chmod +x /usr/local/bin/ffmpeg /usr/local/bin/ffprobe
    
    # Update PATH preference
    export PATH="/usr/local/bin:$PATH"
    
    # Cleanup
    cd /
    rm -rf "$temp_dir"
    
    info "Static FFmpeg installed to /usr/local/bin/ffmpeg"
    return 0
}

try_install_ffmpeg() {
    local os_type
    os_type=$(detect_os)
    
    info "Attempting to install FFmpeg..."
    
    case "$os_type" in
        ubuntu|debian|linuxmint|pop)
            install_ffmpeg_ubuntu_debian
            ;;
        fedora|rhel|centos|rocky|alma)
            install_ffmpeg_fedora_rhel
            ;;
        arch|manjaro|endeavour)
            install_ffmpeg_arch
            ;;
        *)
            warn "Unknown or unsupported OS: $os_type"
            warn "Trying static build method..."
            install_ffmpeg_static
            ;;
    esac
}

fix_ffmpeg_codecs() {
    info "FFmpeg is installed but missing required codecs/filters"
    info "Attempting to fix with static build..."
    
    if install_ffmpeg_static; then
        info "Static FFmpeg installed successfully"
        return 0
    else
        error "Failed to install static FFmpeg"
        return 1
    fi
}

#############################################################################
# Main Logic
#############################################################################

ensure_requirements() {
    info "Checking FFmpeg requirements..."
    
    # Check current status
    local missing=0
    check_ffmpeg_requirements || missing=$?
    
    if (( missing == 0 )); then
        info "✓ All FFmpeg requirements are met"
        return 0
    fi
    
    # Requirements not met
    if (( missing == 4 )); then
        # FFmpeg not installed at all
        warn "FFmpeg is not installed"
        
        if [[ "$AUTO_FIX" != "true" ]]; then
            error "Please install FFmpeg manually or run with --auto-fix"
            return 1
        fi
        
        info "Installing FFmpeg..."
        if ! try_install_ffmpeg; then
            error "Failed to install FFmpeg"
            return 1
        fi
        
        # Recheck after installation
        check_ffmpeg_requirements || missing=$?
        
        if (( missing == 0 )); then
            info "✓ FFmpeg installed successfully with all requirements"
            return 0
        fi
        
        # Still missing codecs, try static build
        warn "Installed FFmpeg is missing some codecs/filters"
        if ! fix_ffmpeg_codecs; then
            error "Failed to fix FFmpeg codecs"
            return 1
        fi
    else
        # FFmpeg installed but missing codecs
        warn "FFmpeg is missing $missing required codec(s)/filter(s)"
        
        if [[ "$AUTO_FIX" != "true" ]]; then
            error "Please run with --auto-fix to install missing codecs"
            return 1
        fi
        
        if ! fix_ffmpeg_codecs; then
            error "Failed to fix FFmpeg codecs"
            return 1
        fi
    fi
    
    # Final verification
    check_ffmpeg_requirements || missing=$?
    
    if (( missing == 0 )); then
        info "✓ All FFmpeg requirements are now met"
        return 0
    else
        error "Failed to meet all requirements (still missing $missing items)"
        error "Please install FFmpeg manually with H.264, AAC support"
        return 1
    fi
}

show_help() {
    cat <<EOF
FFmpeg Requirements Installer for Stream Load Tester

Usage: $(basename "$0") [OPTIONS]

This script ensures FFmpeg is installed with required codecs:
  - H.264 encoder (libx264 or hardware encoder)
  - AAC audio encoder
  - testsrc2 filter (test video source)
  - sine filter (test audio source)

Options:
  --check-only    Only check requirements, don't install
  --no-auto-fix   Don't automatically install if missing
  --quiet         Minimal output
  -h, --help      Show this help message

Exit Codes:
  0 - All requirements met
  1 - Requirements not met and/or installation failed

Examples:
  $(basename "$0")                  # Check and auto-install if needed
  $(basename "$0") --check-only     # Only check, don't install
  $(basename "$0") --quiet          # Silent mode

EOF
}

main() {
    local check_only=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --check-only)
                check_only=true
                AUTO_FIX=false
                shift
                ;;
            --no-auto-fix)
                AUTO_FIX=false
                shift
                ;;
            --quiet)
                QUIET_MODE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    if [[ "$check_only" == "true" ]]; then
        # Just check and report
        local missing=0
        check_ffmpeg_requirements || missing=$?
        
        if (( missing == 0 )); then
            info "✓ All FFmpeg requirements are met"
            exit 0
        else
            if (( missing == 4 )); then
                error "FFmpeg is not installed"
            else
                error "FFmpeg is missing $missing required codec(s)/filter(s)"
            fi
            exit 1
        fi
    else
        # Check and install if needed
        if ensure_requirements; then
            exit 0
        else
            exit 1
        fi
    fi
}

# Execute main if run directly
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
