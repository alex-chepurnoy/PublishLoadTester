#!/bin/bash

#############################################################################
# Installation Script for Stream Load Tester
# 
# Description: Automated installation of dependencies for the stream load tester
#              on various Linux distributions
#
# Usage: ./install.sh [options]
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
PROJECT_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
FFMPEG_FIX_SCRIPT="$SCRIPT_DIR/fix_ffmpeg_codecs.sh"
FFMPEG_HELPERS="$SCRIPT_DIR/lib/ffmpeg_checks.sh"

if [[ ! -f "$FFMPEG_HELPERS" ]]; then
    echo -e "${RED}[ERROR]${NC} Missing FFmpeg helper library at $FFMPEG_HELPERS"
    exit 1
fi

# shellcheck disable=SC1091
source "$FFMPEG_HELPERS"

# Installation flags
SKIP_CONFIRMATION=false
INSTALL_WEBRTC=true
UPDATE_PACKAGES=true
VERBOSE=false

# Detect distribution
detect_distro() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        echo "$ID"
    elif command -v lsb_release >/dev/null 2>&1; then
        lsb_release -si | tr '[:upper:]' '[:lower:]'
    else
        echo "unknown"
    fi
}

# Install Python WebRTC packages with proper environment handling
install_python_packages() {
    local packages="aiortc aiohttp websockets"
    
    info "Checking Python environment..."
    
    # First, try to detect if this is an externally managed environment
    local is_externally_managed=false
    
    # Check for the PEP 668 marker file
    if [[ -f /usr/lib/python*/EXTERNALLY-MANAGED ]] || [[ -f /usr/lib/python*/dist-packages/EXTERNALLY-MANAGED ]]; then
        is_externally_managed=true
    fi
    
    # Try a test pip install to see if we get the externally-managed error
    if ! $is_externally_managed; then
        if pip3 install --dry-run --user pip 2>&1 | grep -q "externally-managed-environment"; then
            is_externally_managed=true
        fi
    fi
    
    if $is_externally_managed; then
        warn "Detected externally-managed Python environment (PEP 668)"
        handle_externally_managed_env "$packages"
    else
        # Try standard user installation
        info "Attempting standard user installation..."
        if pip3 install --user "$packages"; then
            info "Successfully installed Python WebRTC packages"
        else
            warn "Standard installation failed, trying alternative methods..."
            handle_externally_managed_env "$packages"
        fi
    fi
}

# Handle externally managed environment
handle_externally_managed_env() {
    local packages="$1"
    
    info "Trying alternative installation methods..."
    
    # Method 1: Try system packages first
    info "Checking for system packages..."
    local system_packages_available=true
    for pkg in aiortc aiohttp websockets; do
        if ! apt-cache show "python3-$pkg" >/dev/null 2>&1; then
            system_packages_available=false
            break
        fi
    done
    
    if $system_packages_available; then
        if [[ "$SKIP_CONFIRMATION" == "false" ]]; then
            echo "System packages are available. Install using apt? (recommended) (y/N)"
            read -r response
            if [[ "$response" =~ ^[Yy] ]]; then
                info "Installing system packages..."
                sudo apt install -y python3-aiortc python3-aiohttp python3-websockets
                if [[ $? -eq 0 ]]; then
                    info "Successfully installed system packages"
                    return 0
                else
                    warn "System package installation failed"
                fi
            fi
        fi
    fi
    
    # Method 2: Try pipx
    if command -v pipx >/dev/null 2>&1; then
        if [[ "$SKIP_CONFIRMATION" == "false" ]]; then
            echo "Try installing with pipx? (y/N)"
            read -r response
            if [[ "$response" =~ ^[Yy] ]]; then
                info "Installing with pipx..."
                for package in $packages; do
                    pipx install "$package" || warn "Failed to install $package with pipx"
                done
                return 0
            fi
        fi
    else
        debug "pipx not available"
    fi
    
    # Method 3: Virtual environment (recommended)
    if [[ "$SKIP_CONFIRMATION" == "false" ]]; then
        echo "Create a virtual environment for WebRTC packages? (recommended) (Y/n)"
        read -r response
        if [[ ! "$response" =~ ^[Nn] ]]; then
            create_venv_and_install
            return 0
        fi
    else
        # In non-interactive mode, create venv automatically
        info "Creating virtual environment automatically..."
        create_venv_and_install
        return 0
    fi
    
    # Method 4: --break-system-packages (last resort)
    if [[ "$SKIP_CONFIRMATION" == "false" ]]; then
        echo "Try --break-system-packages flag? (not recommended) (y/N)"
        read -r response
        if [[ "$response" =~ ^[Yy] ]]; then
            info "Installing with --break-system-packages..."
            if pip3 install --break-system-packages --user "$packages"; then
                info "Successfully installed with --break-system-packages"
                return 0
            fi
        fi
    fi
    
    # If all methods fail
    warn "All installation methods failed or were declined"
    warn "WebRTC functionality will not be available"
    warn "You can manually install packages later or re-run the installation script"
    return 1
}

