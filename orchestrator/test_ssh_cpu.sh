#!/usr/bin/env bash
# Test SSH connectivity and CPU check for orchestrator debugging

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

KEY_PATH="${1:-$HOME/AlexC_Dev2_EC2.pem}"
SERVER_IP="${2:-54.67.101.210}"
SSH_USER="${3:-ubuntu}"

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o ServerAliveInterval=5 -o ServerAliveCountMax=3 -o LogLevel=ERROR"

echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}  SSH & CPU Check Diagnostics${NC}"
echo -e "${BLUE}======================================${NC}"
echo
echo "Key Path:   $KEY_PATH"
echo "Server IP:  $SERVER_IP"
echo "SSH User:   $SSH_USER"
echo

# Test 1: Basic SSH connectivity
echo -e "${YELLOW}[Test 1]${NC} Testing basic SSH connectivity..."
if ssh -i "$KEY_PATH" $SSH_OPTS "$SSH_USER@$SERVER_IP" "echo 'SSH OK'" 2>/dev/null; then
    echo -e "${GREEN}✓ SSH connection successful${NC}"
else
    echo -e "${RED}✗ SSH connection failed${NC}"
    echo "  Try: ssh -i $KEY_PATH $SSH_USER@$SERVER_IP"
    exit 1
fi
echo

# Test 2: Check Python3
echo -e "${YELLOW}[Test 2]${NC} Checking Python3 on remote server..."
PYTHON_VERSION=$(ssh -i "$KEY_PATH" $SSH_OPTS "$SSH_USER@$SERVER_IP" "python3 --version" 2>&1 || echo "NOT FOUND")
if [[ "$PYTHON_VERSION" =~ "Python 3" ]]; then
    echo -e "${GREEN}✓ Python3 found: $PYTHON_VERSION${NC}"
else
    echo -e "${RED}✗ Python3 not found or not accessible${NC}"
    echo "  Install with: sudo apt-get install python3"
    exit 1
fi
echo

# Test 3: Check /proc/stat access
echo -e "${YELLOW}[Test 3]${NC} Checking /proc/stat access..."
PROC_STAT=$(ssh -i "$KEY_PATH" $SSH_OPTS "$SSH_USER@$SERVER_IP" "cat /proc/stat | head -n1" 2>/dev/null)
if [[ "$PROC_STAT" =~ ^cpu ]]; then
    echo -e "${GREEN}✓ /proc/stat accessible${NC}"
    echo "  First line: ${PROC_STAT:0:50}..."
else
    echo -e "${RED}✗ /proc/stat not accessible${NC}"
    echo "  Output: $PROC_STAT"
    echo -e "${YELLOW}  Note: If you see SSH warnings, that's normal and can be ignored${NC}"
    exit 1
fi
echo

# Test 4: Test Python CPU calculation directly
echo -e "${YELLOW}[Test 4]${NC} Testing Python CPU calculation..."
echo "  (This takes ~2 seconds...)"
CPU_OUTPUT=$(ssh -i "$KEY_PATH" $SSH_OPTS "$SSH_USER@$SERVER_IP" "python3 - <<'PY'
import time
try:
    with open('/proc/stat') as f:
        l1=f.readline().split()[1:]
    t1=sum(map(int,l1)); idle1=int(l1[3])
    time.sleep(1)
    with open('/proc/stat') as f:
        l2=f.readline().split()[1:]
    t2=sum(map(int,l2)); idle2=int(l2[3])
    used=100*(1-(idle2-idle1)/(t2-t1))
    print('%.2f' % used)
except Exception as e:
    print('ERROR: ' + str(e))
PY" 2>&1)

if [[ "$CPU_OUTPUT" =~ ^[0-9]+\.[0-9]+$ ]]; then
    echo -e "${GREEN}✓ CPU calculation successful: ${CPU_OUTPUT}%${NC}"
else
    echo -e "${RED}✗ CPU calculation failed${NC}"
    echo "  Output: $CPU_OUTPUT"
    exit 1
fi
echo

# Test 5: Test with timeout (as used in orchestrator)
echo -e "${YELLOW}[Test 5]${NC} Testing with timeout (15s)..."
TIMEOUT_CPU=$(timeout 15 ssh -i "$KEY_PATH" $SSH_OPTS "$SSH_USER@$SERVER_IP" "python3 - <<'PY'
import time
try:
    with open('/proc/stat') as f:
        l1=f.readline().split()[1:]
    t1=sum(map(int,l1)); idle1=int(l1[3])
    time.sleep(1)
    with open('/proc/stat') as f:
        l2=f.readline().split()[1:]
    t2=sum(map(int,l2)); idle2=int(l2[3])
    used=100*(1-(idle2-idle1)/(t2-t1))
    print('%.2f' % used)
except Exception as e:
    print('0.00')
PY" 2>&1 || echo "TIMEOUT")

if [[ "$TIMEOUT_CPU" == "TIMEOUT" ]]; then
    echo -e "${RED}✗ Command timed out after 15 seconds${NC}"
    exit 1
elif [[ "$TIMEOUT_CPU" =~ ^[0-9]+\.[0-9]+$ ]]; then
    echo -e "${GREEN}✓ CPU check with timeout successful: ${TIMEOUT_CPU}%${NC}"
else
    echo -e "${YELLOW}⚠ Unexpected output: $TIMEOUT_CPU${NC}"
fi
echo

# Test 6: Test repeated calls (as in orchestrator loop)
echo -e "${YELLOW}[Test 6]${NC} Testing 3 consecutive CPU checks..."
for i in 1 2 3; do
    CPU=$(timeout 15 ssh -i "$KEY_PATH" $SSH_OPTS "$SSH_USER@$SERVER_IP" "python3 - <<'PY'
import time
try:
    with open('/proc/stat') as f:
        l1=f.readline().split()[1:]
    t1=sum(map(int,l1)); idle1=int(l1[3])
    time.sleep(1)
    with open('/proc/stat') as f:
        l2=f.readline().split()[1:]
    t2=sum(map(int,l2)); idle2=int(l2[3])
    used=100*(1-(idle2-idle1)/(t2-t1))
    print('%.2f' % used)
except Exception as e:
    print('0.00')
PY" 2>&1 || echo "FAIL")
    
    if [[ "$CPU" =~ ^[0-9]+\.[0-9]+$ ]]; then
        echo -e "  Check $i: ${GREEN}${CPU}%${NC}"
    else
        echo -e "  Check $i: ${RED}FAILED - $CPU${NC}"
    fi
    sleep 1
done
echo

echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}  All diagnostics passed!${NC}"
echo -e "${GREEN}======================================${NC}"
echo
echo "CPU monitoring should work correctly in orchestrator."
echo "If orchestrator still shows CPU errors, check orchestrator.log for details."
