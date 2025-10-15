#!/bin/bash

#############################################################################
# Quick Fix for Python WebRTC Package Installation
# 
# Description: Standalone script to fix the externally-managed-environment
#              error by setting up a virtual environment for WebRTC packages
#
# Usage: ./fix_python_packages.sh
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

info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

main() {
    echo -e "${BLUE}Python WebRTC Package Fix${NC}"
    echo "=========================="
    echo
    
    # Get script directory
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local project_dir="$(cd "$script_dir/.." && pwd)"
    
    info "Fixing Python WebRTC package installation..."
    
    # Install python3-full if on Ubuntu/Debian
    if command -v apt >/dev/null 2>&1; then
        info "Installing python3-full (required for venv on newer Ubuntu/Debian)..."
        sudo apt update
        sudo apt install -y python3-full python3-venv
    fi
    
    # Create virtual environment
    local venv_path="$HOME/.local/share/stream-load-tester-venv"
    
    if [[ -d "$venv_path" ]]; then
        warn "Virtual environment already exists at $venv_path"
        echo "Remove existing environment and recreate? (y/N)"
        read -r response
        if [[ "$response" =~ ^[Yy] ]]; then
            rm -rf "$venv_path"
        else
            info "Using existing virtual environment"
        fi
    fi
    
    if [[ ! -d "$venv_path" ]]; then
        info "Creating virtual environment at $venv_path..."
        python3 -m venv "$venv_path"
    fi
    
    # Install packages
    info "Installing WebRTC packages in virtual environment..."
    "$venv_path/bin/pip" install --upgrade pip
    "$venv_path/bin/pip" install aiortc aiohttp websockets
    
    # Create wrapper script
    local wrapper_script="$HOME/.local/bin/stream-load-tester-webrtc"
    info "Creating wrapper script at $wrapper_script..."
    
    mkdir -p "$(dirname "$wrapper_script")"
    
    cat > "$wrapper_script" << 'EOF'
#!/bin/bash
# Wrapper script to run WebRTC publisher with virtual environment
VENV_PATH="$HOME/.local/share/stream-load-tester-venv"
if [[ -f "$VENV_PATH/bin/python" ]]; then
    exec "$VENV_PATH/bin/python" "$@"
else
    echo "Error: Virtual environment not found at $VENV_PATH"
    echo "Please run the fix script again."
    exit 1
fi
EOF
    
    chmod +x "$wrapper_script"
    
    # Update webrtc_publisher.py if it exists
    if [[ -f "$project_dir/webrtc_publisher.py" ]]; then
        info "Updating webrtc_publisher.py to use virtual environment..."
        
        # Create backup
        cp "$project_dir/webrtc_publisher.py" "$project_dir/webrtc_publisher.py.bak"
        
        # Update shebang
        sed -i "1s|.*|#!$wrapper_script|" "$project_dir/webrtc_publisher.py"
        
        info "Created backup: webrtc_publisher.py.bak"
    fi
    
    # Test the installation
    info "Testing WebRTC package installation..."
    if "$venv_path/bin/python" -c "import aiortc, aiohttp, websockets; print('All packages imported successfully!')" 2>/dev/null; then
        info "✅ WebRTC packages installed successfully!"
    else
        error "❌ Package installation test failed"
        exit 1
    fi
    
    echo
    info "🎉 Python WebRTC package fix completed!"
    info "Virtual environment: $venv_path"
    info "Wrapper script: $wrapper_script"
    
    # Add PATH recommendation
    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        echo
        warn "Consider adding $HOME/.local/bin to your PATH:"
        echo "echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc"
        echo "source ~/.bashrc"
    fi
    
    echo
    info "You can now run the dependency checker to verify:"
    info "  ./check_dependencies.sh webrtc"
    echo
    info "Or run the main script:"
    info "  ./stream_load_tester.sh"
}

# Execute main function
main "$@"