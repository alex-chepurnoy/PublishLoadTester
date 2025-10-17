# Data Collection Review & Fixes Summary

## Date: October 17, 2025

---

## Executive Summary

✅ **9 pilot runs completed successfully** (RTMP, 1080p, H.264, 1/5/10 connections, 3000/5000/8000k bitrates)

❌ **Critical monitoring gaps identified:**
- Wowza process-specific CPU: 0% (broken PID detection)
- Memory usage: Empty (consequence of PID issue)  
- Network throughput: 0 Mbps (ifstat not installed)

✅ **System-wide CPU metrics working correctly:**
- Accurate measurements (1.32% - 5.53% depending on load)
- Proper per-stream calculations
- Good scaling characteristics observed

---

## Issues Found

### 1. **Wowza PID Detection FAILED** ⚠️ CRITICAL

**Problem:**
```bash
wowza_pid=$(pgrep -f Wowza || pgrep -f WowzaMediaServer || pgrep -f 'java' | head -n1 || true)
```
Returns **multiple PIDs** instead of one, causing pidstat to fail.

**Evidence:**
- `wowza.pid` contains 6 PIDs
- `pidstat.log` shows only usage help (command failed)
- All Wowza CPU metrics = 0.00%

**Fix Applied:**
```bash
# Improved PID detection - finds main Wowza process by memory usage
wowza_pid=$(ps aux | grep -E '[Ww]owza|WowzaStreamingEngine' | grep java | grep -v grep | sort -k6 -rn | head -n1 | awk '{print $2}')
```

---

### 2. **Network Monitoring FAILED** ⚠️ HIGH

**Problem:**
- `ifstat` command not installed on server
- `ifstat.log` shows: "failed to run command 'ifstat': No such file or directory"
- All network metrics = 0.000 Mbps

**Fix Applied:**
- Added `sar -n DEV 5` as network monitor (already available)
- Made ifstat optional (only runs if available)
- Updated parser to prioritize sar_net data over ifstat

---

### 3. **Memory Monitoring INCOMPLETE** ⚠️ MEDIUM

**Problem:**
- `wowza_proc.txt` empty (consequence of PID issue)
- `pidstat.log` should include memory but fails
- All memory metrics empty

**Fix Applied:**
- Fixed pidstat parser to extract RSS memory
- Improved ps command to include more columns: `pid,rss,vsz,pmem,pcpu,cmd`
- Added fallback: pidstat memory → wowza_proc.txt → empty

---

## Fixes Applied

### orchestrator/run_orchestration.sh

#### Changed: `remote_start_monitors()`
```bash
# OLD - broken PID detection
wowza_pid=$(pgrep -f Wowza || pgrep -f WowzaMediaServer || pgrep -f 'java' | head -n1)

# NEW - improved detection + logging
wowza_pid=$(ps aux | grep -E '[Ww]owza|WowzaStreamingEngine|WowzaMediaServer' | grep java | grep -v grep | sort -k6 -rn | head -n1 | awk '{print $2}')
echo "Detected Wowza PID: $wowza_pid" > $remote_dir/monitors/wowza_detection.log

# Added sar network monitoring
nohup sar -n DEV 5 > $remote_dir/sar_net.log 2>&1 & echo $! > $remote_dir/monitors/sar_net.pid

# Made ifstat optional
if command -v ifstat >/dev/null 2>&1; then 
  nohup ifstat -t 5 > $remote_dir/ifstat.log 2>&1 & 
fi
```

#### Changed: `remote_stop_monitors()`
```bash
# Added sar_net.pid cleanup
if [ -f $remote_dir/monitors/sar_net.pid ]; then kill $(cat ...); fi

# Improved ps command for wowza_proc.txt
ps -p $pid -o pid,rss,vsz,pmem,pcpu,cmd --no-headers > $remote_dir/wowza_proc.txt
```

---

### orchestrator/parse_run.py

#### Enhanced: `parse_pidstat()`
```python
# OLD - only captured CPU
results.append((ts, pid, cpu_val))

# NEW - captures both CPU and RSS memory
results.append((ts, pid, cpu_val, rss_val))
```

#### Added: `parse_sar_net()`
```python
def parse_sar_net(path):
    """Parse sar -n DEV output for network interface stats"""
    # Extracts txkB/s from sar network device output
    # Skips loopback interface
    # Returns list of transmission rates in kB/s
```

