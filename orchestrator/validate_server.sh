#!/usr/bin/env bash
# Quick validation script to check monitoring tools and Wowza process on server
# Usage: ./validate_server.sh <ssh_key> <user@host>

set -euo pipefail

if [ $# -lt 2 ]; then
  echo "Usage: $0 <ssh_key_path> <user@host>"
  echo "Example: $0 ~/key.pem ubuntu@54.67.101.210"
  exit 1
fi

KEY="$1"
HOST="$2"
SSH_OPTS="-q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"

echo "=== Validating Monitoring Setup on $HOST ==="
echo

echo "0. Checking local Python3 (required for parsing)..."
if command -v python3 >/dev/null 2>&1; then
  echo "  ✓ python3 $(python3 --version 2>&1)"
else
  echo "  ✗ python3 NOT FOUND (orchestrator will skip parsing results)"
  echo "    Install: apt-get install python3 (Ubuntu) or brew install python3 (macOS)"
fi
echo

echo "1. Checking monitoring tools availability on server..."
ssh -i "$KEY" $SSH_OPTS "$HOST" 'for cmd in pidstat sar ps grep awk; do if command -v $cmd >/dev/null 2>&1; then echo "  ✓ $cmd"; else echo "  ✗ $cmd MISSING"; fi; done'
echo

echo "2. Checking Java heap monitoring tools..."
ssh -i "$KEY" $SSH_OPTS "$HOST" 'JAVA_BIN="/usr/local/WowzaStreamingEngine/java/bin"; for cmd in jcmd jstat jmap; do if command -v $cmd >/dev/null 2>&1; then echo "  ✓ $cmd (in PATH)"; elif [ -x "$JAVA_BIN/$cmd" ]; then echo "  ✓ $cmd (in $JAVA_BIN)"; else echo "  ✗ $cmd MISSING"; fi; done'
echo

echo "3. Checking optional tools..."
ssh -i "$KEY" $SSH_OPTS "$HOST" 'if command -v ifstat >/dev/null 2>&1; then echo "  ✓ ifstat (optional)"; else echo "  ⚠ ifstat not found (will use sar instead)"; fi'
echo

echo "4. Testing sar network monitoring..."
ssh -i "$KEY" $SSH_OPTS "$HOST" 'sar -n DEV 1 1 | head -10' || echo "  ✗ sar -n DEV failed"
echo

echo "4. Testing sar network monitoring..."
ssh -i "$KEY" $SSH_OPTS "$HOST" 'sar -n DEV 1 1 | head -10' || echo "  ✗ sar -n DEV failed"
echo

echo "5. Detecting Wowza Engine process..."
WOWZA_PID=$(ssh -i "$KEY" $SSH_OPTS "$HOST" "ps aux | grep 'com.wowza.wms.bootstrap.Bootstrap start' | grep -v grep | awk '{print \$2}' | head -n1 || echo ''")
if [ -n "$WOWZA_PID" ]; then
  echo "  ✓ Found Wowza Engine PID: $WOWZA_PID"
  echo "  Process details:"
  ssh -i "$KEY" $SSH_OPTS "$HOST" "ps -p $WOWZA_PID -o pid,rss,vsz,pmem,pcpu,cmd"
else
  echo "  ✗ Wowza Engine process not found (com.wowza.wms.bootstrap.Bootstrap)"
  echo "  All Java processes:"
  ssh -i "$KEY" $SSH_OPTS "$HOST" "ps aux | grep java | grep -v grep | head -5"
fi
echo

echo "6. Testing Java heap monitoring (if Wowza found)..."
if [ -n "$WOWZA_PID" ]; then
  JAVA_BIN="/usr/local/WowzaStreamingEngine/java/bin"
  
  echo "  Testing jcmd GC.heap_info..."
  JCMD_OUTPUT=$(ssh -i "$KEY" $SSH_OPTS "$HOST" "{ command -v jcmd >/dev/null 2>&1 && jcmd $WOWZA_PID GC.heap_info; } || { [ -x $JAVA_BIN/jcmd ] && $JAVA_BIN/jcmd $WOWZA_PID GC.heap_info; } 2>&1 | head -20")
  if [ $? -eq 0 ] && echo "$JCMD_OUTPUT" | grep -q "PSYoungGen\|ParOldGen\|PSOldGen"; then
    echo "  ✓ jcmd works"
    echo "$JCMD_OUTPUT" | head -5
  else
    echo "  ✗ jcmd failed or returned unexpected format"
    echo "  Output: $JCMD_OUTPUT" | head -3
  fi
  
  echo "  Testing jstat -gc..."
  JSTAT_OUTPUT=$(ssh -i "$KEY" $SSH_OPTS "$HOST" "{ command -v jstat >/dev/null 2>&1 && jstat -gc $WOWZA_PID; } || { [ -x $JAVA_BIN/jstat ] && $JAVA_BIN/jstat -gc $WOWZA_PID; } 2>&1 | head -5")
  if [ $? -eq 0 ] && echo "$JSTAT_OUTPUT" | grep -qE "S0C|EC|OU"; then
    echo "  ✓ jstat works"
  else
    echo "  ✗ jstat failed"
    echo "  Output: $JSTAT_OUTPUT"
  fi
  
  echo "  Testing jmap -heap (brief check only)..."
  JMAP_OUTPUT=$(ssh -i "$KEY" $SSH_OPTS "$HOST" "timeout 5 bash -c '{ command -v jmap >/dev/null 2>&1 && jmap -heap $WOWZA_PID; } || { [ -x $JAVA_BIN/jmap ] && $JAVA_BIN/jmap -heap $WOWZA_PID; }' 2>&1 | head -10")
  if [ $? -eq 0 ] && echo "$JMAP_OUTPUT" | grep -q "Heap Configuration\|using"; then
    echo "  ✓ jmap works (emergency fallback available)"
  else
    echo "  ✗ jmap failed"
    echo "  Output: $JMAP_OUTPUT" | head -3
  fi
else
  echo "  ⚠ Skipping (no Wowza PID detected)"
fi
echo

echo "7. Testing pidstat on detected Wowza PID..."
if [ -n "$WOWZA_PID" ]; then
  ssh -i "$KEY" $SSH_OPTS "$HOST" "pidstat -h -u -r 1 1 -p $WOWZA_PID" || echo "  ✗ pidstat failed"
else
  echo "  ⚠ Skipping (no PID detected)"
fi
echo

echo "8. Checking for common Wowza patterns..."
echo "  All Wowza-related processes:"
ssh -i "$KEY" $SSH_OPTS "$HOST" "ps aux | grep -i wowza | grep -v grep" || echo "  (none found)"
echo

echo "=== Validation Complete ==="
echo
if [ -n "$WOWZA_PID" ]; then
  echo "✓ Server appears ready for orchestrated load testing"
  echo "  Wowza PID: $WOWZA_PID"
else
  echo "⚠ Wowza process not detected - please verify Wowza is running"
fi
