#!/bin/bash

#############################################################################
# FFmpeg Codec Fix Script
# 
# Description: Fixes FFmpeg installations that lack essential codecs
#              (H.264, AAC, test sources) common on Ubuntu/Debian systems
#
# Usage: ./fix_ffmpeg_codecs.sh
#
# Author: Stream Load Tester Project
# Version: 1.0
# Date: October 15, 2025
#############################################################################

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/ffmpeg_checks.sh"

info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    usage() {
        cat <<EOF
    Usage: $(basename "$0") [options]

    Options:
      --check-only         Check FFmpeg codecs and exit with number of issues
      --auto METHOD        Automatically run the specified fix method
                           Methods: packages, snap, ppa, static, recommended
      -h, --help           Show this help message

    Without options the script runs in interactive mode.
    EOF
    }

    run_codec_check() {
        set +e
        check_ffmpeg_codecs
        local issues=$?
        set -e
        return $issues
    }

    perform_install_method() {
        local method="$1"
        case "$method" in
            packages)
                if ! install_codec_packages; then
                    return 1
                fi
                ;;
            snap)
                if ! install_ffmpeg_snap; then
                    return 1
                fi
                ;;
            ppa)
                if ! install_ffmpeg_ppa; then
                    return 1
                fi
                ;;
            static)
                if ! install_static_ffmpeg; then
                    return 1
                fi
                ;;
            recommended)
                if ! install_codec_packages; then
                    warn "Failed to install codec packages, continuing with fallback"
                fi
                run_codec_check
                local issues=$?
                if (( issues != 0 )); then
                    warn "Packages method incomplete, falling back to static build"
                    if ! install_static_ffmpeg; then
                        return 1
                    fi
                fi
                ;;
            *)
                error "Unknown method: $method"
                return 2
                ;;
        esac
    }

    run_auto_mode() {
        local method="$1"

        info "Running automatic FFmpeg fix (method: $method)"
        run_codec_check
        local issues=$?
        if (( issues == 0 )); then
            info "FFmpeg already has all required codecs"
            return 0
        fi

        if ! perform_install_method "$method"; then
            error "Failed to execute method '$method'"
            return 1
        fi

        info "Re-checking FFmpeg installation..."
        sleep 1
        run_codec_check
        local remaining=$?
        if (( remaining == 0 )); then
            info "🎉 FFmpeg codec fix completed successfully!"
            return 0
        fi

        error "❌ Issues remain after automatic fix"
        return $remaining
    }

    run_interactive_mode() {
        echo -e "${BLUE}FFmpeg Codec Fix Script${NC}"
        echo "======================="
        echo

        run_codec_check
        local issues=$?
        if (( issues == 0 )); then
            info "🎉 FFmpeg already has all required codecs!"
            return 0
        fi

        echo
        warn "Found $issues codec/feature issues that need fixing"
        echo
        echo "Choose installation method:"
        echo "1) Install additional codec packages (recommended for Ubuntu/Debian)"
        echo "2) Install FFmpeg from snap (includes all codecs)"
        echo "3) Install FFmpeg from PPA (alternative repository)"
        echo "4) Install static FFmpeg build (universal, always works)"
        echo "5) Exit without changes"
        echo
        read -p "Enter choice [1-5]: " choice

        case "$choice" in
            1)
                perform_install_method "packages"
                ;;
            2)
                perform_install_method "snap"
                ;;
            3)
                perform_install_method "ppa"
                ;;
            4)
                perform_install_method "static"
                ;;
            5)
                info "Exiting without changes"
                return 0
                ;;
            *)
                error "Invalid choice"
                return 1
                ;;
        esac

        echo
        info "Testing FFmpeg installation..."
        sleep 2
        run_codec_check
        local remaining_issues=$?
        if (( remaining_issues == 0 )); then
            echo
            info "🎉 FFmpeg codec fix completed successfully!"
            info "All required codecs and features are now available"
            echo
            info "You can now run the dependency checker:"
            info "  ./scripts/check_dependencies.sh"
            echo
            info "Or run the main stream load tester:"
            info "  ./stream_load_tester.sh"
        else
            echo
            error "❌ Some issues remain after installation"
            error "You may need to try a different installation method"
            echo
            echo "Troubleshooting suggestions:"
            echo "1. Try method 4 (static build) - usually works on all systems"
            echo "2. Manually compile FFmpeg with required codecs"
            echo "3. Use Docker container with pre-built FFmpeg"

            return 1
        fi

        return 0
    }

    echo -e "${YELLOW}[WARN]${NC} $1"
        local args=()
        local auto_method=""
        local check_only=false

        while [[ $# -gt 0 ]]; do
            case "$1" in
                --check-only)
                    check_only=true
                    shift
                    ;;
                --auto=*)
                    auto_method="${1#*=}"
                    shift
                    ;;
                --auto)
                    if [[ $# -lt 2 ]]; then
                        error "--auto requires a method"
                        return 1
                    fi
                    auto_method="$2"
                    shift 2
                    ;;
                -h|--help)
                    usage
                    return 0
                    ;;
                --)
                    shift
                    break
                    ;;
                -* )
                    error "Unknown option: $1"
                    usage
                    return 1
                    ;;
                *)
                    args+=("$1")
                    shift
                    ;;
            esac
        done

        if $check_only; then
            run_codec_check
            return $?
        fi

        if [[ -n "$auto_method" ]]; then
            run_auto_mode "$auto_method"
            return $?
        fi

        run_interactive_mode "${args[@]}"
    
    return $issues
}

