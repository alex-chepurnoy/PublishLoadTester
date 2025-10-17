# Orchestrator Data Collection Analysis
## Date: October 17, 2025

## Summary of 9 Pilot Runs

All 9 runs completed successfully:
- **Protocol:** RTMP
- **Resolution:** 1080p (H.264 + AAC)
- **Bitrates:** 3000k, 5000k, 8000k
- **Connections:** 1, 5, 10
- **Duration:** 12 minutes each

---

## Data Collection Status

### ✅ **Working Correctly**

1. **System-Wide CPU (sar_cpu.log)**
   - ✅ Collecting every 5 seconds
   - ✅ Parsing correctly
   - ✅ Shows avg_sys_cpu_percent and max_sys_cpu_percent in CSV
   - **Example:** Run with 10 connections @ 8000k showed 5.53% avg CPU, 9.37% max

2. **CPU Per Stream Calculation**
   - ✅ Calculated as: `avg_sys_cpu / connections`
   - **Results:**
     - 1 stream: ~1.32-1.48% CPU per stream
     - 5 streams: ~0.61-0.72% CPU per stream
     - 10 streams: ~0.49-0.55% CPU per stream

3. **Run Organization**
   - ✅ Each run has proper directory structure
   - ✅ Client logs captured
   - ✅ Server logs fetched via SSH
   - ✅ results.csv aggregated correctly

---

## ❌ **Critical Issues Found**

### **1. Wowza Process-Specific Monitoring FAILED**

**Problem:** `pidstat` command is completely failing

**Root Cause:** The PID detection command is returning **multiple PIDs** instead of one:
```bash
wowza_pid=$(pgrep -f Wowza || pgrep -f WowzaMediaServer || pgrep -f 'java' | head -n1 || true)
```

**Evidence from wowza.pid file:**
```
14483
14485
21608
21743
122887
122889
```

**Impact:**
- `pidstat -p "$wowza_pid"` fails because it receives multiple PIDs on one line
- Results in pidstat.log containing only the usage help text
- All Wowza-specific metrics show **0.00** in CSV:
  - `avg_pid_cpu_percent: 0.00`
  - `max_pid_cpu_percent: 0.00`
  - `mem_rss_kb: (empty)`

**Why This Matters:**
- We can't distinguish between system-wide CPU and Wowza-specific CPU
- We can't measure memory usage per stream
- We can't identify if Wowza is the bottleneck vs other processes

---

### **2. Network Monitoring FAILED**

**Problem:** `ifstat` command not found on the server

**Evidence from ifstat.log:**
```
nohup: failed to run command 'ifstat': No such file or directory
```

**Impact:**
- All network metrics show **0.000** in CSV:
  - `avg_net_tx_mbps: 0.000`
  - `max_net_tx_mbps: 0.000`

**Why This Matters:**
- Can't measure actual network throughput
- Can't verify if streams are achieving target bitrate
- Can't detect network saturation

---

### **3. Memory Monitoring FAILED**

