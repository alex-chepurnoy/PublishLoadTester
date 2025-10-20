# Phase 4 Remaining Tasks

**Date**: 2025-10-18  
**Status**: 🟡 In Progress  

## Overview

Phase 4 core monitoring is complete, but the adaptive stopping logic needs refinement for proper full matrix testing behavior. Currently, when a threshold is reached, the entire test sweep exits. For full matrix testing, we need to skip remaining connection counts and continue to the next protocol.

## Current Behavior vs. Required Behavior

### Current Behavior (Lines 923-936)
```bash
# Check CPU threshold
cpu_int=${cpu%.*}
if (( cpu_int >= 80 )); then
  log "Server CPU >= 80% (current: ${cpu}%). Halting further tests."
  echo "Server CPU >= 80% (current: ${cpu}%). Halting further tests."
  exit 0  # ← EXITS ENTIRE SWEEP
fi

# Check Heap threshold
if [[ -n "$heap" ]] && [[ "$heap" != "0.00" ]] && [[ "$heap" != "N/A" ]]; then
  heap_int=${heap%.*}
  if (( heap_int >= 80 )); then
    log "Server Heap >= 80% (current: ${heap}%). Halting further tests."
    echo "Server Heap >= 80% (current: ${heap}%). Halting further tests."
    exit 0  # ← EXITS ENTIRE SWEEP
  fi
fi
```

**Problem**: `exit 0` terminates the entire orchestrator, stopping all remaining tests.

### Required Behavior for Full Matrix

When testing **RTMP 1080p** with connection counts [1, 5, 10, 20, 50, 100]:
- If 20 connections causes CPU/Heap ≥ 80%
- Log: "Maximum capacity: 10 connections for RTMP 1080p"
- Skip: 50 and 100 connection tests
- Continue: Move to **RTSP 1080p** starting at 1 connection

**Loop Structure**:
```
Resolution: 1080p
  Protocol: RTMP
    Connections: 1 ✅ (CPU: 20%, Heap: 15%)
    Connections: 5 ✅ (CPU: 45%, Heap: 35%)
    Connections: 10 ✅ (CPU: 70%, Heap: 60%)
    Connections: 20 ❌ (CPU: 85%, Heap: 75%) ← THRESHOLD REACHED
    → Log max capacity: 10 connections
    → Skip: 50, 100
  Protocol: RTSP (continue)
    Connections: 1 ✅ (CPU: 22%, Heap: 18%)
    ...
```

## Task Breakdown

### Task 4.2.1: Fix Skip Logic for Connection Counts

**File**: `orchestrator/run_orchestration.sh`  
**Lines**: 920-936 (threshold checking section)

**Changes Required**:

1. **Add State Variable** (before main loop, ~line 880):
```bash
# Track last successful connection count
last_successful_conn=0
declare -A MAX_CAPACITY
```

2. **Track Successful Tests** (after test completes, ~line 948):
```bash
# After run_single_experiment succeeds
experiment_status=$?

if (( experiment_status == 0 )); then
  last_successful_conn=$conn
else
  # Test failed - don't update last successful
  :
fi
```

3. **Replace Exit Logic with Break** (lines 923-936):
```bash
# Check CPU threshold
cpu_int=${cpu%.*}
if (( cpu_int >= 80 )); then
  log "Server CPU >= 80% (current: ${cpu}%). Maximum capacity for ${protocol} ${resolution}: ${last_successful_conn} connections"
  echo "Maximum capacity reached: ${last_successful_conn} connections for ${protocol} ${resolution}"
  MAX_CAPACITY["${protocol}_${resolution}"]="${last_successful_conn}|${cpu}|${heap}"
  log "Skipping remaining connections [${conn}, ...] for ${protocol} ${resolution}"
  break  # Exit connection loop only, continue to next protocol
fi

# Check Heap threshold
if [[ -n "$heap" ]] && [[ "$heap" != "0.00" ]] && [[ "$heap" != "N/A" ]]; then
  heap_int=${heap%.*}
  if (( heap_int >= 80 )); then
    log "Server Heap >= 80% (current: ${heap}%). Maximum capacity for ${protocol} ${resolution}: ${last_successful_conn} connections"
    echo "Maximum capacity reached: ${last_successful_conn} connections for ${protocol} ${resolution}"
    MAX_CAPACITY["${protocol}_${resolution}"]="${last_successful_conn}|${cpu}|${heap}"
    log "Skipping remaining connections [${conn}, ...] for ${protocol} ${resolution}"
    break  # Exit connection loop only, continue to next protocol
  fi
fi
```

