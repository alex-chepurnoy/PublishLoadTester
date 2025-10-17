# Java Heap Monitoring Changes

## Summary of Changes

This document outlines the changes made to add Java heap monitoring and remove unnecessary metrics from the load testing orchestrator.

---

## 1. Java Heap Statistics with jstat ✅

### What Changed
Added `jstat -gc` monitoring to capture Java heap statistics instead of relying solely on RSS memory.

### Why This Matters
- **More accurate for Java applications**: Wowza is a Java application, so Java heap metrics are more relevant than OS-level RSS memory
- **Better capacity planning**: Understand actual heap usage vs capacity
- **GC monitoring**: Track garbage collection activity during load tests
- **Heap breakdown**: See Eden, Old Gen, and other heap spaces

### Implementation

#### Orchestration Script (`run_orchestration.sh`)
Added jstat monitoring to `remote_start_monitors()`:
```bash
if [ -n "$wowza_pid" ] && command -v jstat >/dev/null 2>&1; then 
  nohup jstat -gc -t "$wowza_pid" 5000 > $remote_dir/jstat_gc.log 2>&1 & 
  echo $! > $remote_dir/monitors/jstat.pid
fi
```

Added jstat cleanup to `remote_stop_monitors()`:
```bash
if [ -f $remote_dir/monitors/jstat.pid ]; then 
  kill $(cat $remote_dir/monitors/jstat.pid) 2>/dev/null || true
fi
```

#### Parse Script (`parse_run.py`)
Added new function `parse_jstat_gc()` to parse jstat output:
```python
def parse_jstat_gc(path):
    """Parse jstat -gc output for Java heap statistics
    
    Extracts:
    - EU (Eden Used) + OU (Old Gen Used) = Total heap used
    - EC (Eden Capacity) + OC (Old Gen Capacity) = Total heap capacity
    """
```

### Output Columns Added
- `heap_used_kb` - Average Java heap used in KB (Eden + Old Gen)
- `heap_capacity_kb` - Average Java heap capacity in KB (Eden + Old Gen)

### jstat -gc Output Format
```
Timestamp  S0C    S1C    S0U    S1U    EC      EU      OC       OU       MC      MU    CCSC   CCSU  YGC  YGCT  FGC  FGCT  CGC  CGCT   GCT
           KB     KB     KB     KB     KB      KB      KB       KB       KB      KB    KB     KB    #    secs  #    secs  #    secs   secs
```

**Key columns:**
- **EC** (Eden Capacity) - Max size of Eden space
- **EU** (Eden Used) - Current Eden usage
- **OC** (Old Gen Capacity) - Max size of Old Generation
- **OU** (Old Gen Used) - Current Old Gen usage
- **YGC** (Young GC Count) - Number of young generation GCs
- **YGCT** (Young GC Time) - Total young GC time in seconds
- **FGC** (Full GC Count) - Number of full GCs
- **FGCT** (Full GC Time) - Total full GC time in seconds

---

## 2. Removed Metrics ✅

### Removed from CSV Output

#### a) `avg_pid_cpu_percent` and `max_pid_cpu_percent`
**Why removed:**
- Redundant with system-wide CPU metrics
- System CPU (`avg_sys_cpu_percent`) is more reliable and already captured by `sar`
- Reduces CSV complexity

#### b) `bitrate_kbps`
**Why removed:**
- Bitrate is embedded in the run_id (e.g., `rtmp_1080p_h264_aac_5000k_10conn`)
- Don't need it as a separate column
- Can be extracted from run_id if needed for analysis

#### c) `mem_per_stream_mb`
**Why removed:**
- Derived metric that can be calculated in post-processing if needed
- Formula: `(mem_rss_kb / 1024) / connections`
- Raw `mem_rss_kb` and `connections` columns provide the data needed

### What Was Removed from Code

**parse_run.py:**
- Removed `--bitrate` argument
- Removed `avg_pid_cpu` and `max_pid_cpu` calculation
- Removed `mem_per_stream_mb` calculation
- Updated CSV header to remove these columns

**run_orchestration.sh:**
- Removed `--bitrate` argument from `parse_run.py` calls

---

## 3. Updated CSV Schema

### Old CSV Schema (❌ Removed)
```
run_id, timestamp, protocol, resolution, video_codec, audio_codec, bitrate_kbps, connections,
avg_pid_cpu_percent, max_pid_cpu_percent, avg_sys_cpu_percent, max_sys_cpu_percent,
cpu_per_stream_percent, mem_rss_kb, mem_per_stream_mb, avg_net_tx_mbps, max_net_tx_mbps
```