# Create virtual environment and install packages
create_venv_and_install() {
    local venv_path="$HOME/.local/share/stream-load-tester-venv"
    
    # Ensure python3-full is installed (required for venv on newer Ubuntu/Debian)
    if command -v apt >/dev/null 2>&1; then
        info "Ensuring python3-full is installed..."
        sudo apt install -y python3-full python3-venv
    fi
    
    info "Creating virtual environment at $venv_path..."
    if ! python3 -m venv "$venv_path"; then
        error "Failed to create virtual environment"
        return 1
    fi
    
    info "Installing packages in virtual environment..."
    if ! "$venv_path/bin/pip" install aiortc aiohttp websockets; then
        error "Failed to install packages in virtual environment"
        return 1
    fi
    
    # Create wrapper script
    local wrapper_script="$HOME/.local/bin/stream-load-tester-webrtc"
    mkdir -p "$(dirname "$wrapper_script")"
    
    cat > "$wrapper_script" << 'EOF'
#!/bin/bash
# Wrapper script to run WebRTC publisher with virtual environment
VENV_PATH="$HOME/.local/share/stream-load-tester-venv"
if [[ -f "$VENV_PATH/bin/python" ]]; then
    exec "$VENV_PATH/bin/python" "$@"
else
    echo "Error: Virtual environment not found at $VENV_PATH"
    echo "Please run the installation script again."
    exit 1
fi
EOF
    
    chmod +x "$wrapper_script"
    
    # Update the webrtc_publisher.py shebang to use the wrapper
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    if [[ -f "$script_dir/webrtc_publisher.py" ]]; then
        # Create a backup
        cp "$script_dir/webrtc_publisher.py" "$script_dir/webrtc_publisher.py.bak"
        
        # Update shebang to use the wrapper
        sed -i "1s|.*|#!$wrapper_script|" "$script_dir/webrtc_publisher.py"
        
        info "Updated webrtc_publisher.py to use virtual environment"
    fi
    
    info "Virtual environment created successfully"
    info "WebRTC functionality will use: $venv_path"
    
    # Add to PATH recommendation
    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        info "Consider adding $HOME/.local/bin to your PATH:"
        info "echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc"
    fi
    
    return 0
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

debug() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${BLUE}[DEBUG]${NC} $1"
    fi
}

ffmpeg_requirements_met() {
    ffmpeg_reset_capability_cache

    if ! ffmpeg_is_available; then
        return 1
    fi

    local status

    ffmpeg_has_any_encoder "${FFMPEG_H264_ENCODERS[@]}"
    status=$?
    if (( status != 0 )); then
        return 1
    fi

    ffmpeg_has_any_encoder "${FFMPEG_AAC_ENCODERS[@]}"
    status=$?
    if (( status != 0 )); then
        return 1
    fi

    ffmpeg_has_any_filter "${FFMPEG_TESTSRC_FILTERS[@]}"
    status=$?
    if (( status != 0 )); then
        return 1
    fi

    ffmpeg_has_any_filter "${FFMPEG_SINE_FILTERS[@]}"
    status=$?
    if (( status != 0 )); then
        return 1
    fi

    return 0
}

ensure_ffmpeg_codecs() {
    local method=${1:-recommended}

    if ffmpeg_requirements_met; then
        debug "FFmpeg already meets codec requirements"
        return 0
    fi

    warn "FFmpeg codecs missing or incomplete; invoking fix script ($method)"
    if ! "$FFMPEG_FIX_SCRIPT" --auto "$method"; then
        warn "FFmpeg fix script failed with method '$method'"
        return 1
    fi

    if ffmpeg_requirements_met; then
        info "FFmpeg now has required codecs"
        return 0
    fi

    warn "FFmpeg still missing required codecs after fix script"
    return 1
}