4. **Add Cooldown After Skip** (after connection loop, ~line 950):
```bash
      done  # End connections loop
      
      # If we broke out due to threshold, add extra cooldown
      if [[ -n "${MAX_CAPACITY[${protocol}_${resolution}]}" ]]; then
        log "Extra cooldown after threshold: waiting 60 seconds for server to recover..."
        sleep 60
      fi
    done  # End protocol loop
```

**Testing**:
```bash
# Test with artificially low threshold (e.g., 40%) to trigger skip
# Verify:
# 1. Remaining connections are skipped
# 2. Next protocol starts
# 3. Max capacity is logged
```

---

### Task 4.2.2: Add Protocol and Codec Selector

**File**: `orchestrator/run_orchestration.sh`  
**Lines**: After pilot mode prompt (~line 268)

**Changes Required**:

1. **Add Protocol Selector** (after pilot mode, before test sweep):
```bash
# Protocol Selection
echo ""
echo "=========================================="
echo "Protocol Selection"
echo "=========================================="
echo "  1) RTMP only"
echo "  2) RTSP only"
echo "  3) SRT only"
echo "  4) RTMP + SRT"
echo "  5) RTMP + RTSP"
echo "  6) ALL protocols (RTMP, RTSP, SRT)"
echo ""
read -p "Select protocols to test [6]: " PROTO_CHOICE
PROTO_CHOICE="${PROTO_CHOICE:-6}"

case "$PROTO_CHOICE" in
  1) PROTOCOLS=(rtmp) ;;
  2) PROTOCOLS=(rtsp) ;;
  3) PROTOCOLS=(srt) ;;
  4) PROTOCOLS=(rtmp srt) ;;
  5) PROTOCOLS=(rtmp rtsp) ;;
  6) PROTOCOLS=(rtmp rtsp srt) ;;
  *) 
    echo "Invalid selection, using all protocols"
    PROTOCOLS=(rtmp rtsp srt)
    ;;
esac

log "Selected protocols: ${PROTOCOLS[*]}"
echo "Testing protocols: ${PROTOCOLS[*]}"
```

2. **Add Codec Selector** (for future multi-codec support):
```bash
# Video Codec Selection (future-proofing for Phase 5+)
echo ""
echo "=========================================="
echo "Video Codec Selection"
echo "=========================================="
echo "  1) H.264 only (current phase)"
echo "  2) H.265 only (future)"
echo "  3) VP9 only (future)"
echo "  4) ALL codecs (future)"
echo ""
read -p "Select video codec [1]: " CODEC_CHOICE
CODEC_CHOICE="${CODEC_CHOICE:-1}"

case "$CODEC_CHOICE" in
  1) VIDEO_CODECS=(h264) ;;
  2) VIDEO_CODECS=(h265) ;;
  3) VIDEO_CODECS=(vp9) ;;
  4) VIDEO_CODECS=(h264 h265 vp9) ;;
  *) 
    echo "Invalid selection, using H.264"
    VIDEO_CODECS=(h264)
    ;;
esac

log "Selected video codec(s): ${VIDEO_CODECS[*]}"
echo "Testing codec(s): ${VIDEO_CODECS[*]}"
```

3. **Add Connection Range Selector** (optional, advanced):
```bash
# Connection Range Selection (optional)
echo ""
echo "=========================================="
echo "Connection Range Selection"
echo "=========================================="
echo "  1) Full range (1, 5, 10, 20, 50, 100)"
echo "  2) Quick test (1, 10, 50)"
echo "  3) Custom range"
echo ""
read -p "Select connection range [1]: " CONN_CHOICE
CONN_CHOICE="${CONN_CHOICE:-1}"

case "$CONN_CHOICE" in
  1) CONNECTIONS=(1 5 10 20 50 100) ;;
  2) CONNECTIONS=(1 10 50) ;;
  3) 
    echo "Enter connection counts (space-separated, e.g., '1 5 20'):"
    read -p "> " custom_conn
    CONNECTIONS=($custom_conn)
    ;;
  *) 
    echo "Invalid selection, using full range"
    CONNECTIONS=(1 5 10 20 50 100)
    ;;
esac

log "Selected connection counts: ${CONNECTIONS[*]}"
echo "Testing connections: ${CONNECTIONS[*]}"
```

**Benefits**:
- Targeted testing (e.g., test only SRT for debugging)
- Faster iterations during development
- Protocol comparison (run RTMP vs SRT back-to-back)
- Flexible test matrix customization

**Testing**:
```bash
# Test each selection option
./run_orchestration.sh
# Select option 3 (SRT only)
# Verify only SRT tests run
```

---

### Task 4.2.3: Add Maximum Capacity Summary Report

