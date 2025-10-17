# Quick Summary: Java Heap Monitoring & Metric Cleanup

## Changes Made ✅

### 1. Java Heap Monitoring (NEW)
Added `jstat -gc` to capture Java heap statistics:
- ✅ Starts automatically with other monitors
- ✅ Captures heap every 5 seconds
- ✅ Parses Eden + Old Gen usage and capacity
- ✅ Adds `heap_used_kb` and `heap_capacity_kb` to CSV

**Why:** More relevant than RSS memory for Java applications like Wowza.

---

### 2. Removed Metrics
Cleaned up CSV by removing:
- ❌ `avg_pid_cpu_percent` and `max_pid_cpu_percent` (redundant with system CPU)
- ❌ `bitrate_kbps` (already in run_id)
- ❌ `mem_per_stream_mb` (can be calculated from raw values)
- ❌ `--bitrate` argument from parse_run.py

**Why:** Simpler CSV, less redundancy, easier analysis.

---

## New CSV Columns

### Before (17 columns)
```
run_id, timestamp, protocol, resolution, video_codec, audio_codec, bitrate_kbps, connections,
avg_pid_cpu_percent, max_pid_cpu_percent, avg_sys_cpu_percent, max_sys_cpu_percent,
cpu_per_stream_percent, mem_rss_kb, mem_per_stream_mb, avg_net_tx_mbps, max_net_tx_mbps
```

### After (15 columns)
```
run_id, timestamp, protocol, resolution, video_codec, audio_codec, connections,
avg_sys_cpu_percent, max_sys_cpu_percent, cpu_per_stream_percent,
mem_rss_kb, heap_used_kb, heap_capacity_kb, avg_net_tx_mbps, max_net_tx_mbps
```

**Changes:**
- ➖ Removed: `bitrate_kbps`, `avg_pid_cpu_percent`, `max_pid_cpu_percent`, `mem_per_stream_mb`
- ➕ Added: `heap_used_kb`, `heap_capacity_kb`
- Net change: 17 → 15 columns

---

## Files Modified

1. **orchestrator/run_orchestration.sh**
   - Added jstat monitoring to `remote_start_monitors()`
   - Added jstat cleanup to `remote_stop_monitors()`
   - Removed `--bitrate` argument from parse_run.py calls

2. **orchestrator/parse_run.py**
   - Added `parse_jstat_gc()` function
   - Removed `--bitrate` argument
   - Removed avg_pid_cpu, max_pid_cpu calculations
   - Removed mem_per_stream_mb calculation
   - Updated CSV header and row data

---

## What You Get Now

### Per Test Run
- ✅ System CPU usage (avg and max)
- ✅ CPU per stream
- ✅ **Java heap used** (Eden + Old Gen)
- ✅ **Java heap capacity**
- ✅ RSS memory (fallback)
- ✅ Network throughput (avg and max)

### In Log Files
- `jstat_gc.log` - Full Java heap statistics including GC activity
- `pidstat.log` - Process CPU and RSS memory
- `sar_cpu.log` - System-wide CPU
- `sar_net.log` - Network interface statistics

---

## Testing

### Run Pilot Test
```bash
cd orchestrator
./run_orchestration.sh
# Answer 'y' to pilot mode
```

### Check Results
```bash
# View results CSV
cat orchestrator/runs/results.csv | column -t -s,

# Check heap metrics are populated
awk -F, 'NR>1 {print "Connections:",$7," Heap Used:",$12,"KB  Capacity:",$13,"KB"}' \
  orchestrator/runs/results.csv

# Calculate heap utilization
awk -F, 'NR>1 && $12>0 && $13>0 {printf "%d streams: %.1f%% heap\n", $7, ($12/$13)*100}' \
  orchestrator/runs/results.csv
```

### Verify jstat Working
```bash
# Check jstat log was created
ls -lh orchestrator/runs/*/server_logs/jstat_gc.log

# View jstat output
head orchestrator/runs/rtmp_1080p_h264_aac_*/server_logs/jstat_gc.log
```

---

## Requirements

### On Remote Server (Wowza)
- ✅ JDK installed (not just JRE) - for jstat command
- ✅ Same user running orchestrator can access Wowza process
- ✅ jstat command available in PATH

### Installation (if needed)
```bash
# Ubuntu/Debian
sudo apt-get install openjdk-11-jdk

# Or Amazon Corretto (Wowza's recommended)
sudo apt-get install amazon-corretto-11-jdk
```

---

## Benefits

### For Capacity Planning
- 📊 See actual Java heap usage vs capacity
- 📊 Understand heap growth with connection count
- 📊 Identify heap limits before running out of memory

### For Performance Analysis
- ⚡ More accurate memory metrics for Java apps
- ⚡ Simpler CSV with focused metrics
- ⚡ Can analyze GC activity from jstat_gc.log

### For Troubleshooting
- 🔍 Identify memory leaks (heap keeps growing)
- 🔍 Spot excessive GC activity
- 🔍 Correlate heap with performance issues

---

## Migration

### ⚠️ Breaking Changes
- Old CSV format incompatible with new format
- Cannot merge old and new results.csv files
- Old orchestration runs cannot be parsed with new parse_run.py

### Recommended Approach
```bash
# Archive old results
mv orchestrator/runs orchestrator/runs_old

# Create new results directory
mkdir orchestrator/runs

# Run fresh pilot test
cd orchestrator && ./run_orchestration.sh
```

---

## Quick Reference

### What's Different?

| Aspect | Before | After |
|--------|--------|-------|
| Memory metric | RSS only | **Heap + RSS** |
| CPU metric | PID + System | **System only** |
| Columns | 17 | **15** (cleaner) |
| Bitrate arg | Required | **Removed** |
| Focus | Generic | **Java-optimized** |

### Sample Output
```csv
rtmp_1080p_h264_aac_5000k_50conn,...,50,45.32,52.18,0.9064,8234567,4567890,8388608,425.234,478.901
                                     ^^  ^^^^^  ^^^^^  ^^^^^^  ^^^^^^^  ^^^^^^^  ^^^^^^^  ^^^^^^^  ^^^^^^^
                                     ||    |      |       |       |        |        |        |        └─ Max network (Mbps)
                                     ||    |      |       |       |        |        |        └─ Avg network (Mbps)
                                     ||    |      |       |       |        |        └─ Heap capacity (KB)
                                     ||    |      |       |       |        └─ Heap used (KB) ⭐ NEW
                                     ||    |      |       |       └─ RSS memory (KB)
                                     ||    |      |       └─ CPU per stream (%)
                                     ||    |      └─ Max system CPU (%)
                                     ||    └─ Avg system CPU (%)
                                     └└─ Connection count
```

---

## Documentation

See full details in: **[JAVA_HEAP_MONITORING.md](./JAVA_HEAP_MONITORING.md)**

---

## Status: ✅ COMPLETE

All changes implemented and ready to test!

**Next step:** Run pilot test to validate Java heap monitoring is working.