install_ubuntu_debian() {
    info "Installing dependencies for Ubuntu/Debian..."
    
    if [[ "$UPDATE_PACKAGES" == "true" ]]; then
        info "Updating package lists..."
        sudo apt update
    fi
    
    # Check Ubuntu version for codec installation strategy
    local ubuntu_version=""
    if [[ -f /etc/lsb-release ]]; then
        ubuntu_version=$(grep DISTRIB_RELEASE /etc/lsb-release | cut -d= -f2)
    fi
    
    info "Installing FFmpeg with full codec support..."
    
    # For Ubuntu 22.04+ and Debian 12+, we need to enable universe repository
    if command -v add-apt-repository >/dev/null 2>&1; then
        info "Enabling universe repository for full codec support..."
        sudo add-apt-repository universe -y
        sudo apt update
    fi
    
    # Install FFmpeg with extra codecs
    sudo apt install -y \
        ffmpeg \
        libavcodec-extra \
        ubuntu-restricted-extras \
        gstreamer1.0-tools \
        gstreamer1.0-plugins-good \
        gstreamer1.0-plugins-bad \
        gstreamer1.0-plugins-ugly \
        gstreamer1.0-nice \
        gstreamer1.0-libav

    if ! ensure_ffmpeg_codecs "recommended"; then
        warn "FFmpeg may still lack required codecs. Run $FFMPEG_FIX_SCRIPT manually if issues persist."
    fi
    
    info "Installing Python and pip..."
    sudo apt install -y python3 python3-pip python3-venv python3-full
    
    if [[ "$INSTALL_WEBRTC" == "true" ]]; then
        info "Installing Python WebRTC packages..."
        install_python_packages
    fi
    
    info "Ubuntu/Debian installation completed"
}

install_fedora_rhel() {
    info "Installing dependencies for Fedora/RHEL..."
    
    # Enable RPM Fusion for FFmpeg
    if ! rpm -q rpmfusion-free-release >/dev/null 2>&1; then
        info "Enabling RPM Fusion repositories..."
        sudo dnf install -y \
            https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
            https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
    fi
    
    if [[ "$UPDATE_PACKAGES" == "true" ]]; then
        info "Updating package lists..."
        sudo dnf update -y
    fi
    
    info "Installing FFmpeg and GStreamer..."
    sudo dnf install -y \
        ffmpeg \
        gstreamer1-tools \
        gstreamer1-plugins-good \
        gstreamer1-plugins-bad-free \
        gstreamer1-plugins-ugly
    
    info "Installing Python and pip..."
    sudo dnf install -y python3 python3-pip python3-venv
    
    if [[ "$INSTALL_WEBRTC" == "true" ]]; then
        info "Installing Python WebRTC packages..."
        install_python_packages
    fi
    
    info "Fedora/RHEL installation completed"
}

install_arch() {
    info "Installing dependencies for Arch Linux..."
    
    if [[ "$UPDATE_PACKAGES" == "true" ]]; then
        info "Updating package database..."
        sudo pacman -Sy
    fi
    
    info "Installing FFmpeg and GStreamer..."
    sudo pacman -S --needed \
        ffmpeg \
        gstreamer \
        gst-plugins-good \
        gst-plugins-bad \
        gst-plugins-ugly
    
    info "Installing Python and pip..."
    sudo pacman -S --needed python python-pip
    
    if [[ "$INSTALL_WEBRTC" == "true" ]]; then
        info "Installing Python WebRTC packages..."
        install_python_packages
    fi
    
    info "Arch Linux installation completed"
}

install_opensuse() {
    info "Installing dependencies for openSUSE..."
    
    if [[ "$UPDATE_PACKAGES" == "true" ]]; then
        info "Updating package lists..."
        sudo zypper refresh
    fi
    
    info "Installing FFmpeg and GStreamer..."
    sudo zypper install -y \
        ffmpeg \
        gstreamer-tools \
        gstreamer-plugins-good \
        gstreamer-plugins-bad \
        gstreamer-plugins-ugly
    
    info "Installing Python and pip..."
    sudo zypper install -y python3 python3-pip python3-venv
    
    if [[ "$INSTALL_WEBRTC" == "true" ]]; then
        info "Installing Python WebRTC packages..."
        install_python_packages
    fi
    
    info "openSUSE installation completed"
}

make_scripts_executable() {
    info "Making scripts executable..."
    
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    
    chmod +x "$script_dir/stream_load_tester.sh"
    chmod +x "$script_dir/check_dependencies.sh"
    chmod +x "$script_dir/webrtc_publisher.py"
    chmod +x "$script_dir/scripts/cleanup.sh"
    
    debug "Made scripts executable"
}