install_codec_packages() {
    info "Installing additional codec packages..."
    
    sudo apt update
    
    # Install extra codecs
    local packages=(
        "libavcodec-extra"
        "ubuntu-restricted-extras"
        "ffmpeg"
        "libx264-dev"
        "libfdk-aac-dev"
        "libmp3lame-dev"
    )
    
    for package in "${packages[@]}"; do
        info "Installing $package..."
        if sudo apt install -y "$package" 2>/dev/null; then
            info "✓ Installed $package"
        else
            warn "Failed to install $package (may not be available)"
        fi
    done
}

install_ffmpeg_snap() {
    info "Installing FFmpeg from snap (includes all codecs)..."
    
    if ! command -v snap >/dev/null 2>&1; then
        info "Installing snapd..."
        sudo apt install -y snapd
    fi
    
    # Remove existing ffmpeg
    sudo apt remove -y ffmpeg || true
    
    # Install from snap
    sudo snap install ffmpeg
    
    # Create symlinks for system-wide access
    sudo ln -sf /snap/bin/ffmpeg /usr/local/bin/ffmpeg || true
    sudo ln -sf /snap/bin/ffprobe /usr/local/bin/ffprobe || true
    
    info "FFmpeg installed from snap"
}

install_ffmpeg_ppa() {
    info "Installing FFmpeg from PPA..."
    
    # Add software-properties-common if not available
    sudo apt install -y software-properties-common
    
    # Try different PPAs
    local ppas=(
        "ppa:savoury1/ffmpeg4"
        "ppa:savoury1/ffmpeg5"
        "ppa:jonathonf/ffmpeg-4"
    )
    
    for ppa in "${ppas[@]}"; do
        info "Trying $ppa..."
        if sudo add-apt-repository "$ppa" -y; then
            sudo apt update
            
            # Remove existing ffmpeg
            sudo apt remove -y ffmpeg || true
            
            # Install from PPA
            if sudo apt install -y ffmpeg; then
                info "✓ FFmpeg installed from $ppa"
                return 0
            else
                warn "Failed to install from $ppa"
                sudo add-apt-repository --remove "$ppa" -y || true
            fi
        fi
    done
    
    return 1
}

