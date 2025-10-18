#!/usr/bin/env bash
# Orchestration script to run stream_load_tester.sh experiments and collect server stats via SSH
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
STREAM_TOOL="$ROOT_DIR/stream_load_tester.sh"
RUNS_DIR="$SCRIPT_DIR/runs"

# Orchestrator log (early definition so log() can be used during setup)
ORCH_LOG="$RUNS_DIR/orchestrator.log"
mkdir -p "$(dirname "$ORCH_LOG")"
touch "$ORCH_LOG"

log() {
  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  echo "[$ts] $*" | tee -a "$ORCH_LOG" >&2
}

# SSH options used for all ssh/scp calls; define early so check_ssh_connectivity can use it
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o ServerAliveInterval=5 -o ServerAliveCountMax=3 -o LogLevel=ERROR"

# Phase 1: Timing windows updated to 15-minute tests (TEST_MATRIX specification)
# Full test runs: 15 minutes per test
WARMUP=60
STEADY=840  # 14 minutes (15 min total - 1 min warmup)
COOLDOWN=30
TOTAL_SECONDS=$((WARMUP + STEADY + COOLDOWN))
# stream_load_tester.sh takes minutes (integer)
DURATION_MINUTES=$(( (TOTAL_SECONDS + 59) / 60 ))  # Results in 15 minutes

# Pilot mode timing (shorter for quick validation - 2 minutes)
PILOT_WARMUP=15
PILOT_STEADY=90
PILOT_COOLDOWN=15
PILOT_TOTAL_SECONDS=$((PILOT_WARMUP + PILOT_STEADY + PILOT_COOLDOWN))
PILOT_DURATION_MINUTES=$(( (PILOT_TOTAL_SECONDS + 59) / 60 ))  # Results in 2 minutes

DEFAULT_KEY="$HOME/AlexC_Dev2_EC2.pem"

echo "--- Stream Load Orchestrator ---"

# Check dependencies early (including Python3)
SCRIPTS_DIR="$ROOT_DIR/scripts"
if [[ -f "$SCRIPTS_DIR/check_dependencies.sh" ]]; then
  log "Checking local dependencies (Bash, Python3, FFmpeg)..."
  if ! "$SCRIPTS_DIR/check_dependencies.sh" >/dev/null 2>&1; then
    log "Some dependencies are missing or incomplete"
    echo ""
    echo -e "${YELLOW}Some dependencies are missing or incomplete.${NC}"
    echo "The orchestrator requires:"
    echo "  - Python3 (for result parsing and CSV generation)"
    echo "  - FFmpeg (for stream generation)"
    echo ""
    read -p "Run automatic installation? (Y/n): " run_install
    if [[ ! "$run_install" =~ ^[Nn] ]]; then
      log "Running automatic installation..."
      if "$SCRIPTS_DIR/install.sh" --yes 2>&1 | tee -a "$ORCH_LOG"; then
        log "Installation completed successfully"
        # Re-check dependencies
        if ! "$SCRIPTS_DIR/check_dependencies.sh" >/dev/null 2>&1; then
          log "WARNING: Some dependencies still missing after installation"
          echo -e "${YELLOW}Warning: Some dependencies still missing. Check the log above.${NC}"
          read -p "Continue anyway? (y/N): " continue_anyway
          if [[ ! "$continue_anyway" =~ ^[Yy] ]]; then
            echo "Aborting."
            exit 1
          fi
        fi
      else
        log "Installation failed"
        echo -e "${RED}Installation failed. Please install dependencies manually:${NC}"
        echo "  - Python3: sudo apt-get install python3"
        echo "  - FFmpeg: ./scripts/ensure_ffmpeg_requirements.sh"
        exit 1
      fi
    else
      log "User skipped installation"
      echo -e "${YELLOW}Continuing without automatic installation...${NC}"
      echo "Warning: Results may not be parsed without Python3"
      sleep 2
    fi
  else
    log "All local dependencies verified"
  fi
else
  log "WARNING: check_dependencies.sh not found, skipping dependency check"
fi

read -p "Path to SSH key (.pem) [${DEFAULT_KEY}]: " KEY_PATH
KEY_PATH="${KEY_PATH:-$DEFAULT_KEY}"

if [[ ! -f "$KEY_PATH" ]]; then
  echo "Warning: key file not found at $KEY_PATH" >&2
  read -p "Continue anyway? (y/N): " cont
  if [[ ! "$cont" =~ ^[Yy] ]]; then
    echo "Aborting."; exit 1
  fi
fi