### New CSV Schema (✅ Current)
```
run_id, timestamp, protocol, resolution, video_codec, audio_codec, connections,
avg_sys_cpu_percent, max_sys_cpu_percent, cpu_per_stream_percent,
mem_rss_kb, heap_used_kb, heap_capacity_kb, avg_net_tx_mbps, max_net_tx_mbps
```

### Column Descriptions

| Column | Type | Description |
|--------|------|-------------|
| `run_id` | string | Unique identifier for the test run (e.g., `rtmp_1080p_h264_aac_5000k_10conn_20251016_143025`) |
| `timestamp` | ISO-8601 | UTC timestamp when results were parsed |
| `protocol` | string | Streaming protocol (rtmp, rtsp, srt) |
| `resolution` | string | Video resolution (4k, 1080p, 720p, 360p) |
| `video_codec` | string | Video codec (h264, h265) |
| `audio_codec` | string | Audio codec (aac, opus) |
| `connections` | integer | Number of concurrent streams |
| `avg_sys_cpu_percent` | float | Average system-wide CPU usage (from sar) |
| `max_sys_cpu_percent` | float | Maximum system-wide CPU usage |
| `cpu_per_stream_percent` | float | Average CPU per stream (avg_sys_cpu / connections) |
| `mem_rss_kb` | integer | RSS memory in KB (from pidstat or ps) |
| `heap_used_kb` | integer | **NEW** - Average Java heap used in KB |
| `heap_capacity_kb` | integer | **NEW** - Average Java heap capacity in KB |
| `avg_net_tx_mbps` | float | Average network transmit in Mbps |
| `max_net_tx_mbps` | float | Maximum network transmit in Mbps |

---

## 4. Metrics Priority

### CPU Metrics (Best → Fallback)
1. ✅ **System CPU** (`sar -u`) - Most reliable, always available
2. ❌ ~~Process CPU~~ (`pidstat -p <pid>`) - Removed, less reliable for Java

### Memory Metrics (Best → Fallback)
1. ✅ **Java Heap** (`jstat -gc`) - Best for Java apps, if available
2. ✅ **RSS Memory** (`pidstat` or `ps`) - Fallback if jstat not available

### Network Metrics (Best → Fallback)
1. ✅ **sar network** (`sar -n DEV`) - Preferred, more reliable
2. ✅ **ifstat** - Fallback if available

---

## 5. Benefits of These Changes

### For Analysis
- ✅ **More relevant metrics** for Java applications (heap vs RSS)
- ✅ **Simpler CSV** with fewer redundant columns
- ✅ **Heap capacity tracking** to understand when limits are approached
- ✅ **Better GC insights** from jstat logs

### For Capacity Planning
- ✅ Understand actual heap usage patterns
- ✅ Identify when heap is approaching capacity
- ✅ Track GC frequency and duration
- ✅ Optimize JVM heap settings based on actual usage

### For Troubleshooting
- ✅ Correlate heap usage with connection counts
- ✅ Identify memory leaks (increasing heap_used without increasing connections)
- ✅ Spot excessive GC activity (check jstat_gc.log directly)

---

## 6. Example Output

### Sample CSV Row (New Format)
```csv
rtmp_1080p_h264_aac_5000k_50conn_20251016_143025,2025-10-16T14:35:42Z,rtmp,1080p,h264,aac,50,45.32,52.18,0.9064,8234567,4567890,8388608,425.234,478.901
```

**Parsed:**
- Run: rtmp, 1080p, h264, aac, 5000k bitrate, 50 connections
- System CPU: 45.32% avg, 52.18% max
- CPU per stream: 0.9064%
- RSS Memory: 8.2 GB
- Heap Used: 4.4 GB (53% of capacity)
- Heap Capacity: 8 GB
- Network: 425 Mbps avg, 479 Mbps max

### Sample jstat_gc.log
```
Timestamp       S0C     S1C     S0U     S1U      EC       EU        OC         OU       MC      MU    CCSC   CCSU  YGC   YGCT    FGC    FGCT     CGC    CGCT       GCT   
         0.0  87040.0 87040.0   0.0   12345.6  696320.0 234567.8  1398272.0  567890.1  90112.0 85432.1  11904.0 11234.5   12    0.145    2    0.089     -        -    0.234
       5000.0  87040.0 87040.0 23456.7   0.0   696320.0 345678.9  1398272.0  678901.2  90112.0 86543.2  11904.0 11345.6   13    0.156    2    0.089     -        -    0.245
```

---

## 7. Usage Examples

### Running a Test
```bash
cd orchestrator
./run_orchestration.sh

# When prompted:
Run pilot subset only? (y/N): y
```

