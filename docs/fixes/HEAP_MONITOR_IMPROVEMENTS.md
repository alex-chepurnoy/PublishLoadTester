# Heap Safety Monitor Improvements

**Date**: 2025-10-17  
**Status**: Complete  

## Overview

Enhanced the heap safety monitoring system with flexible thresholds, real-time status reporting, and improved CSV output with heap statistics.

## Changes Implemented

### 1. Flexible Heap Threshold System

**Previous Behavior**:
- Immediately killed test when heap reached 80%
- No grace period for temporary spikes

**New Behavior**:
- Prints **WARNING** when heap reaches 80%
- Monitors sustained high heap usage
- Only kills test if heap stays >= 80% for **30 consecutive seconds**
- Resets timer if heap drops below threshold
- Provides countdown messaging during sustained high usage

**Benefits**:
- Prevents false positives from temporary heap spikes
- Allows GC to reclaim memory before killing tests
- More resilient to normal heap fluctuations

### 2. Real-Time Status Information

**Added INFO Messages Every 10 Seconds**:
```
INFO: Server CPU: 45.23%
INFO: Server Heap: 67.89%
```

**Progressive Warning Messages**:
```
WARNING: Heap at 82.34% (>= 80%) - monitoring for sustained high usage...
WARNING: Heap sustained at 83.12% for 10s (threshold: 30s)
WARNING: Heap sustained at 84.56% for 20s (threshold: 30s)
CRITICAL: Heap sustained >= 80% for 30s - KILLING TEST TO PREVENT SERVER CRASH
```

**Benefits**:
- Provides visibility into server state during test execution
- Helps diagnose performance issues in real-time
- Clear warning progression before test termination

### 3. Optimized Heap Detection

**Previous**: Called `get_server_heap()` which re-detected Wowza PID every check

**New**: Uses cached `WOWZA_PID` variable directly in background monitor

**Benefits**:
- Reduces SSH overhead (no repeated `pgrep` calls)
- Faster response time (inline heap check vs. function call)
- More efficient monitoring during test execution

### 4. Suppressed Debug Output

**Commented Out**:
```bash
# log "DEBUG: Detected Wowza PID: $wowza_pid"
# log "DEBUG: jcmd output length: ${#jcmd_output}"
# log "DEBUG: jcmd first 3 lines: ..."
# log "DEBUG: heap_raw after jcmd: $heap_raw"
```

**Benefits**:
- Cleaner log output
- Easier to spot important warnings and errors
- Debug messages can be re-enabled by uncommenting

### 5. Enhanced CSV Output with Heap Statistics

**Previous CSV Columns**:
```
run_id, timestamp, protocol, resolution, video_codec, audio_codec, connections,
avg_sys_cpu_percent, max_sys_cpu_percent, cpu_per_stream_percent, 
mem_rss_kb, heap_used_mb, heap_capacity_mb
```

**New CSV Columns**:
```
run_id, timestamp, protocol, resolution, video_codec, audio_codec, connections,
avg_sys_cpu_percent, max_sys_cpu_percent, mem_rss_mb, avg_heap_mb, max_heap_mb
```

**Changes**:
- ✅ Added `avg_heap_mb` - Average heap usage during steady-state window
- ✅ Added `max_heap_mb` - Peak heap usage during steady-state window
- ❌ Removed `heap_capacity_mb` - Incorrect values, not needed
- ❌ Removed `cpu_per_stream_percent` - Not useful for analysis
- 🔄 Changed `mem_rss_kb` → `mem_rss_mb` - Consistent units with heap metrics

**Benefits**:
- All memory metrics now in megabytes (MB) for consistency
- Average and max heap provide better insight into memory behavior
- Simpler CSV structure with only essential metrics
- Easier data analysis and comparison

## Data Source for Heap Statistics

Heap values are gathered from the **live heap safety monitor** that checks every 10 seconds during test execution. These values are written to `remote_monitor.csv`:

```csv
TIMESTAMP,CPU_PCT,HEAP_USED_MB,HEAP_CAPACITY_MB,HEAP_MAX_MB,HEAP_PCT,MEM_PCT,NET_MBPS,WOWZA_PID
```

The `parse_run.py` script aggregates these 10-second samples into average and max values for the CSV output.

## Configuration

The heap safety monitor can be configured via parameters:

```bash
start_heap_safety_monitor [check_interval] [warn_threshold] [kill_duration]
```

**Default Values**:
- `check_interval`: 10 seconds
- `warn_threshold`: 80%
- `kill_duration`: 30 seconds

**Example with Custom Values**:
```bash
start_heap_safety_monitor 5 75 60  # Check every 5s, warn at 75%, kill after 60s sustained
```

## Testing Recommendations

1. **Normal Load Test**: Verify INFO messages appear every 10 seconds
2. **Warning Test**: Trigger 80% heap and verify warning messages appear
3. **Reset Test**: Verify timer resets when heap drops below threshold
4. **Kill Test**: Verify test kills after 30 seconds sustained high heap
5. **CSV Test**: Verify avg_heap_mb and max_heap_mb appear in results.csv

## Related Files

- `orchestrator/run_orchestration.sh` - Main orchestrator with heap safety monitor
- `orchestrator/parse_run.py` - Results parser with heap statistics
- `orchestrator/remote_monitor.sh` - Remote monitoring script (unchanged)

## Migration Notes

**Existing CSV Files**: Will have old column structure. New test runs will use new structure.

**Re-enable Debug Logging**: Uncomment the `# log "DEBUG: ..."` lines in `run_orchestration.sh`

## Summary

These improvements make the heap safety monitoring more robust, informative, and flexible while streamlining the CSV output to focus on the most relevant metrics for performance analysis.
