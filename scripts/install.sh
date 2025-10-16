#!/bin/bash

#############################################################################
# Installation Script for Stream Load Tester
# 
# Description: Automated installation of dependencies for the stream load tester
#
# Usage: ./install.sh [options]
#
# Author: Stream Load Tester Project
# Version: 2.0
# Date: October 16, 2025
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

# Installation flags
SKIP_CONFIRMATION=false
VERBOSE=false

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

make_scripts_executable() {
    info "Making scripts executable..."
    
    chmod +x "$PROJECT_ROOT/stream_load_tester.sh"
    chmod +x "$PROJECT_ROOT/check_dependencies.sh"
    chmod +x "$SCRIPT_DIR/cleanup.sh"
    chmod +x "$SCRIPT_DIR/ensure_ffmpeg_requirements.sh"
    chmod +x "$SCRIPT_DIR/fix_ffmpeg_codecs.sh"
    
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
    
    sudo ln -sf "$PROJECT_ROOT/stream_load_tester.sh" /usr/local/bin/stream-load-tester
    sudo ln -sf "$PROJECT_ROOT/check_dependencies.sh" /usr/local/bin/stream-load-tester-check
    sudo ln -sf "$SCRIPT_DIR/cleanup.sh" /usr/local/bin/stream-load-tester-cleanup
    
    info "Created symlinks:"
    info "  stream-load-tester -> $PROJECT_ROOT/stream_load_tester.sh"
    info "  stream-load-tester-check -> $PROJECT_ROOT/check_dependencies.sh"
    info "  stream-load-tester-cleanup -> $SCRIPT_DIR/cleanup.sh"
}

verify_installation() {
    info "Verifying installation..."
    
    # Run FFmpeg requirement check
    if "$SCRIPT_DIR/ensure_ffmpeg_requirements.sh" --check-only; then
        info "FFmpeg requirements verified successfully"
        return 0
    else
        warn "FFmpeg requirements check failed"
        warn "Installation may need additional configuration"
        return 1
    fi
}

show_help() {
    cat <<EOF
Installation Script for Stream Load Tester

Usage: $0 [OPTIONS]

This script:
  - Makes all scripts executable
  - Ensures FFmpeg is installed with required codecs
  - Optionally creates system-wide symlinks

Options:
  -y, --yes           Skip confirmation prompts
  -v, --verbose       Verbose output
  -h, --help          Show this help message

Examples:
  $0                  # Interactive installation
  $0 --yes            # Automatic installation
  $0 --verbose        # Installation with detailed output

EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -y|--yes)
                SKIP_CONFIRMATION=true
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
    
    # Check if running as root
    if [[ $EUID -eq 0 ]]; then
        warn "Running as root is not recommended"
        warn "Consider running as a regular user with sudo access"
    fi
    
    # Confirm installation
    if [[ "$SKIP_CONFIRMATION" == "false" ]]; then
        echo "This will:"
        echo "  - Make all scripts executable"
        echo "  - Install FFmpeg with required codecs (if missing)"
        echo "  - Optionally create system-wide command symlinks"
        echo
        echo "Continue with installation? (y/N)"
        read -r response
        if [[ ! "$response" =~ ^[Yy] ]]; then
            info "Installation cancelled"
            exit 0
        fi
    fi
    
    echo
    make_scripts_executable
    
    echo
    info "Ensuring FFmpeg requirements..."
    if "$SCRIPT_DIR/ensure_ffmpeg_requirements.sh"; then
        info "FFmpeg requirements met"
    else
        error "Failed to ensure FFmpeg requirements"
        error "Please install FFmpeg manually or run:"
        error "  ./scripts/ensure_ffmpeg_requirements.sh"
        exit 1
    fi
    
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
        error "Please check the verification output above"
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