**Problem:** `wowza_proc.txt` is empty (consequence of issue #1)

**Impact:**
- `mem_rss_kb` field is empty in CSV
- `mem_per_stream_mb` shows 0.000

**Why This Matters:**
- Can't track memory consumption per connection
- Can't identify memory leaks or scaling issues

---

## 📊 Current CSV Data Quality

| Metric | Status | Values |
|--------|--------|--------|
| System CPU (avg/max) | ✅ Good | 1.32% - 5.53% |
| CPU per stream | ✅ Good | 0.49% - 1.48% |
| Wowza CPU | ❌ Missing | Always 0.00 |
| Memory (RSS) | ❌ Missing | Always empty |
| Memory per stream | ❌ Missing | Always 0.000 |
| Network TX (avg/max) | ❌ Missing | Always 0.000 |

---

## 🔧 Required Fixes

### **Fix #1: Wowza PID Detection (CRITICAL)**

**Current broken code:**
```bash
wowza_pid=$(pgrep -f Wowza || pgrep -f WowzaMediaServer || pgrep -f 'java' | head -n1 || true)
```

**Issue:** The OR operators execute in sequence, and `pgrep -f 'java' | head -n1` runs AFTER the previous pgreps succeed, appending all Java PIDs.

**Solution:**
```bash
wowza_pid=$(pgrep -f WowzaStreamingEngine | head -n1 || pgrep -f WowzaMediaServer | head -n1 || pgrep -f 'java.*wowza' -i | head -n1 || echo "")
```

Better yet, use a more specific pattern or ask the user for the correct process name during setup.

**Alternative - Get Main Java Process:**
```bash
# Find the main Wowza Java process (typically has highest memory)
wowza_pid=$(ps aux | grep -i wowza | grep java | grep -v grep | sort -k6 -rn | head -n1 | awk '{print $2}')
```

---

### **Fix #2: Install ifstat or Use Alternative (HIGH)**

**Option A: Install ifstat on remote server**
```bash
sudo apt-get install -y ifstat
```

**Option B: Use sar for network (already available)**
Replace ifstat with `sar -n DEV 5`:
```bash
nohup sar -n DEV 5 > $remote_dir/sar_net.log 2>&1 &
```

Then update parser to parse sar network output.

**Option C: Use /proc/net/dev directly**
```bash
# Monitor specific interface (e.g., eth0)
while true; do 
  date +%T; 
  cat /proc/net/dev | grep eth0; 
  sleep 5; 
done > $remote_dir/net_stats.log
```

---

### **Fix #3: Improve Parser to Calculate Network from Multiple Sources**

**Current:** Parser only looks at ifstat

**Better:** Add fallback parsing:
1. Try ifstat.log
2. If empty, try sar_net.log (if we implement Option B above)
3. If empty, try to parse sar_cpu.log for network sections
4. Calculate expected bandwidth: `bitrate_kbps * connections * 1.1 (overhead)`

---

## 📈 Data Insights from System CPU

Despite missing Wowza-specific data, system CPU shows interesting patterns:

| Connections | 3000k CPU | 5000k CPU | 8000k CPU |
|-------------|-----------|-----------|-----------|
| 1 stream    | 1.38%     | 1.32%     | 1.48%     |
| 5 streams   | 3.35%     | 3.60%     | 3.07%     |
| 10 streams  | 4.86%     | 5.51%     | 5.53%     |

**Observations:**
- CPU scales sub-linearly with connections (good!)
- Bitrate doesn't significantly impact CPU (H.264 encoding is client-side)
- Server is under 6% CPU even with 10x 8000k streams
- Plenty of headroom for more connections

---

## 🎯 Recommended Action Plan

### **Priority 1: Fix Wowza PID Detection**
- Update `remote_start_monitors()` in orchestrator
- Test on actual Wowza server to ensure single PID returned
- Add logging to show which PID was selected

### **Priority 2: Add Network Monitoring**
- Install ifstat on server OR use sar alternative
- Update parser to handle new network data source
- Validate actual throughput vs expected (bitrate × connections)

### **Priority 3: Improve Parser**
- Add better error handling for missing data
- Add calculated fields (expected bandwidth)
- Add data quality indicators to CSV

### **Priority 4: Add More Metrics**
- Disk I/O (if recording/transcoding)
- Connection count verification
- Stream health/errors from Wowza logs
- Frame drop detection from client logs

---

## 📝 Next Steps

1. **Review Wowza process names on server**
   ```bash
   ssh user@server "ps aux | grep -i wowza | grep -v grep"
   ```

2. **Check available monitoring tools**
   ```bash
   ssh user@server "which ifstat sar pidstat"
   ```

3. **Apply fixes to orchestrator script**

4. **Run single test to validate**

5. **Re-run pilot with corrected monitoring**

6. **Compare results to validate data quality**

---

## ✅ What's Already Good

- CSV format is clean and readable
- System-wide CPU metrics are accurate
- Run organization is excellent
- Timestamp tracking works
- CPU per stream calculation is correct
- No crashes or data loss
- Orchestrator automation works well

The foundation is solid - we just need to fix the process-specific monitoring!
