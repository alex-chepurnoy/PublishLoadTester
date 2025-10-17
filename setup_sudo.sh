#!/bin/bash
# Setup passwordless sudo for Java monitoring tools
# Run this on the EC2 server

USER="${1:-ubuntu}"

echo "=========================================="
echo "Java Monitoring Sudo Setup"
echo "=========================================="
echo "User: $USER"
echo

# Check if running with sudo privileges
if [ "$EUID" -ne 0 ] && ! sudo -n true 2>/dev/null; then
  echo "Error: This script needs sudo access."
  echo "Please ensure you can run sudo commands."
  exit 1
fi

echo "Creating sudoers configuration..."

sudo tee /etc/sudoers.d/java-monitoring > /dev/null <<EOF
# Java monitoring tools - passwordless sudo
# Created by setup_sudo.sh for load testing orchestration
# Allows $USER to run Java monitoring tools without password

# Standard JDK locations
$USER ALL=(ALL) NOPASSWD: /usr/bin/jcmd
$USER ALL=(ALL) NOPASSWD: /usr/bin/jstat
$USER ALL=(ALL) NOPASSWD: /usr/bin/jmap

# Wowza bundled JDK locations
$USER ALL=(ALL) NOPASSWD: /usr/local/WowzaStreamingEngine/java/bin/jcmd
$USER ALL=(ALL) NOPASSWD: /usr/local/WowzaStreamingEngine/java/bin/jstat
$USER ALL=(ALL) NOPASSWD: /usr/local/WowzaStreamingEngine/java/bin/jmap

# Alternative paths (if installed elsewhere)
$USER ALL=(ALL) NOPASSWD: /opt/java/*/bin/jcmd
$USER ALL=(ALL) NOPASSWD: /opt/java/*/bin/jstat
$USER ALL=(ALL) NOPASSWD: /opt/java/*/bin/jmap
EOF

echo "Setting permissions..."
sudo chmod 440 /etc/sudoers.d/java-monitoring

echo "Validating sudoers syntax..."
sudo visudo -c -f /etc/sudoers.d/java-monitoring

if [ $? -ne 0 ]; then
  echo "✗ Error: Syntax error in sudoers file!"
  echo "Removing invalid file..."
  sudo rm /etc/sudoers.d/java-monitoring
  exit 1
fi

echo "✓ Sudoers file created successfully"
echo

echo "Testing sudo access..."

# Test jcmd
if command -v jcmd >/dev/null 2>&1; then
  echo -n "  Testing sudo jcmd... "
  if sudo -n jcmd -h >/dev/null 2>&1; then
    echo "✓ Works"
  else
    echo "✗ Failed"
  fi
elif [ -x "/usr/local/WowzaStreamingEngine/java/bin/jcmd" ]; then
  echo -n "  Testing sudo jcmd (Wowza)... "
  if sudo -n /usr/local/WowzaStreamingEngine/java/bin/jcmd -h >/dev/null 2>&1; then
    echo "✓ Works"
  else
    echo "✗ Failed"
  fi
else
  echo "  ⚠ jcmd not found (will be tested when Wowza runs)"
fi

# Test jstat
if command -v jstat >/dev/null 2>&1; then
  echo -n "  Testing sudo jstat... "
  if sudo -n jstat -help >/dev/null 2>&1; then
    echo "✓ Works"
  else
    echo "✗ Failed"
  fi
elif [ -x "/usr/local/WowzaStreamingEngine/java/bin/jstat" ]; then
  echo -n "  Testing sudo jstat (Wowza)... "
  if sudo -n /usr/local/WowzaStreamingEngine/java/bin/jstat -help >/dev/null 2>&1; then
    echo "✓ Works"
  else
    echo "✗ Failed"
  fi
else
  echo "  ⚠ jstat not found (will be tested when Wowza runs)"
fi

echo
echo "=========================================="
echo "Setup Complete!"
echo "=========================================="
echo
echo "Next steps:"
echo "1. Start Wowza if not already running"
echo "2. From your client machine, run:"
echo "   ./orchestrator/diagnose_jcmd.sh <server-ip> <key> $USER"
echo "3. Run validation:"
echo "   ./orchestrator/validate_server.sh"
echo "4. Test with pilot mode:"
echo "   ./orchestrator/run_orchestration.sh --pilot"
echo