**File**: `orchestrator/run_orchestration.sh`  
**Lines**: After main loop completes (~line 960)

**Changes Required**:

1. **Print Summary Report**:
```bash
echo ""
echo "=========================================="
echo "Maximum Capacity Summary"
echo "=========================================="

if [[ ${#MAX_CAPACITY[@]} -gt 0 ]]; then
  echo ""
  echo "Protocol | Resolution | Max Connections | CPU % | Heap %"
  echo "---------|------------|----------------|-------|-------"
  
  for key in "${!MAX_CAPACITY[@]}"; do
    IFS='_' read -r protocol resolution <<< "$key"
    IFS='|' read -r max_conn cpu heap <<< "${MAX_CAPACITY[$key]}"
    printf "%-8s | %-10s | %15s | %5s | %6s\n" \
      "${protocol^^}" "$resolution" "$max_conn" "$cpu" "$heap"
  done
  
  echo ""
  echo "Note: Tests that completed all connection counts without reaching"
  echo "      threshold are not listed (no maximum capacity found)."
else
  echo ""
  echo "No capacity limits reached during testing."
  echo "All tests completed successfully at all connection counts."
fi

echo ""
echo "=========================================="
```

2. **Save Summary to File**:
```bash
# Save summary to file
SUMMARY_FILE="$RUNS_DIR/capacity_summary_$(date +%Y%m%d_%H%M%S).txt"

{
  echo "Maximum Capacity Summary"
  echo "Test Run: $(date)"
  echo ""
  echo "Protocol | Resolution | Max Connections | CPU % | Heap %"
  echo "---------|------------|----------------|-------|-------"
  
  for key in "${!MAX_CAPACITY[@]}"; do
    IFS='_' read -r protocol resolution <<< "$key"
    IFS='|' read -r max_conn cpu heap <<< "${MAX_CAPACITY[$key]}"
    printf "%-8s | %-10s | %15s | %5s | %6s\n" \
      "${protocol^^}" "$resolution" "$max_conn" "$cpu" "$heap"
  done
} > "$SUMMARY_FILE"

log "Capacity summary saved to: $SUMMARY_FILE"
echo "Capacity summary saved to: $SUMMARY_FILE"
```

**Example Output**:
```
==========================================
Maximum Capacity Summary
==========================================

Protocol | Resolution | Max Connections | CPU % | Heap %
---------|------------|----------------|-------|-------
RTMP     | 1080p      |              10 | 82.45 | 76.23
SRT      | 1080p      |              20 | 79.12 | 81.56
RTMP     | 4k         |               5 | 85.34 | 78.90

Note: Tests that completed all connection counts without reaching
      threshold are not listed (no maximum capacity found).
==========================================
```

---

## Implementation Priority

1. **HIGH**: Task 4.2.1 - Fix skip logic (critical for full matrix testing)
2. **MEDIUM**: Task 4.2.2 - Protocol selector (improves usability)
3. **LOW**: Task 4.2.3 - Capacity summary (nice to have, Phase 5 material)

## Testing Strategy

### Test 4.2.1: Skip Logic
```bash
# Modify threshold to 40% for testing
# Run pilot mode with 2 resolutions, 2 protocols
# Verify:
# - First protocol hits 40% at connection 10
# - Connections 20+ are skipped
# - Second protocol starts at connection 1
# - Logs show "Maximum capacity: X connections"
```

### Test 4.2.2: Protocol Selector
```bash
# Run orchestrator
# Select option 3 (SRT only)
# Verify:
# - Only SRT tests execute
# - RTMP and RTSP are skipped
# - Logs show "Selected protocols: srt"
```

### Test 4.2.3: Capacity Summary
```bash
# Run full test with artificial threshold
# At end, verify:
# - Summary table printed
# - Summary file created in runs/
# - All protocols that hit threshold are listed
```

## Success Criteria

- ✅ Threshold detection maintains test progression (doesn't exit)
- ✅ Remaining connections skipped when threshold reached
- ✅ Next protocol starts fresh at connection 1
- ✅ Maximum capacity tracked per protocol/resolution
- ✅ Protocol selector allows targeted testing
- ✅ Logs clearly show skip reasoning
- ✅ Summary report generated at end

## Estimated Time

- Task 4.2.1: 30-45 minutes
- Task 4.2.2: 20-30 minutes  
- Task 4.2.3: 15-20 minutes
- Testing: 30-45 minutes

**Total**: ~2 hours

## Next Phase

Once Phase 4 is complete, move to **Phase 5: Enhanced Logging & Reporting** for comprehensive result analysis and capacity reporting.