# Ensure private key has safe permissions. If not, copy to a temp file with 600 perms and use that.
TEMP_KEY=""
if [[ -f "$KEY_PATH" ]]; then
  # First try to tighten the permissions in-place
  if chmod 600 "$KEY_PATH" 2>/dev/null; then
    log "Set permissions 600 on key: $KEY_PATH"
  else
    log "Could not chmod key in-place (filesystem may not support chmod). Will create a secure temporary copy."
  fi

  perms=$(stat -c '%a' "$KEY_PATH" 2>/dev/null || stat -f '%A' "$KEY_PATH" 2>/dev/null || echo "")
  # If we couldn't determine numeric perms or they are > 600, make a secure temp copy
  if [[ -z "$perms" || ! "$perms" =~ ^[0-9]+$ ]] || (( perms > 600 )); then
    log "Key $KEY_PATH still has permissive mode ($perms). Creating a secure temp copy."
    TEMP_KEY=$(mktemp -p "$RUNS_DIR" key.XXXXXX.pem)
    cp "$KEY_PATH" "$TEMP_KEY"
    chmod 600 "$TEMP_KEY" || true
    KEY_PATH="$TEMP_KEY"
    log "Using temporary secure key: $KEY_PATH"
  fi
fi

read -p "SSH user for Wowza host [ubuntu]: " SSH_USER
SSH_USER="${SSH_USER:-ubuntu}"

read -p "Wowza server IP/address: " SERVER_IP
if [[ -z "$SERVER_IP" ]]; then echo "Server IP required"; exit 1; fi

echo ""
echo "Protocol-specific configuration (RTMP):"
read -p "  RTMP application name [live]: " RTMP_APP_NAME
RTMP_APP_NAME="${RTMP_APP_NAME:-live}"
read -p "  RTMP port [1935]: " RTMP_PORT
RTMP_PORT="${RTMP_PORT:-1935}"

echo ""
echo "Protocol-specific configuration (SRT):"
read -p "  SRT application name [live]: " SRT_APP_NAME
SRT_APP_NAME="${SRT_APP_NAME:-live}"
read -p "  SRT port [9999]: " SRT_PORT
SRT_PORT="${SRT_PORT:-9999}"

echo ""
echo "Protocol-specific configuration (RTSP):"
read -p "  RTSP application name [live]: " RTSP_APP_NAME
RTSP_APP_NAME="${RTSP_APP_NAME:-live}"
read -p "  RTSP port [554]: " RTSP_PORT
RTSP_PORT="${RTSP_PORT:-554}"

echo ""
read -p "Base stream name (test stream prefix) [test]: " STREAM_BASE
STREAM_BASE="${STREAM_BASE:-test}"

# Quick SSH connectivity check before starting the sweep. This avoids repeated retries
check_ssh_connectivity() {
  log "Checking SSH connectivity to $SSH_USER@$SERVER_IP with key $KEY_PATH"
  # quick test command; don't run remote commands if server unknown
  if ssh -i "$KEY_PATH" $SSH_OPTS -o BatchMode=yes -o ConnectTimeout=5 "$SSH_USER@$SERVER_IP" 'echo OK' >/dev/null 2>&1; then
    log "SSH connectivity OK with key $KEY_PATH"
    return 0
  fi

  log "SSH test failed with key $KEY_PATH. Trying secure temporary copy if possible."
  if [[ -z "$TEMP_KEY" ]]; then
    TEMP_KEY=$(mktemp -p "$RUNS_DIR" key.XXXXXX.pem)
    cp "$KEY_PATH" "$TEMP_KEY" 2>/dev/null || true
    chmod 600 "$TEMP_KEY" 2>/dev/null || true
  fi

  if ssh -i "$TEMP_KEY" $SSH_OPTS -o BatchMode=yes -o ConnectTimeout=5 "$SSH_USER@$SERVER_IP" 'echo OK' >/dev/null 2>&1; then
    log "SSH connectivity OK with temporary key $TEMP_KEY"
    KEY_PATH="$TEMP_KEY"
    return 0
  fi

  log "SSH authentication still failing. Please ensure the key at $KEY_PATH is valid and has permissions 600, or copy it into the control host and re-run."
  echo "SSH authentication failed. Fix key permissions or provide a different key and re-run." >&2
  exit 1
}

check_ssh_connectivity

echo "Using stream tool: $STREAM_TOOL"
echo "Runs directory: $RUNS_DIR"
mkdir -p "$RUNS_DIR"

# orchestrator misc globals
SSH_OPTS="-q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
ABORT=0

