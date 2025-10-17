# Orchestrator Review - Quick Reference

## Current Status

### ✅ What's Working
- **System CPU:** Accurate measurements via `sar -u`
- **Run automation:** 9 pilot runs completed successfully  
- **Data organization:** Clean directory structure per run
- **CSV output:** Proper format with all columns
- **SSH operations:** Reliable with retry logic

### ❌ What's Broken  
- **Wowza CPU:** Always 0% (PID detection returns multiple PIDs)
- **Memory:** Always empty (consequence of PID issue)
- **Network:** Always 0 Mbps (ifstat not installed)

---

## Root Causes

1. **PID Detection Bug**
   ```bash
   # BROKEN: Returns 6 PIDs instead of 1
   pgrep -f Wowza || pgrep -f WowzaMediaServer || pgrep -f 'java' | head -n1
   ```

2. **Missing Tool**
   - `ifstat` not installed on Ubuntu server
   - No fallback mechanism

3. **Parser Limitations**
   - Didn't extract memory from pidstat
   - No support for sar network data

---

## Fixes Applied

### 1. Fixed PID Detection (orchestrator/run_orchestration.sh)
```bash
# NEW: Finds main Wowza Java process by memory usage
wowza_pid=$(ps aux | grep -E '[Ww]owza|WowzaStreamingEngine' | \
            grep java | grep -v grep | \
            sort -k6 -rn | head -n1 | awk '{print $2}')
```

### 2. Added Network Monitoring (orchestrator/run_orchestration.sh)
```bash
# NEW: Use sar for network (always available)
nohup sar -n DEV 5 > $remote_dir/sar_net.log 2>&1 &

# Made ifstat optional
if command -v ifstat >/dev/null 2>&1; then ...
```

### 3. Enhanced Parser (orchestrator/parse_run.py)
- `parse_pidstat()` now extracts RSS memory
- `parse_sar_net()` NEW function for network data
- Prioritizes sar_net over ifstat
- Prioritizes pidstat memory over ps snapshot

---

## Before & After

### CSV Metrics (Example: 5 streams @ 5000k)

| Metric | Before | After (Expected) |
|--------|--------|------------------|
| avg_sys_cpu_percent | 3.60 ✅ | 3.60 ✅ |
| avg_pid_cpu_percent | 0.00 ❌ | ~3.2 🎯 |
| mem_rss_kb | (empty) ❌ | ~2400000 🎯 |
| avg_net_tx_mbps | 0.000 ❌ | ~27.5 🎯 |

---

## Testing Steps

### Step 1: Validate Server (from orchestrator directory)
```bash
chmod +x validate_server.sh
./validate_server.sh ~/AlexC_Dev2_EC2.pem ubuntu@54.67.101.210
```

**Expected output:**
- ✓ All tools available
- ✓ Single Wowza PID detected
- ✓ pidstat test succeeds
- ✓ sar network test succeeds

### Step 2: Run Single Test
```bash
./run_orchestration.sh
# Choose: Pilot mode (y)
# Will run just 1 test
```

### Step 3: Validate Data
```bash
# Find latest run
LATEST=$(ls -t runs/2025* | head -n1)

# Check PID detection
cat runs/$LATEST/server_logs/monitors/wowza_detection.log

# Check pidstat data (should NOT be help text)
head -20 runs/$LATEST/server_logs/pidstat.log

# Check network data
head -20 runs/$LATEST/server_logs/sar_net.log

# Check process snapshot
cat runs/$LATEST/server_logs/wowza_proc.txt

# Check CSV (should have non-zero values)
tail -1 runs/results.csv
```

### Step 4: Verify CSV Values
```bash
# Expected for 1 stream @ 3000k:
# - avg_pid_cpu: ~1-2%
# - mem_rss_kb: ~2000000-4000000 (2-4 GB)
# - avg_net_tx_mbps: ~3.3 Mbps
```

---

## Quick Data Quality Check

After a test run, these should be **non-zero**:
```bash
tail -1 runs/results.csv | cut -d',' -f9   # avg_pid_cpu_percent
tail -1 runs/results.csv | cut -d',' -f14  # mem_rss_kb
tail -1 runs/results.csv | cut -d',' -f16  # avg_net_tx_mbps
```

If any are zero or empty, review the corresponding log file.

---

## Troubleshooting

### "Wowza PID still shows 0.00 CPU"
1. Check wowza_detection.log - is there a PID?
2. Check pidstat.log - actual data or help text?
3. Run validate_server.sh to test PID detection
4. May need to adjust grep pattern for your Wowza version

### "Network still shows 0.000"
1. Check sar_net.log exists and has data
2. Check interface name (might not be eth0)
3. Parser expects column 5 to be txkB/s - verify sar format

### "Memory still empty"
1. Check pidstat.log has RSS column
2. Check wowza_proc.txt is not empty
3. Verify ps command succeeded in remote_stop_monitors

---

## Files Changed

1. **orchestrator/run_orchestration.sh**
   - `remote_start_monitors()` - lines ~240-252
   - `remote_stop_monitors()` - lines ~265-275

2. **orchestrator/parse_run.py**
   - `parse_pidstat()` - lines ~18-45
   - `parse_sar_net()` - lines ~73-93 (NEW)
   - Network parsing - lines ~120-130
   - Memory parsing - lines ~135-145

3. **Documentation**
   - `DATA_ANALYSIS.md` - Full analysis of 9 pilot runs
   - `FIXES_SUMMARY.md` - Detailed fix documentation
   - `REVIEW.md` - This quick reference

4. **Utilities**
   - `validate_server.sh` - Server validation script (NEW)

---

## Next Actions

1. ✅ **Run validation:** `./orchestrator/validate_server.sh <key> <user@host>`
2. ⏳ **Single test:** Verify one run produces good data
3. ⏳ **Full pilot:** Re-run 9 tests with fixes
4. ⏳ **Analyze:** Compare new results to broken data
5. ⏳ **Scale:** Run full test matrix if data quality is good

---

## Expected Outcomes

After fixes, you should see:
- **Real Wowza CPU %** (not 0.00)
- **Memory in GB range** (not empty)  
- **Network matching bitrate × connections** (not 0.000)
- **Ability to identify bottlenecks** (CPU vs network vs memory)
- **Accurate per-stream costs** for capacity planning

---

**Last Updated:** October 17, 2025  
**Status:** Fixes applied, ready for validation testing