create_symlinks() {
    info "Creating system-wide symlinks (optional)..."
    
    if [[ "$SKIP_CONFIRMATION" == "false" ]]; then
        echo "Create symlinks in /usr/local/bin for system-wide access? (y/N)"
        read -r response
        if [[ ! "$response" =~ ^[Yy] ]]; then
            info "Skipping symlink creation"
            return
        fi
    fi
    
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    
    sudo ln -sf "$script_dir/stream_load_tester.sh" /usr/local/bin/stream-load-tester
    sudo ln -sf "$script_dir/check_dependencies.sh" /usr/local/bin/stream-load-tester-deps
    sudo ln -sf "$script_dir/scripts/cleanup.sh" /usr/local/bin/stream-load-tester-cleanup
    
    info "Created symlinks:"
    info "  stream-load-tester -> $script_dir/stream_load_tester.sh"
    info "  stream-load-tester-deps -> $script_dir/check_dependencies.sh"
    info "  stream-load-tester-cleanup -> $script_dir/scripts/cleanup.sh"
}

verify_installation() {
    info "Verifying installation..."
    
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    
    # Run dependency check
    if "$script_dir/check_dependencies.sh" all; then
        info "All dependencies verified successfully"
        return 0
    else
        error "Dependency verification failed"
        return 1
    fi
}

show_help() {
    echo "Installation Script for Stream Load Tester"
    echo
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  -y, --yes           Skip confirmation prompts"
    echo "  --no-webrtc         Skip WebRTC package installation"
    echo "  --no-update         Skip package list updates"
    echo "  -v, --verbose       Verbose output"
    echo "  -h, --help          Show this help message"
    echo
    echo "Supported distributions:"
    echo "  - Ubuntu/Debian"
    echo "  - Fedora/RHEL/CentOS"
    echo "  - Arch Linux"
    echo "  - openSUSE"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -y|--yes)
                SKIP_CONFIRMATION=true
                shift
                ;;
            --no-webrtc)
                INSTALL_WEBRTC=false
                shift
                ;;
            --no-update)
                UPDATE_PACKAGES=false
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
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
    echo -e "${BLUE}Stream Load Tester Installation Script${NC}"
    echo "======================================"
    echo
    
    # Parse arguments
    parse_args "$@"
    
    # Detect distribution
    local distro=$(detect_distro)
    info "Detected distribution: $distro"
    
    # Check if running as root
    if [[ $EUID -eq 0 ]]; then
        warn "Running as root. Some pip installations may not work correctly."
        warn "Consider running as a regular user with sudo access."
    fi
    
    # Confirm installation
    if [[ "$SKIP_CONFIRMATION" == "false" ]]; then
        echo "This will install Stream Load Tester dependencies including:"
        echo "  - FFmpeg"
        echo "  - GStreamer and plugins"
        echo "  - Python 3 and pip"
        if [[ "$INSTALL_WEBRTC" == "true" ]]; then
            echo "  - Python WebRTC packages (aiortc, aiohttp, websockets)"
        fi
        echo
        echo "Continue with installation? (y/N)"
        read -r response
        if [[ ! "$response" =~ ^[Yy] ]]; then
            info "Installation cancelled"
            exit 0
        fi
    fi
    
    # Install based on distribution
    case "$distro" in
        ubuntu|debian)
            install_ubuntu_debian
            ;;
        fedora|rhel|centos)
            install_fedora_rhel
            ;;
        arch|manjaro)
            install_arch
            ;;
        opensuse*|suse)
            install_opensuse
            ;;
        *)
            error "Unsupported distribution: $distro"
            echo
            echo "Manual installation required. Please install:"
            echo "  - FFmpeg with libx264 and aac support"
            echo "  - GStreamer 1.0 with plugins (good, bad, ugly)"
            echo "  - Python 3.6+ with pip"
            echo "  - Python packages: aiortc aiohttp websockets"
            exit 1
            ;;
    esac
    
    echo
    make_scripts_executable
    
    echo
    if verify_installation; then
        info "Installation completed successfully!"
        
        echo
        create_symlinks
        
        echo
        info "Stream Load Tester is ready to use!"
        info "Run './stream_load_tester.sh' to start testing"
        info "Run './check_dependencies.sh' to verify setup"
        
    else
        error "Installation completed but verification failed"
        error "Please check the dependency checker output above"
        exit 1
    fi
}

# Check for minimum requirements
if ! command -v bash >/dev/null 2>&1; then
    echo "Error: Bash is required but not found"
    exit 1
fi

# Check bash version
if [[ ${BASH_VERSION%%.*} -lt 4 ]]; then
    echo "Error: Bash 4.0 or higher is required (current: $BASH_VERSION)"
    exit 1
fi

# Execute main function
main "$@"