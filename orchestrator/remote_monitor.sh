#!/usr/bin/env bash
# Remote monitoring script - runs ON the Wowza server
# Logs CPU, Heap, Memory, and Network metrics every 5 seconds
# This script is deployed and started by the orchestrator

set -euo pipefail

# Configuration
INTERVAL=5
LOG_DIR="${1:-/tmp/wowza_monitoring}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="$LOG_DIR/monitor_${TIMESTAMP}.log"

# Create log directory
mkdir -p "$LOG_DIR"

# Detect Wowza PID
get_wowza_pid() {
  # Get Wowza Engine PID (not Manager)
  # Look for com.wowza.wms.bootstrap.Bootstrap which is the actual streaming engine
  ps aux | grep 'com.wowza.wms.bootstrap.Bootstrap start' | grep -v grep | awk '{print $2}' | head -n1 || echo ""
}

# Get CPU usage
get_cpu() {
  python3 - <<'PY'
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
except Exception:
    print('0.00')
PY
}

# Get heap usage - returns "used_mb capacity_mb percentage"
get_heap() {
  local pid=$1
  local java_bin="/usr/local/WowzaStreamingEngine/java/bin"
  local result=""
  
  # Try jcmd with sudo (we know it needs sudo from diagnostics)
  # Supports all GC types: Parallel, G1, ZGC, Shenandoah
  
  # Try PATH jcmd with sudo first
  if command -v jcmd >/dev/null 2>&1; then
    result=$(sudo jcmd $pid GC.heap_info 2>&1 | awk '
      BEGIN { total_kb=0; used_kb=0 }
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
      /ZHeap/ {
        # ZGC format: "ZHeap used 194M, capacity 496M, max capacity 5416M"
        for(i=1; i<=NF; i++) {
          if ($i == "used" && $(i+1) ~ /^[0-9]+M/) {
            used_mb = $(i+1); gsub(/[^0-9]/, "", used_mb)
            used_kb = used_mb * 1024
          }
          if ($i == "capacity" && $(i+1) ~ /^[0-9]+M/ && $(i-1) !~ /max/) {
            cap_mb = $(i+1); gsub(/[^0-9]/, "", cap_mb)
            total_kb = cap_mb * 1024
          }
        }
      }
      /garbage-first heap|Shenandoah/ {
        # G1GC/Shenandoah format: "garbage-first heap   total 524288K, used 194288K"
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
        if(total_kb>0) {
          used_mb = used_kb / 1024
          capacity_mb = total_kb / 1024
          pct = (used_kb / total_kb) * 100
          printf "%.2f %.2f %.2f", used_mb, capacity_mb, pct
        } else {
          print "0.00 0.00 0.00"
        }
      }
    ' 2>/dev/null || echo "0.00 0.00 0.00")
  elif [ -x "$java_bin/jcmd" ]; then
    result=$(sudo $java_bin/jcmd $pid GC.heap_info 2>&1 | awk '
      BEGIN { total_kb=0; used_kb=0 }
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
      /ZHeap/ {
        for(i=1; i<=NF; i++) {
          if ($i == "used" && $(i+1) ~ /^[0-9]+M/) {
            used_mb = $(i+1); gsub(/[^0-9]/, "", used_mb)
            used_kb = used_mb * 1024
          }
          if ($i == "capacity" && $(i+1) ~ /^[0-9]+M/ && $(i-1) !~ /max/) {
            cap_mb = $(i+1); gsub(/[^0-9]/, "", cap_mb)
            total_kb = cap_mb * 1024
          }
        }
      }
      /garbage-first heap|Shenandoah/ {
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
        if(total_kb>0) {
          used_mb = used_kb / 1024
          capacity_mb = total_kb / 1024
          pct = (used_kb / total_kb) * 100
          printf "%.2f %.2f %.2f", used_mb, capacity_mb, pct
        } else {
          print "0.00 0.00 0.00"
        }
      }
    ' 2>/dev/null || echo "0.00 0.00 0.00")
  fi
  
  echo "${result:-0.00 0.00 0.00}"
}

# Get memory usage
get_memory() {
  free | grep Mem | awk '{printf "%.2f", ($3/$2)*100}'
}

# Get network throughput
get_network() {
  if command -v ifstat >/dev/null 2>&1; then
    # Use ifstat (KB/s incoming)
    ifstat -i eth0 1 1 2>/dev/null | tail -n1 | awk '{printf "%.2f", $2 * 0.0078125}' || echo "0.00"
  else
    # Fallback to sar (KB/s)
    sar -n DEV 1 1 2>/dev/null | grep -E 'eth0|ens' | grep -v Average | tail -n1 | awk '{printf "%.2f", $6 * 0.0078125}' || echo "0.00"
  fi
}

# Main monitoring loop
echo "Starting monitoring on $(hostname) at $(date)"
echo "Log file: $LOG_FILE"
echo "Interval: ${INTERVAL}s"
echo

# Write header (added HEAP_MAX_MB)
echo "TIMESTAMP,CPU_PCT,HEAP_USED_MB,HEAP_CAPACITY_MB,HEAP_MAX_MB,HEAP_PCT,MEM_PCT,NET_MBPS,WOWZA_PID" > "$LOG_FILE"

# Get initial PID
WOWZA_PID=$(get_wowza_pid)

if [[ -z "$WOWZA_PID" ]]; then
  echo "WARNING: Wowza process not detected. Heap monitoring will be unavailable."
  echo "Will continue monitoring CPU, Memory, and Network only."
fi

# Monitor continuously
while true; do
  TIMESTAMP=$(date +%Y-%m-%d_%H:%M:%S)
  
  # Re-detect PID if it was empty (Wowza might have started)
  if [[ -z "$WOWZA_PID" ]]; then
    WOWZA_PID=$(get_wowza_pid)
  fi
  
  # Get metrics
  CPU=$(get_cpu)
  MEM=$(get_memory)
  NET=$(get_network)
  
  if [[ -n "$WOWZA_PID" ]]; then
  # get_heap returns "used_mb capacity_mb max_mb percentage"
  HEAP_DATA=$(get_heap "$WOWZA_PID")
  HEAP_USED_MB=$(echo "$HEAP_DATA" | awk '{print $1}')
  HEAP_CAPACITY_MB=$(echo "$HEAP_DATA" | awk '{print $2}')
  HEAP_MAX_MB=$(echo "$HEAP_DATA" | awk '{print $3}')
  HEAP_PCT=$(echo "$HEAP_DATA" | awk '{print $4}')
  else
    HEAP_USED_MB="N/A"
    HEAP_CAPACITY_MB="N/A"
    HEAP_PCT="N/A"
  fi
  
  # Log to file
  echo "$TIMESTAMP,$CPU,$HEAP_USED_MB,$HEAP_CAPACITY_MB,$HEAP_MAX_MB,$HEAP_PCT,$MEM,$NET,$WOWZA_PID" >> "$LOG_FILE"
  
  # Also print to stdout (for debugging)
  echo "[$TIMESTAMP] CPU: ${CPU}% | Heap: ${HEAP_USED_MB}/${HEAP_CAPACITY_MB}MB (${HEAP_PCT}%) | Mem: ${MEM}% | Net: ${NET} Mbps | PID: ${WOWZA_PID:-N/A}"
  
  sleep $INTERVAL
done