# retry helpers
ssh_retry() {
  local cmd="$1"
  local attempts=0
  local max_attempts=4
  local wait=1
  while (( attempts < max_attempts )); do
    if (( ABORT == 1 )); then
      log "ssh_retry: abort requested, exiting"
      return 1
    fi
    if ssh -i "$KEY_PATH" $SSH_OPTS "$SSH_USER@$SERVER_IP" "$cmd"; then
      return 0
    fi
    attempts=$((attempts+1))
    log "ssh attempt $attempts failed, retrying in ${wait}s"
    sleep $wait
    wait=$((wait*2))
  done
  log "ssh_retry: command failed after $max_attempts attempts"
  return 1
}

scp_retry() {
  local src="$1"
  local dest="$2"
  local attempts=0
  local max_attempts=4
  local wait=1
  while (( attempts < max_attempts )); do
    if (( ABORT == 1 )); then
      log "scp_retry: abort requested, exiting"
      return 1
    fi
    if scp -i "$KEY_PATH" $SSH_OPTS -r "$src" "$dest" 2>/dev/null; then
      return 0
    fi
    attempts=$((attempts+1))
    log "scp attempt $attempts failed, retrying in ${wait}s"
    sleep $wait
    wait=$((wait*2))
  done
  log "scp_retry: failed after $max_attempts attempts"
  return 1
}

# Phase 1: Single bitrate per resolution (TEST_MATRIX specification)
declare -A RESOLUTION_BITRATES
RESOLUTION_BITRATES[360p]=800
RESOLUTION_BITRATES[720p]=2500
RESOLUTION_BITRATES[1080p]=4500
RESOLUTION_BITRATES[4k]=15000

# Test matrix defaults
PROTOCOLS=(rtmp rtsp srt)
RESOLUTIONS=(4k 1080p 720p 360p)
VIDEO_CODECS=(h264)  # Phase 1: H.264 only for baseline testing
AUDIO_CODEC=aac
CONNECTIONS=(1 5 10 20 50 100)  # Phase 1: Added 100, removed 2

# Pilot option: override defaults if requested
read -p "Run pilot subset only? (y/N): " RUN_PILOT
if [[ "$RUN_PILOT" =~ ^[Yy] ]]; then
  log "Pilot mode: reducing matrix for quick validation"
  PROTOCOLS=(rtmp srt)
  RESOLUTIONS=(1080p)
  VIDEO_CODECS=(h264 h265 vp9)  # Pilot mode allows codec comparison
  RESOLUTION_BITRATES[1080p]=4500
  CONNECTIONS=(1 5 10 20 50)
  
  # Use shorter duration for pilot
  DURATION_MINUTES=$PILOT_DURATION_MINUTES
  log "Pilot mode: 2-minute tests, 5 connection counts (1,5,10,20,50), 2 protocols (RTMP, SRT)"
  log "Pilot mode: 3 codecs (H.264, H.265, VP9) for codec comparison"
  log "Pilot mode: Total tests = ~30, estimated time = ~60 minutes"
fi


function remote_dir_for() {
  local run_id="$1"
  echo "/var/tmp/wlt_runs/${run_id}"
}

CURRENT_RUN=""
ABORT=0

on_interrupt() {
  log "Received interrupt signal. Setting abort flag and attempting cleanup..."
  ABORT=1
  # Kill any ssh/scp children of this process group to speed stop
  pkill -P $$ 2>/dev/null || true
}

function cleanup_on_exit() {
  # If a run is in progress, try to stop monitors and fetch logs
  if [[ -n "$CURRENT_RUN" ]]; then
    echo "Cleaning up remote monitors for $CURRENT_RUN"
    remote_stop_monitors "$CURRENT_RUN" || true
    fetch_server_logs "$CURRENT_RUN" || true
  fi

  # Remove temporary key if created
  if [[ -n "$TEMP_KEY" && -f "$TEMP_KEY" ]]; then
    rm -f "$TEMP_KEY" || true
    log "Removed temporary key $TEMP_KEY"
  fi
}

trap 'on_interrupt' INT TERM
trap cleanup_on_exit EXIT