The orchestrator will automatically:
1. Start jstat monitoring (if Java/jstat available on remote server)
2. Collect heap statistics every 5 seconds
3. Parse jstat_gc.log and add heap metrics to results.csv

### Manual Parsing
If you need to re-parse a run:
```bash
python3 orchestrator/parse_run.py \
  --run-dir orchestrator/runs/rtmp_1080p_h264_aac_5000k_50conn_20251016_143025 \
  --run-id rtmp_1080p_h264_aac_5000k_50conn_20251016_143025 \
  --protocol rtmp \
  --resolution 1080p \
  --video-codec h264 \
  --audio-codec aac \
  --connections 50 \
  --wowza-pid 12345
```

Note: `--bitrate` argument no longer needed!

### Analyzing Results
```bash
# View results CSV
cat orchestrator/runs/results.csv | column -t -s,

# Check heap usage trends
awk -F, 'NR>1 {print $7,$12,$13}' orchestrator/runs/results.csv | column -t
# Output: connections heap_used_kb heap_capacity_kb

# Calculate heap utilization percentage
awk -F, 'NR>1 && $12>0 && $13>0 {printf "%d connections: %.1f%% heap used\n", $7, ($12/$13)*100}' orchestrator/runs/results.csv
```

---

## 8. Troubleshooting

### Issue: No heap_used_kb or heap_capacity_kb values

**Possible causes:**
1. jstat not available on remote server
2. Wowza PID not detected
3. jstat command failed

**Solution:**
```bash
# Check if jstat available on server
ssh ubuntu@54.67.101.210 "command -v jstat"

# Check jstat_gc.log for errors
cat orchestrator/runs/<run_id>/server_logs/jstat_gc.log

# Verify Wowza PID was detected
cat orchestrator/runs/<run_id>/server_logs/monitors/wowza_detection.log
```

### Issue: Empty jstat_gc.log

**Possible causes:**
1. jstat requires JDK (not just JRE)
2. Permission issues

**Solution:**
```bash
# Install JDK on Ubuntu server
sudo apt-get install openjdk-11-jdk

# Or for Amazon Corretto (Wowza's recommended JDK)
sudo apt-get install amazon-corretto-11-jdk
```

### Issue: jstat permission denied

**Solution:**
```bash
# Run as same user as Wowza process
# Check Wowza user
ps aux | grep [W]owza

# If Wowza runs as 'wowza' user, SSH as that user
# or grant permissions to monitor processes
```

---

## 9. Next Steps

### For Users
1. ✅ Run new pilot test to validate changes
2. ✅ Verify heap metrics appear in results.csv
3. ✅ Check jstat_gc.log files are being collected
4. ✅ Compare heap usage across different connection counts

### For Analysis
- Plot heap_used vs connections to find linear relationship
- Calculate heap per stream: `heap_used_kb / connections`
- Identify heap capacity limits for capacity planning
- Monitor GC activity in jstat_gc.log for performance issues

### Future Enhancements
- Add GC pause time aggregation (YGCT, FGCT)
- Track GC frequency (YGC, FGC delta between samples)
- Alert if heap usage exceeds 85% of capacity
- Add heap per stream calculation (similar to cpu_per_stream)

---

## 10. Migration Notes

### Existing Results
Old results.csv files with the old schema will still work but:
- Cannot be merged with new results (different columns)
- Need to be parsed separately for analysis
- Recommend archiving old results before running new tests

### Backward Compatibility
The parser is **NOT** backward compatible with old orchestration runs because:
- Old runs don't have jstat_gc.log
- Old orchestration calls included --bitrate argument
- To parse old runs, use the old version of parse_run.py

### Starting Fresh
Recommended approach:
1. Archive old results: `mv orchestrator/runs orchestrator/runs_old`
2. Create new results directory: `mkdir orchestrator/runs`
3. Run new pilot: `cd orchestrator && ./run_orchestration.sh`
4. Verify new CSV schema is correct

---

## Summary

✅ **Added:**
- jstat -gc monitoring for Java heap statistics
- `heap_used_kb` column
- `heap_capacity_kb` column
- Better memory metrics for Java applications

❌ **Removed:**
- `avg_pid_cpu_percent` and `max_pid_cpu_percent` columns (redundant)
- `bitrate_kbps` column (embedded in run_id)
- `mem_per_stream_mb` column (can be derived)
- `--bitrate` argument from parse_run.py

✨ **Result:**
- More relevant metrics for Java applications
- Simpler, cleaner CSV schema
- Better capacity planning insights
- Improved troubleshooting capabilities
