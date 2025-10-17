#!/bin/bash
# Diagnostic script to troubleshoot jcmd issues

if [ $# -lt 3 ]; then
  echo "Usage: $0 <server-ip> <ssh-key> <ssh-user>"
  echo "Example: $0 54.123.45.67 ~/.ssh/mykey.pem ubuntu"
  exit 1
fi

SERVER_IP="$1"
KEY_PATH="$2"
SSH_USER="$3"
SSH_OPTS="-q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"

echo "=========================================="
echo "jcmd Diagnostic Tool"
echo "=========================================="
echo

echo "1. Finding Wowza Engine process..."
WOWZA_INFO=$(ssh -i "$KEY_PATH" $SSH_OPTS "$SSH_USER@$SERVER_IP" \
  "ps aux | grep 'com.wowza.wms.bootstrap.Bootstrap start' | grep -v grep | head -n1")

if [ -z "$WOWZA_INFO" ]; then
  echo "  ✗ No Wowza Engine process found!"
  echo "  Make sure Wowza Streaming Engine is running on the server."
  echo "  Note: Looking for 'com.wowza.wms.bootstrap.Bootstrap start' (not Manager)"
  exit 1
fi

WOWZA_PID=$(echo "$WOWZA_INFO" | awk '{print $2}')
WOWZA_USER=$(echo "$WOWZA_INFO" | awk '{print $1}')

echo "  ✓ Found Wowza:"
echo "    PID: $WOWZA_PID"
echo "    User: $WOWZA_USER"
echo "    Command: $(echo "$WOWZA_INFO" | awk '{for(i=11;i<=NF;i++) printf "%s ", $i; print ""}')"
echo

echo "2. Checking jcmd availability..."
JCMD_CHECK=$(ssh -i "$KEY_PATH" $SSH_OPTS "$SSH_USER@$SERVER_IP" \
  'JAVA_BIN="/usr/local/WowzaStreamingEngine/java/bin"; \
   if command -v jcmd >/dev/null 2>&1; then \
     echo "PATH:$(which jcmd)"; \
   elif [ -x "$JAVA_BIN/jcmd" ]; then \
     echo "WOWZA:$JAVA_BIN/jcmd"; \
   else \
     echo "MISSING"; \
   fi')

if [ "$JCMD_CHECK" = "MISSING" ]; then
  echo "  ✗ jcmd not found!"
  echo "  Install with: sudo apt-get install openjdk-11-jdk-headless"
  exit 1
fi

echo "  ✓ jcmd found at: ${JCMD_CHECK#*:}"
JCMD_PATH="${JCMD_CHECK#*:}"
echo

echo "3. Testing jcmd access with current user ($SSH_USER)..."
JCMD_TEST=$(ssh -i "$KEY_PATH" $SSH_OPTS "$SSH_USER@$SERVER_IP" \
  "$JCMD_PATH $WOWZA_PID GC.heap_info 2>&1 | head -25")

echo "Output:"
echo "----------------------------------------"
echo "$JCMD_TEST"
echo "----------------------------------------"
echo

if echo "$JCMD_TEST" | grep -q "PSYoungGen\|ParOldGen\|PSOldGen"; then
  echo "  ✓ SUCCESS! jcmd returned heap data"
  
  # Test parsing
  echo
  echo "4. Testing AWK parsing..."
  PARSED=$(echo "$JCMD_TEST" | awk '
    /PSYoungGen|ParOldGen|PSOldGen/ {
      if ($0 ~ /total [0-9]+K/) {
        for(i=1; i<=NF; i++) {
          if ($i == "total" && $(i+1) ~ /^[0-9]+K/) {
            gsub(/K/, "", $(i+1))
            total_kb += $(i+1)
          }
          if ($i == "used" && $(i+1) ~ /^[0-9]+K/) {
            gsub(/K/, "", $(i+1))
            used_kb += $(i+1)
          }
        }
      }
    }
    END {
      printf "Total: %d KB, Used: %d KB\n", total_kb, used_kb
      if(total_kb > 0) printf "Percentage: %.2f%%\n", (used_kb / total_kb) * 100
      else print "Percentage: 0.00%"
    }
  ')
  echo "  $PARSED"
  
elif echo "$JCMD_TEST" | grep -qi "permission denied\|unable to open\|not allowed\|Operation not permitted"; then
  echo "  ✗ PERMISSION DENIED (expected for user $SSH_USER accessing $WOWZA_USER process)"
  echo
  echo "4. Testing jcmd with sudo..."
  JCMD_SUDO_TEST=$(ssh -i "$KEY_PATH" $SSH_OPTS "$SSH_USER@$SERVER_IP" \
    "sudo $JCMD_PATH $WOWZA_PID GC.heap_info 2>&1 | head -25")
  
  echo "Output:"
  echo "----------------------------------------"
  echo "$JCMD_SUDO_TEST"
  echo "----------------------------------------"
  echo
  
  if echo "$JCMD_SUDO_TEST" | grep -q "PSYoungGen\|ParOldGen\|PSOldGen\|garbage-first heap\|ZHeap\|Z Heap\|Shenandoah"; then
    echo "  ✓ SUCCESS! sudo jcmd works"
    
    # Test parsing
    echo
    echo "5. Testing AWK parsing..."
    PARSED=$(echo "$JCMD_SUDO_TEST" | awk '
      # Parallel GC format
      /PSYoungGen|ParOldGen|PSOldGen/ {
        if ($0 ~ /total [0-9]+K/) {
          for(i=1; i<=NF; i++) {
            if ($i == "total" && $(i+1) ~ /^[0-9]+K/) {
              gsub(/K/, "", $(i+1))
              total_kb += $(i+1)
            }
            if ($i == "used" && $(i+1) ~ /^[0-9]+K/) {
              gsub(/K/, "", $(i+1))
              used_kb += $(i+1)
            }
          }
        }
      }
      # G1GC/ZGC/Shenandoah format
      /garbage-first heap|ZHeap|Z Heap|Shenandoah/ {
        if ($0 ~ /total [0-9]+K.*used [0-9]+K/ || $0 ~ /used [0-9]+K.*total [0-9]+K/) {
          for(i=1; i<=NF; i++) {
            if ($i == "total" && $(i+1) ~ /^[0-9]+K/) {
              gsub(/[^0-9]/, "", $(i+1))
              total_kb = $(i+1)
            }
            if ($i == "used" && $(i+1) ~ /^[0-9]+K/) {
              gsub(/[^0-9]/, "", $(i+1))
              used_kb = $(i+1)
            }
          }
        }
      }
      END {
        printf "Total: %d KB, Used: %d KB\n", total_kb, used_kb
        if(total_kb > 0) printf "Percentage: %.2f%%\n", (used_kb / total_kb) * 100
        else print "Percentage: 0.00%"
      }
    ')
    echo "  $PARSED"
    echo
    echo "  ✅ Your monitoring scripts will work with sudo!"
  else
    echo "  ✗ sudo jcmd also failed"
    echo
    echo "  Troubleshooting:"
    echo "  1. Verify passwordless sudo is configured:"
    echo "     ssh $SSH_USER@$SERVER_IP sudo -n jcmd -h"
    echo "  2. Check sudoers file exists:"
    echo "     ssh $SSH_USER@$SERVER_IP ls -la /etc/sudoers.d/java-monitoring"
    echo "  3. Re-run setup:"
    echo "     scp setup_sudo.sh $SSH_USER@$SERVER_IP:~/"
    echo "     ssh $SSH_USER@$SERVER_IP ./setup_sudo.sh"
  fi
elif echo "$JCMD_TEST" | grep -qi "No such process\|does not exist"; then
  echo "  ✗ PROCESS NOT FOUND"
  echo "  PID $WOWZA_PID may have changed. Wowza might have restarted."
else
  echo "  ✗ UNEXPECTED ERROR"
  echo "  Check the output above for clues."
  echo
  echo "4. Testing jcmd with sudo anyway..."
  JCMD_SUDO_TEST=$(ssh -i "$KEY_PATH" $SSH_OPTS "$SSH_USER@$SERVER_IP" \
    "sudo $JCMD_PATH $WOWZA_PID GC.heap_info 2>&1 | head -25")
  
  if echo "$JCMD_SUDO_TEST" | grep -q "PSYoungGen\|ParOldGen\|PSOldGen"; then
    echo "  ✓ sudo jcmd works!"
    echo
    PARSED=$(echo "$JCMD_SUDO_TEST" | awk '
      /PSYoungGen|ParOldGen|PSOldGen/ {
        if ($0 ~ /total [0-9]+K/) {
          for(i=1; i<=NF; i++) {
            if ($i == "total" && $(i+1) ~ /^[0-9]+K/) {
              gsub(/K/, "", $(i+1))
              total_kb += $(i+1)
            }
            if ($i == "used" && $(i+1) ~ /^[0-9]+K/) {
              gsub(/K/, "", $(i+1))
              used_kb += $(i+1)
            }
          }
        }
      }
      END {
        printf "Total: %d KB, Used: %d KB\n", total_kb, used_kb
        if(total_kb > 0) printf "Percentage: %.2f%%\n", (used_kb / total_kb) * 100
        else print "Percentage: 0.00%"
      }
    ')
    echo "  $PARSED"
  fi
fi

echo
echo "=========================================="
echo "Diagnostic Complete"
echo "=========================================="