#### Enhanced: Network data priority
```python
# NEW - prioritize sar_net over ifstat
if sar_net:
    avg_net_tx_kbps, max_net_tx_kbps = aggregate(sar_net)
    avg_if_tx_mbps = kbps_to_mbps(avg_net_tx_kbps)
    max_if_tx_mbps = kbps_to_mbps(max_net_tx_kbps)
else:
    # Fall back to ifstat if available
    ...
```

#### Enhanced: Memory data priority
```python
# NEW - prioritize pidstat memory over wowza_proc.txt
if avg_pid_mem > 0:
    mem_rss_kb = int(avg_pid_mem)
else:
    # Fall back to wowza_proc.txt snapshot
    ...
```

---

## Testing Recommendations

### 1. Verify Wowza PID Detection
```bash
ssh user@server "ps aux | grep -E '[Ww]owza|WowzaStreamingEngine' | grep java | grep -v grep | sort -k6 -rn | head -n1"
```
Should return **exactly one line** with the main Wowza process.

### 2. Check sar Availability
```bash
ssh user@server "which sar && sar -n DEV 1 1"
```
Should show network interface statistics.

### 3. Run Single Test
```bash
cd orchestrator
./run_orchestration.sh
# Select pilot mode, run 1 test
```

### 4. Validate Outputs
Check the latest run directory:
```bash
cat runs/LATEST_RUN/server_logs/monitors/wowza_detection.log  # Should show single PID
head -20 runs/LATEST_RUN/server_logs/pidstat.log              # Should show actual data, not help
head -20 runs/LATEST_RUN/server_logs/sar_net.log              # Should show interface stats
cat runs/LATEST_RUN/server_logs/wowza_proc.txt                # Should show process details
tail -1 runs/results.csv                                       # Should have non-zero metrics
```

### 5. Expected CSV Improvements

**Before (broken):**
```csv
avg_pid_cpu_percent,max_pid_cpu_percent,mem_rss_kb,avg_net_tx_mbps
0.00,0.00,,0.000
```

**After (fixed):**
```csv
avg_pid_cpu_percent,max_pid_cpu_percent,mem_rss_kb,avg_net_tx_mbps
2.35,4.82,2458624,12.456
```

---

## Data Quality Checklist

After running a test with fixes, verify:

- [ ] `wowza_detection.log` contains a single PID number
- [ ] `pidstat.log` contains actual metrics (not help text)
- [ ] `sar_net.log` contains network interface statistics
- [ ] `wowza_proc.txt` contains process details (not empty)
- [ ] `results.csv` has non-zero values for:
  - [ ] `avg_pid_cpu_percent`
  - [ ] `max_pid_cpu_percent`
  - [ ] `mem_rss_kb`
  - [ ] `avg_net_tx_mbps`
  - [ ] `max_net_tx_mbps`

---

## What's Still Good

✅ System CPU monitoring (sar -u)  
✅ Run organization and directory structure  
✅ CSV format and headers  
✅ Per-stream calculations  
✅ Orchestrator automation  
✅ SSH connectivity and retry logic  
✅ Cleanup and error handling  

---

## Next Steps

1. **Test the fixes** with a single pilot run
2. **Validate data quality** using checklist above
3. **Re-run full pilot** (9 tests) to get complete dataset
4. **Analyze results** with proper Wowza-specific metrics
5. **Scale up** to full test matrix if data looks good

---

## Files Modified

1. `orchestrator/run_orchestration.sh`
   - `remote_start_monitors()` - Improved PID detection, added sar_net, made ifstat optional
   - `remote_stop_monitors()` - Added sar_net cleanup, improved ps command

2. `orchestrator/parse_run.py`
   - `parse_pidstat()` - Now extracts RSS memory
   - `parse_sar_net()` - NEW function for network stats
   - Network parsing - Prioritizes sar_net over ifstat
   - Memory parsing - Prioritizes pidstat over wowza_proc.txt

3. `orchestrator/DATA_ANALYSIS.md` - NEW comprehensive analysis document

4. `ORCHESTRATOR_FIXES.md` - Updated with latest fixes

---

## Success Criteria

After fixes, a successful test should show:

**CPU Metrics:**
- System: 1-6% (varies with load) ✅ Already working
- Wowza: Should match or be slightly lower than system ⚠️ To be fixed
- Per stream: 0.5-1.5% ✅ Already calculated

**Memory Metrics:**
- RSS: Several GB (e.g., 2-4 GB for Wowza) ⚠️ To be fixed
- Per stream: ~200-400 MB ⚠️ To be fixed

**Network Metrics:**
- Should approximate: bitrate × connections × 1.1 ⚠️ To be fixed
- Example: 5000k × 5 streams = ~27.5 Mbps expected

---

**Status:** Ready for testing with improvements! 🚀