function remote_start_monitors() {
  local run_id="$1"
  local remote_dir
  remote_dir=$(remote_dir_for "$run_id")
  
  local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  # Deploy the remote monitoring script
  log "Deploying remote_monitor.sh to server..."
  scp -i "$KEY_PATH" $SSH_OPTS "$script_dir/remote_monitor.sh" "$SSH_USER@$SERVER_IP:/tmp/remote_monitor.sh" || {
    log "WARNING: Failed to deploy remote_monitor.sh"
  }

  # Create dir and try to detect Wowza PID (improved detection)
  # Use ps + grep to find the main Wowza Java process, sorted by memory usage
  local remote_cmd="mkdir -p $remote_dir/monitors && \
    chmod +x /tmp/remote_monitor.sh 2>/dev/null || true; \
    wowza_pid=\$(ps aux | grep -E '[Ww]owza|WowzaStreamingEngine|WowzaMediaServer' | grep java | grep -v grep | sort -k6 -rn | head -n1 | awk '{print \$2}' || echo ''); \
    if [ -z \"\$wowza_pid\" ]; then wowza_pid=\$(pgrep -f 'java.*com.wowza' -i | head -n1 || echo ''); fi; \
    echo \"Detected Wowza PID: \$wowza_pid\" > $remote_dir/monitors/wowza_detection.log; \
    if [ -n \"\$wowza_pid\" ]; then echo \"\$wowza_pid\" > $remote_dir/monitors/wowza.pid; fi; \
    nohup /tmp/remote_monitor.sh $remote_dir/monitors > $remote_dir/monitors/remote_monitor_stdout.log 2>&1 & echo \$! > $remote_dir/monitors/remote_monitor.pid; \
    if [ -n \"\$wowza_pid\" ]; then nohup pidstat -h -u -r 5 -p \"\$wowza_pid\" > $remote_dir/pidstat.log 2>&1 & echo \$! > $remote_dir/monitors/pidstat.pid; else nohup pidstat -h -u -r 5 > $remote_dir/pidstat.log 2>&1 & echo \$! > $remote_dir/monitors/pidstat.pid; fi; \
    nohup sar -u 5 > $remote_dir/sar_cpu.log 2>&1 & echo \$! > $remote_dir/monitors/sar.pid || true; \
    nohup sar -n DEV 5 > $remote_dir/sar_net.log 2>&1 & echo \$! > $remote_dir/monitors/sar_net.pid || true; \
    if command -v ifstat >/dev/null 2>&1; then nohup ifstat -t 5 > $remote_dir/ifstat.log 2>&1 & echo \$! > $remote_dir/monitors/ifstat.pid; fi; \
    if [ -n \"\$wowza_pid\" ] && command -v jstat >/dev/null 2>&1; then nohup jstat -gc -t \"\$wowza_pid\" 5000 > $remote_dir/jstat_gc.log 2>&1 & echo \$! > $remote_dir/monitors/jstat.pid; fi"
  ssh_retry "$remote_cmd" || log "remote_start_monitors: failed to start monitors for $run_id"
  
  log "Remote monitoring started (PID file: $remote_dir/monitors/remote_monitor.pid)"
}

function remote_stop_monitors() {
  local run_id="$1"
  local remote_dir
  remote_dir=$(remote_dir_for "$run_id")

  local remote_cmd="if [ -f $remote_dir/monitors/remote_monitor.pid ]; then kill \$(cat $remote_dir/monitors/remote_monitor.pid) 2>/dev/null || true; fi; \
    if [ -f $remote_dir/monitors/pidstat.pid ]; then kill \$(cat $remote_dir/monitors/pidstat.pid) 2>/dev/null || true; fi; \
    if [ -f $remote_dir/monitors/sar.pid ]; then kill \$(cat $remote_dir/monitors/sar.pid) 2>/dev/null || true; fi; \
    if [ -f $remote_dir/monitors/sar_net.pid ]; then kill \$(cat $remote_dir/monitors/sar_net.pid) 2>/dev/null || true; fi; \
    if [ -f $remote_dir/monitors/ifstat.pid ]; then kill \$(cat $remote_dir/monitors/ifstat.pid) 2>/dev/null || true; fi; \
    if [ -f $remote_dir/monitors/jstat.pid ]; then kill \$(cat $remote_dir/monitors/jstat.pid) 2>/dev/null || true; fi; \
    sleep 1; ps aux 2>/dev/null | head -n 200 > $remote_dir/process_snapshot.txt || true; \
    if [ -f $remote_dir/monitors/wowza.pid ]; then pid=\$(cat $remote_dir/monitors/wowza.pid | tr -d '[:space:]'); if [ -n \"\$pid\" ] && ps -p \$pid >/dev/null 2>&1; then ps -p \$pid -o pid,rss,vsz,pmem,pcpu,cmd --no-headers > $remote_dir/wowza_proc.txt 2>/dev/null || true; fi; fi"
  ssh_retry "$remote_cmd" || log "remote_stop_monitors: failed to stop monitors for $run_id"
}

function fetch_server_logs() {
  local run_id="$1"
  local remote_dir
  remote_dir=$(remote_dir_for "$run_id")
  mkdir -p "$RUNS_DIR/$run_id/server_logs"
  # Try a few times to fetch logs
  # Try to copy with retries
  scp_retry "$SSH_USER@$SERVER_IP:$remote_dir/*" "$RUNS_DIR/$run_id/server_logs/" || log "fetch_server_logs: scp failed for $run_id"
}

