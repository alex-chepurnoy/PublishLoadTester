#!/usr/bin/env bash
# Debug script to test get_server_heap function

SERVER_IP="54.67.101.210"
KEY_PATH="$HOME/AlexC_Dev2_EC2.pem"
SSH_USER="ubuntu"
SSH_OPTS="-q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"

java_bin="/usr/local/WowzaStreamingEngine/java/bin"

echo "=== Testing get_server_heap function ==="
echo ""

# Get Wowza PID
echo "Step 1: Getting Wowza PID..."
wowza_pid=$(timeout 10 ssh -i "$KEY_PATH" $SSH_OPTS "$SSH_USER@$SERVER_IP" \
  "ps aux | grep 'com.wowza.wms.bootstrap.Bootstrap start' | grep -v grep | awk '{print \$2}' | head -n1 || echo ''" 2>/dev/null || echo "")

if [[ -z "$wowza_pid" ]]; then
  echo "ERROR: Could not get Wowza PID"
  exit 1
fi

echo "Found Wowza PID: $wowza_pid"
echo ""

# Test jcmd command
echo "Step 2: Testing jcmd GC.heap_info..."
jcmd_output=$(timeout 10 ssh -i "$KEY_PATH" $SSH_OPTS "$SSH_USER@$SERVER_IP" \
  "sudo /usr/local/WowzaStreamingEngine/java/bin/jcmd $wowza_pid GC.heap_info" 2>&1)

echo "jcmd output:"
echo "$jcmd_output"
echo ""

# Test AWK parsing
echo "Step 3: Testing AWK parsing..."
heap_pct=$(echo "$jcmd_output" | awk '
  BEGIN { total_kb=0; used_kb=0 }
  /ZHeap|Z Heap/ {
    if ($0 ~ /used [0-9]+M/ || $0 ~ /capacity [0-9]+M/) {
      for(i=1; i<=NF; i++) {
        if ($i == "used" && $(i+1) ~ /^[0-9]+M/) {
          gsub(/[^0-9]/, "", $(i+1))
          used_kb = $(i+1) * 1024
          print "DEBUG: used_kb=" used_kb > "/dev/stderr"
        }
        if ($i == "capacity" && $(i+1) ~ /^[0-9]+M/ && $(i-1) !~ /max/) {
          gsub(/[^0-9]/, "", $(i+1))
          total_kb = $(i+1) * 1024
          print "DEBUG: total_kb=" total_kb > "/dev/stderr"
        }
      }
    }
  }
  END {
    print "DEBUG: Final total_kb=" total_kb ", used_kb=" used_kb > "/dev/stderr"
    if(total_kb > 0) printf "%.2f", (used_kb / total_kb) * 100
    else print "0.00"
  }
')

echo "Heap percentage: $heap_pct%"
echo ""

if [[ "$heap_pct" == "0.00" ]]; then
  echo "ERROR: Got 0.00% - parsing failed!"
else
  echo "SUCCESS: Got valid percentage"
fi