install_static_ffmpeg() {
    info "Installing static FFmpeg build..."
    
    local temp_dir=$(mktemp -d)
    local arch=$(uname -m)
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
            return 1
            ;;
    esac
    
    info "Downloading FFmpeg for $arch..."
    cd "$temp_dir"
    
    if command -v wget >/dev/null 2>&1; then
        wget "$ffmpeg_url" -O ffmpeg-static.tar.xz
    elif command -v curl >/dev/null 2>&1; then
        curl -L "$ffmpeg_url" -o ffmpeg-static.tar.xz
    else
        error "Neither wget nor curl available"
        return 1
    fi
    
    info "Extracting and installing..."
    tar -xf ffmpeg-static.tar.xz
    cd ffmpeg-*-static
    
    # Backup existing ffmpeg
    if command -v ffmpeg >/dev/null 2>&1; then
        sudo cp "$(which ffmpeg)" "$(which ffmpeg).backup" || true
    fi
    
    # Install static binaries
    sudo cp ffmpeg /usr/local/bin/
    sudo cp ffprobe /usr/local/bin/
    sudo chmod +x /usr/local/bin/ffmpeg /usr/local/bin/ffprobe
    
    # Update PATH to prefer /usr/local/bin
    export PATH="/usr/local/bin:$PATH"
    
    # Cleanup
    cd /
    rm -rf "$temp_dir"
    
    info "Static FFmpeg installed to /usr/local/bin/"
}

main() {
    echo -e "${BLUE}FFmpeg Codec Fix Script${NC}"
    echo "======================="
    echo
    
    # Check current status
    local issues=0
    set +e
    check_ffmpeg_codecs
    issues=$?
    set -e
    
    if (( issues == 0 )); then
        info "🎉 FFmpeg already has all required codecs!"
        exit 0
    fi
    
    echo
    warn "Found $issues codec/feature issues that need fixing"
    echo
    
    echo "Choose installation method:"
    echo "1) Install additional codec packages (recommended for Ubuntu/Debian)"
    echo "2) Install FFmpeg from snap (includes all codecs)"
    echo "3) Install FFmpeg from PPA (alternative repository)"
    echo "4) Install static FFmpeg build (universal, always works)"
    echo "5) Exit without changes"
    echo
    
    read -p "Enter choice [1-5]: " choice
    
    case "$choice" in
        1)
            install_codec_packages
            ;;
        2)
            install_ffmpeg_snap
            ;;
        3)
            install_ffmpeg_ppa
            ;;
        4)
            install_static_ffmpeg
            ;;
        5)
            info "Exiting without changes"
            exit 0
            ;;
        *)
            error "Invalid choice"
            exit 1
            ;;
    esac
    
    echo
    info "Testing FFmpeg installation..."
    sleep 2
    
    # Test the installation
    set +e
    check_ffmpeg_codecs
    local remaining_issues=$?
    set -e
    
    if (( remaining_issues == 0 )); then
        echo
        info "🎉 FFmpeg codec fix completed successfully!"
        info "All required codecs and features are now available"
        echo
        info "You can now run the dependency checker:"
        info "  ./scripts/check_dependencies.sh"
        echo
        info "Or run the main stream load tester:"
        info "  ./stream_load_tester.sh"
    else
        echo
        error "❌ Some issues remain after installation"
        error "You may need to try a different installation method"
        echo
        echo "Troubleshooting suggestions:"
        echo "1. Try method 4 (static build) - usually works on all systems"
        echo "2. Manually compile FFmpeg with required codecs"
        echo "3. Use Docker container with pre-built FFmpeg"
        
        exit 1
    fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    if ! command -v sudo >/dev/null 2>&1; then
        error "This script requires sudo access"
        exit 1
    fi

    if ! command -v apt >/dev/null 2>&1; then
        error "This script is designed for Ubuntu/Debian systems with apt"
        error "For other distributions, please install FFmpeg with H.264 and AAC support manually"
        exit 1
    fi

    main "$@"
fi