function get_server_cpu() {
  # Try to compute short-term CPU usage on remote host. Requires python3 on server; fallback to top if python3 missing.
  local cpu
  local cpu_raw
  
  # Capture stdout only (stderr has SSH warnings that we don't want)
  cpu_raw=$(timeout 15 ssh -i "$KEY_PATH" $SSH_OPTS "$SSH_USER@$SERVER_IP" "python3 - <<'PY'
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
    import sys
    print('0.00')
PY" 2>/dev/null || echo "0.00")
  
  # Extract only the numeric value (filter out any warnings or extra text)
  cpu=$(echo "$cpu_raw" | grep -oE '[0-9]+\.[0-9]+' | head -n1)

  # Fallback if empty or invalid
  if [[ -z "$cpu" ]] || ! [[ "$cpu" =~ ^[0-9]+\.[0-9]+$ ]]; then
    cpu=0.00
  fi
  
  echo "$cpu"
}

function get_server_heap() {
  # Get Java heap usage percentage for Wowza process
  # Cascading fallback: jcmd (primary) -> jstat (fallback 1) -> jmap (fallback 2 - emergency only)
  local heap_raw
  local wowza_pid
  local java_bin="/usr/local/WowzaStreamingEngine/java/bin"
  
  # First, get Wowza Engine PID (not Manager)
  # Look for com.wowza.wms.bootstrap.Bootstrap which is the actual streaming engine
  wowza_pid=$(timeout 10 ssh -i "$KEY_PATH" $SSH_OPTS "$SSH_USER@$SERVER_IP" \
    "ps aux | grep 'com.wowza.wms.bootstrap.Bootstrap start' | grep -v grep | awk '{print \$2}' | head -n1 || echo ''" 2>/dev/null || echo "")
  
  if [[ -z "$wowza_pid" ]]; then
    log "WARNING: Could not detect Wowza Engine PID for heap monitoring"
    echo "0.00"
    return
  fi
  
  # Method 1: Try jcmd (primary - fast, human-readable)
  # Try both PATH and Wowza's java/bin directory
  # Supports all GC types: Parallel, G1, ZGC, Shenandoah, Serial
  # Try without sudo first, then with sudo if permission denied
  
  # Get jcmd output from remote server (without AWK processing)
  local jcmd_output
  jcmd_output=$(timeout 10 ssh -i "$KEY_PATH" $SSH_OPTS "$SSH_USER@$SERVER_IP" \
    "{ command -v jcmd >/dev/null 2>&1 && jcmd $wowza_pid GC.heap_info 2>&1; } || \
     { [ -x $java_bin/jcmd ] && $java_bin/jcmd $wowza_pid GC.heap_info 2>&1; } || \
     { command -v jcmd >/dev/null 2>&1 && sudo jcmd $wowza_pid GC.heap_info 2>&1; } || \
     { [ -x $java_bin/jcmd ] && sudo $java_bin/jcmd $wowza_pid GC.heap_info 2>&1; }" 2>/dev/null || echo "")
  
  # Process jcmd output locally with AWK
  # FIXED: Only use top-level heap summary to avoid double-counting
  if [[ -n "$jcmd_output" ]]; then
    heap_raw=$(echo "$jcmd_output" | awk '
      BEGIN { total_kb=0; used_kb=0; found_summary=0 }
      
      # G1GC/ZGC/Shenandoah: Look for top-level summary line FIRST
      # These provide a single authoritative heap total. Prefer max capacity when available.
      /^garbage-first heap[ \t]+total|^ZHeap[ \t]+used|^Z Heap[ \t]+used|^Shenandoah[ \t]+total/ {
        found_summary=1
        # ZGC format: "ZHeap used 194M, capacity 496M, max capacity 5416M"
        if ($0 ~ /used [0-9]+M/ && $0 ~ /capacity [0-9]+M/) {
          for(i=1; i<=NF; i++) {
            if ($i == "used" && $(i+1) ~ /^[0-9]+M/) {
              gsub(/[^0-9]/, "", $(i+1))
              used_kb = $(i+1) * 1024
            }
            # capture regular capacity (committed)
            if ($i == "capacity" && $(i+1) ~ /^[0-9]+M/ && $(i-1) !~ /max/) {
              gsub(/[^0-9]/, "", $(i+1))
              total_kb = $(i+1) * 1024
            }
            # capture max capacity when present: pattern "max capacity <N>M"
            if ($i == "max" && $(i+1) == "capacity" && $(i+2) ~ /^[0-9]+M/) {
              gsub(/[^0-9]/, "", $(i+2))
              max_kb = $(i+2) * 1024
            }
          }
        }
        # G1GC/Shenandoah format: "garbage-first heap total 524288K, used 194288K"
        else if ($0 ~ /total [0-9]+K/ && $0 ~ /used [0-9]+K/) {
          for(i=1; i<=NF; i++) {
            if ($i == "total" && $(i+1) ~ /^[0-9]+K,?$/) {
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
      
      # Parallel GC: Only process if we haven NOT found a summary line
      # Sum up PSYoungGen + ParOldGen (separate regions)
      !found_summary && /^[ \t]*(PSYoungGen|ParOldGen|PSOldGen)[ \t]+total/ {
        if ($0 ~ /total [0-9]+K/) {
          for(i=1; i<=NF; i++) {
            if ($i == "total" && $(i+1) ~ /^[0-9]+K,?$/) {
              gsub(/[^0-9]/, "", $(i+1))
              total_kb += $(i+1)
            }
            if ($i == "used" && $(i+1) ~ /^[0-9]+K,?$/) {
              gsub(/[^0-9]/, "", $(i+1))
              used_kb += $(i+1)
            }
          }
        }
      }
      
      END {
        # Prefer max_kb (if present) as the denominator per new policy, otherwise fall back to total_kb
        denom = (max_kb > 0 ? max_kb : total_kb)
        if(denom > 0) printf "%.2f", (used_kb / denom) * 100
        else print "0.00"
      }
    ')
  else
    heap_raw="0.00"
  fi
  
  # Fallback 1: Try jstat if jcmd failed
  if [[ -z "$heap_raw" ]] || [[ "$heap_raw" == "0.00" ]]; then
    heap_raw=$(timeout 10 ssh -i "$KEY_PATH" $SSH_OPTS "$SSH_USER@$SERVER_IP" \
      "{ command -v jstat >/dev/null 2>&1 && jstat -gc $wowza_pid 2>&1; } || \
       { [ -x $java_bin/jstat ] && $java_bin/jstat -gc $wowza_pid 2>&1; } || \
       { command -v jstat >/dev/null 2>&1 && sudo jstat -gc $wowza_pid 2>&1; } || \
       { [ -x $java_bin/jstat ] && sudo $java_bin/jstat -gc $wowza_pid 2>&1; } | tail -n1 | awk '
        {
          used=\$3+\$4+\$6+\$8;
          capacity=\$1+\$2+\$5+\$7;
          if(capacity>0) printf \"%.2f\", (used/capacity)*100;
          else print \"0.00\"
        }
      '" 2>/dev/null || echo "0.00")
  fi
  
  # Fallback 2: Try jmap if both jcmd and jstat failed
  # WARNING: jmap -heap causes JVM pause - only use as emergency fallback
  # This should rarely be needed and may impact test accuracy
  if [[ -z "$heap_raw" ]] || [[ "$heap_raw" == "0.00" ]]; then
    log "WARNING: Both jcmd and jstat failed. Using jmap as last resort (may cause JVM pause)..."
    heap_raw=$(timeout 10 ssh -i "$KEY_PATH" $SSH_OPTS "$SSH_USER@$SERVER_IP" \
      "{ command -v jmap >/dev/null 2>&1 && jmap -heap $wowza_pid 2>&1; } || \
       { [ -x $java_bin/jmap ] && $java_bin/jmap -heap $wowza_pid 2>&1; } || \
       { command -v jmap >/dev/null 2>&1 && sudo jmap -heap $wowza_pid 2>&1; } || \
       { [ -x $java_bin/jmap ] && sudo $java_bin/jmap -heap $wowza_pid 2>&1; } | awk '
        /used =/ { gsub(/[^0-9]/, \"\", \$3); used=\$3 }
        /capacity =/ { gsub(/[^0-9]/, \"\", \$3); capacity=\$3 }
        END { if(capacity>0) printf \"%.2f\", (used/capacity)*100; else print \"0.00\" }
      '" 2>/dev/null || echo "0.00")
    
    if [[ "$heap_raw" != "0.00" ]]; then
      log "WARNING: jmap succeeded but may have impacted server performance during this query"
    fi
  fi
  
  # Validate result
  if [[ -z "$heap_raw" ]] || ! [[ "$heap_raw" =~ ^[0-9]+\.[0-9]+$ ]]; then
    heap_raw="0.00"
  fi
  
  echo "$heap_raw"
}

function get_server_memory() {
  # Get overall system memory usage percentage
  local mem_raw
  
  mem_raw=$(timeout 10 ssh -i "$KEY_PATH" $SSH_OPTS "$SSH_USER@$SERVER_IP" \
    "free | grep Mem | awk '{printf \"%.2f\", (\$3/\$2)*100}'" 2>/dev/null || echo "0.00")
  
  # Validate result
  if [[ -z "$mem_raw" ]] || ! [[ "$mem_raw" =~ ^[0-9]+\.[0-9]+$ ]]; then
    mem_raw="0.00"
  fi
  
  echo "$mem_raw"
}

function get_server_network() {
  # Get current network throughput in Mbps
  # Uses ifstat if available, otherwise sar
  local net_raw
  local ifstat_available
  
  # Check if ifstat is available
  ifstat_available=$(timeout 5 ssh -i "$KEY_PATH" $SSH_OPTS "$SSH_USER@$SERVER_IP" \
    "command -v ifstat >/dev/null 2>&1 && echo 'yes' || echo 'no'" 2>/dev/null || echo "no")
  
  if [[ "$ifstat_available" == "yes" ]]; then
    # Use ifstat (simpler output)
    net_raw=$(timeout 10 ssh -i "$KEY_PATH" $SSH_OPTS "$SSH_USER@$SERVER_IP" \
      "ifstat -i eth0 1 1 2>/dev/null | tail -n1 | awk '{print \$2}'" 2>/dev/null || echo "0.00")
  else
    # Fallback to sar
    net_raw=$(timeout 10 ssh -i "$KEY_PATH" $SSH_OPTS "$SSH_USER@$SERVER_IP" \
      "sar -n DEV 1 1 2>/dev/null | grep -E 'eth0|ens' | grep -v Average | tail -n1 | awk '{print \$6}'" 2>/dev/null || echo "0.00")
  fi
  
  # Convert KB/s to Mbps if needed (sar returns KB/s, ifstat returns KB/s)
  # Multiply by 8 / 1024 = 0.0078125
  if [[ -n "$net_raw" ]] && [[ "$net_raw" != "0.00" ]]; then
    net_raw=$(echo "$net_raw" | awk '{printf "%.2f", $1 * 0.0078125}')
  fi
  
  # Validate result
  if [[ -z "$net_raw" ]] || ! [[ "$net_raw" =~ ^[0-9]+\.[0-9]+$ ]]; then
    net_raw="0.00"
  fi
  
  echo "$net_raw"
}

function check_server_status() {
  # Unified status check - returns CPU|HEAP|MEM|NET as pipe-delimited string
  # This is more efficient than calling each function separately
  local cpu heap mem net
  
  cpu=$(get_server_cpu)
  heap=$(get_server_heap)
  mem=$(get_server_memory)
  net=$(get_server_network)
  
  echo "$cpu|$heap|$mem|$net"
}

function run_single_experiment() {
  local protocol="$1"
  local resolution="$2"
  local vcodec="$3"
  local bitrate="$4"
  local connections="$5"

  local timestamp
  timestamp=$(date +%Y%m%d_%H%M%S)
  local run_id="${timestamp}_${protocol^^}_${resolution}_${vcodec^^}_${bitrate}k_${connections}conn"
  local local_run_dir="$RUNS_DIR/$run_id"
  mkdir -p "$local_run_dir/client_logs" "$local_run_dir/server_logs"

  echo "=== Running: $run_id ==="

  # Start remote monitors
  CURRENT_RUN="$run_id"
  remote_start_monitors "$run_id"

  # Build server URL based on protocol
  local server_url
  case "$protocol" in
    rtmp)
      server_url="rtmp://$SERVER_IP:$RTMP_PORT/$RTMP_APP_NAME"
      ;;
    rtsp)
      server_url="rtsp://$SERVER_IP:$RTSP_PORT/$RTSP_APP_NAME"
      ;;
    srt)
      server_url="srt://$SERVER_IP:$SRT_PORT?streamid=$SRT_APP_NAME"
      ;;
  esac

  # Run the load tester (non-interactive)
  echo "Starting client load tester: protocol=$protocol resolution=$resolution video=$vcodec audio=$AUDIO_CODEC bitrate=${bitrate}k connections=$connections duration=${DURATION_MINUTES}m"
  "$STREAM_TOOL" \
    --yes \
    --protocol "$protocol" \
    --resolution "$resolution" \
    --video-codec "$vcodec" \
    --audio-codec "$AUDIO_CODEC" \
    --bitrate "$bitrate" \
    --url "$server_url" \
    --connections "$connections" \
    --stream-name "$STREAM_BASE" \
    --duration "$DURATION_MINUTES" \
      2>&1 | tee "$local_run_dir/client_logs/stream_load_tester.log" || true

  # After client exits, give server a short moment then stop monitors
  sleep 5
  log "Stopping remote monitors for $run_id..."
  remote_stop_monitors "$run_id"
  log "Fetching server logs for $run_id..."
  fetch_server_logs "$run_id"

  # Parse results (local parser)
  log "Parsing results for $run_id..."
  if command -v python3 >/dev/null 2>&1; then
    # Fetch remote wowza PID if present and pass to parser
    WOWZA_PID=""
    WOWZA_PID=$(timeout 10 ssh -i "$KEY_PATH" $SSH_OPTS "$SSH_USER@$SERVER_IP" "if [ -f $(remote_dir_for $run_id)/monitors/wowza.pid ]; then cat $(remote_dir_for $run_id)/monitors/wowza.pid; fi" 2>/dev/null || true)
    log "Wowza PID: ${WOWZA_PID:-not found}"
    
    if [[ -n "$WOWZA_PID" ]]; then
      log "Running parser with Wowza PID..."
      if ! python3 "$SCRIPT_DIR/parse_run.py" --run-dir "$local_run_dir" --run-id "$run_id" --protocol "$protocol" --resolution "$resolution" --video-codec "$vcodec" --audio-codec "$AUDIO_CODEC" --connections "$connections" --wowza-pid "$WOWZA_PID"; then
        log "WARNING: Parser failed for $run_id"
      fi
    else
      log "Running parser without Wowza PID..."
      if ! python3 "$SCRIPT_DIR/parse_run.py" --run-dir "$local_run_dir" --run-id "$run_id" --protocol "$protocol" --resolution "$resolution" --video-codec "$vcodec" --audio-codec "$AUDIO_CODEC" --connections "$connections"; then
        log "WARNING: Parser failed for $run_id"
      fi
    fi
    log "Parser completed for $run_id"
  else
    log "ERROR: python3 not available - this should have been caught during startup dependency check"
    echo "WARNING: python3 not available; skipping result parsing for $run_id" >&2
    echo "Raw logs available in: $local_run_dir" >&2
    echo "To parse manually later: python3 $SCRIPT_DIR/parse_run.py --run-dir $local_run_dir --run-id $run_id ..." >&2
  fi

  log "=== Completed: $run_id ==="
  echo "=== Completed: $run_id ==="

  CURRENT_RUN=""
}

echo "Starting test sweep. Press Ctrl+C to abort. The orchestrator will stop when server CPU >= 80%."

for protocol in "${PROTOCOLS[@]}"; do
  for resolution in "${RESOLUTIONS[@]}"; do
    # Get single bitrate for this resolution (Phase 1: one bitrate per resolution)
    bitrate=${RESOLUTION_BITRATES[$resolution]}
    for vcodec in "${VIDEO_CODECS[@]}"; do
      # Skip VP9 for non-SRT protocols (VP9 only works reliably with SRT/MPEGTS)
      if [[ "$vcodec" == "vp9" && "$protocol" != "srt" ]]; then
        log "Skipping VP9 for $protocol (VP9 only supported with SRT protocol)"
        continue
      fi
      
      for conn in "${CONNECTIONS[@]}"; do
        if (( ABORT == 1 )); then
          log "Abort requested, breaking out of connections loop"
          break
        fi
        # Break quickly if abort requested
        if (( ABORT == 1 )); then
          log "Abort requested, stopping sweep"
          exit 1
        fi

        # Check server health: CPU, Heap, Memory, Network
        log "Checking server health..."
        status=$(check_server_status)
        IFS='|' read -r cpu heap mem net <<< "$status"
        
        # Validate CPU value
        if [[ -z "$cpu" ]]; then
          log "WARNING: Unable to get server CPU, continuing anyway..."
          cpu="0.00"
        fi
        
        # Log all metrics
        log "Server Status: CPU=${cpu}% | Heap=${heap}% | Mem=${mem}% | Net=${net}Mbps"
        
        # Check CPU threshold
        cpu_int=${cpu%.*}
        if (( cpu_int >= 80 )); then
          log "Server CPU >= 80% (current: ${cpu}%). Halting further tests."
          echo "Server CPU >= 80% (current: ${cpu}%). Halting further tests."
          exit 0
        fi
        
        # Check Heap threshold (if available)
        if [[ -n "$heap" ]] && [[ "$heap" != "0.00" ]] && [[ "$heap" != "N/A" ]]; then
          heap_int=${heap%.*}
          if (( heap_int >= 80 )); then
            log "Server Heap >= 80% (current: ${heap}%). Halting further tests."
            echo "Server Heap >= 80% (current: ${heap}%). Halting further tests."
            exit 0
          fi
        fi

        run_single_experiment "$protocol" "$resolution" "$vcodec" "$bitrate" "$conn"

        # Phase 1: 30-second cooldown between experiments
        log "Cooldown: waiting 30 seconds for server to stabilize..."
        sleep 30
      done
    done
  done
done

echo "All experiments finished or stopped by CPU/Heap threshold. Results are in $RUNS_DIR"
