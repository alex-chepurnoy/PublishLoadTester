# Pilot Mode Configuration

## Updated Pilot Settings (October 17, 2025)

### Quick Summary

**Old Pilot:**
- Duration: 12 minutes per test
- Connections: 1, 5, 10 (3 counts)
- Bitrates: 3000k, 5000k, 8000k (3 bitrates)
- **Total:** 9 tests × 12 min = ~108 minutes (1.8 hours) ⏰ TOO LONG

**New Pilot:**
- Duration: **2 minutes per test** ⚡
- Connections: **1, 5, 10, 20, 50** (5 counts)
- Bitrates: 3000k, 5000k, 8000k (3 bitrates)
- **Total:** 15 tests × 2 min = **~30 minutes** ✅

---

## Test Matrix

### Pilot Mode Test Combinations

| Test # | Connections | Bitrate | Duration | Protocol | Resolution | Codec |
|--------|-------------|---------|----------|----------|------------|-------|
| 1      | 1           | 3000k   | 2 min    | RTMP     | 1080p      | H.264 |
| 2      | 5           | 3000k   | 2 min    | RTMP     | 1080p      | H.264 |
| 3      | 10          | 3000k   | 2 min    | RTMP     | 1080p      | H.264 |
| 4      | 20          | 3000k   | 2 min    | RTMP     | 1080p      | H.264 |
| 5      | 50          | 3000k   | 2 min    | RTMP     | 1080p      | H.264 |
| 6      | 1           | 5000k   | 2 min    | RTMP     | 1080p      | H.264 |
| 7      | 5           | 5000k   | 2 min    | RTMP     | 1080p      | H.264 |
| 8      | 10          | 5000k   | 2 min    | RTMP     | 1080p      | H.264 |
| 9      | 20          | 5000k   | 2 min    | RTMP     | 1080p      | H.264 |
| 10     | 50          | 5000k   | 2 min    | RTMP     | 1080p      | H.264 |
| 11     | 1           | 8000k   | 2 min    | RTMP     | 1080p      | H.264 |
| 12     | 5           | 8000k   | 2 min    | RTMP     | 1080p      | H.264 |
| 13     | 10          | 8000k   | 2 min    | RTMP     | 1080p      | H.264 |
| 14     | 20          | 8000k   | 2 min    | RTMP     | 1080p      | H.264 |
| 15     | 50          | 8000k   | 2 min    | RTMP     | 1080p      | H.264 |

---

## Timing Breakdown

### Per-Test Duration (2 minutes)

```
Warmup:   15 seconds  (streams start, stabilize)
Steady:   90 seconds  (actual measurement window)
Cooldown: 15 seconds  (graceful shutdown)
────────────────────
Total:    120 seconds = 2 minutes
```

### Total Pilot Run Time

```
15 tests × 2 minutes = 30 minutes base time
+ 5 seconds between tests = ~1 minute overhead
+ Server monitoring overhead = ~1-2 minutes
────────────────────────────────────────────
Estimated Total: ~30-33 minutes
```

**Much better than the previous 108 minutes!** ⚡

---

## Resource Expectations

### Expected Load by Connection Count

| Connections | Expected CPU | Expected Memory | Expected Network BW |
|-------------|--------------|-----------------|---------------------|
| 1 stream    | ~1-2%        | ~200-400 MB     | ~3-8 Mbps          |
| 5 streams   | ~3-5%        | ~1-2 GB         | ~15-40 Mbps        |
| 10 streams  | ~5-8%        | ~2-4 GB         | ~30-80 Mbps        |
| 20 streams  | ~10-15%      | ~4-8 GB         | ~60-160 Mbps       |
| 50 streams  | ~20-35%      | ~10-20 GB       | ~150-400 Mbps      |

**Note:** These are estimates. Actual values depend on server hardware and Wowza configuration.

---

## When to Use Pilot Mode

### ✅ Use Pilot When:

- **Quick validation** - Testing if setup works correctly
- **Initial baseline** - Getting rough performance numbers
- **Configuration changes** - Verifying Wowza config changes
- **Server comparison** - Comparing different server types
- **Development** - Testing orchestrator changes
- **Time-limited** - Need results in ~30 minutes

### ⚠️ Don't Use Pilot When:

- **Production capacity planning** - Need full 10-minute steady state
- **Benchmarking** - Need precise, stable measurements
- **Quality analysis** - Need time for system to show patterns
- **High connection counts** - Need time for connections to stabilize
- **Official reports** - Need longer sampling for statistical confidence

---

## Full Test Matrix (Non-Pilot)

For comparison, here's what the **full test matrix** looks like:

**Configuration:**
- Protocols: RTMP, RTSP, SRT (3)
- Resolutions: 4K, 1080p, 720p, 360p (4)
- Video Codecs: H.264, H.265 (2)
- Bitrates: Low, Mid, High (3 per resolution)
- Connections: 1, 2, 5, 10, 20, 50 (6)
- Duration: 12 minutes per test

**Total combinations:** 3 × 4 × 2 × 3 × 6 = **432 tests**  
**Estimated time:** 432 × 12 min = **~86 hours** (3.6 days!) 😱

**This is why pilot mode exists!**

---

## Running Pilot Mode

### Start the Orchestrator

```bash
cd orchestrator
./run_orchestration.sh
```

### When Prompted

```
Run pilot subset only? (y/N): y
```

### Expected Output

```
Pilot mode: reducing matrix for quick validation
Pilot mode: 2-minute tests, 5 connection counts (1,5,10,20,50), 3 bitrates (3000k,5000k,8000k)
Pilot mode: Total tests = 15, estimated time = ~30 minutes
```

---

## Interpreting Results

After the pilot completes, check `orchestrator/runs/results.csv`:

### Key Metrics to Look For

1. **System CPU Scaling**
   - Should increase roughly linearly with connections
   - Example: 1 conn = 1.5%, 5 conn = 3.5%, 10 conn = 5.5%

2. **CPU Per Stream**
   - Should be relatively consistent across connection counts
   - Example: ~0.5-0.7% per stream regardless of total connections

3. **Memory Usage**
   - Should scale linearly with connections
   - Look for memory leaks (increasing per-stream memory)

4. **Network Throughput**
   - Should match: `bitrate × connections × 1.1` (overhead)
   - Example: 5000k × 10 streams = ~55 Mbps

5. **Server Saturation Point**
   - Note where CPU reaches 70-80%
   - This indicates your server's practical limit

---

## Example Results Analysis

### Sample CSV Output

```csv
connections,bitrate_kbps,avg_sys_cpu_percent,cpu_per_stream_percent,avg_net_tx_mbps
1,3000,1.32,1.3200,3.3
5,3000,3.35,0.6700,16.5
10,3000,4.86,0.4860,33.0
20,3000,8.12,0.4060,66.0
50,3000,18.45,0.3690,165.0
1,5000,1.48,1.4800,5.5
5,5000,3.60,0.7200,27.5
10,5000,5.51,0.5510,55.0
20,5000,9.23,0.4615,110.0
50,5000,21.34,0.4268,275.0
```

### Insights from Sample Data

**✅ Good Signs:**
- CPU per stream decreases with scale (efficiency!)
- Network throughput matches expected (no bottleneck)
- CPU under 25% even at 50 streams

**📈 Capacity Estimate:**
- Current: 50 streams @ 5000k = 21% CPU
- Estimated max: ~150-200 concurrent streams before saturation

**⚠️ Watch For:**
- If 50-stream tests fail/timeout → Need better hardware
- If CPU per stream increases → System inefficiency
- If network doesn't scale → Network bottleneck

---

## Next Steps After Pilot

### If Results Look Good

1. ✅ **Increase connection counts** - Try 100, 200 streams
2. ✅ **Test other protocols** - Add RTSP, SRT tests
3. ✅ **Test other codecs** - Add H.265 tests
4. ✅ **Longer duration** - Run full 12-minute tests

### If Results Show Issues

1. ⚠️ **Check server resources** - Is hardware sufficient?
2. ⚠️ **Tune Wowza config** - Adjust thread pools, memory
3. ⚠️ **Check network** - Is bandwidth adequate?
4. ⚠️ **Review logs** - Look for errors in server_logs/

---

## Time Savings Comparison

| Scenario | Old Pilot | New Pilot | Savings |
|----------|-----------|-----------|---------|
| Quick test | 108 min | 30 min | **-72%** ⚡ |
| Daily runs | 1.8 hrs | 0.5 hrs | **Save 1.3 hrs/day** |
| Weekly validation | 12.6 hrs | 3.5 hrs | **Save 9.1 hrs/week** |

**You can now run 3.6× more pilot tests in the same time!** 🚀

---

## Summary

**New Pilot Configuration:**
- ⚡ **2 minutes** per test (was 12 min)
- 📊 **5 connection counts** (was 3): 1, 5, 10, 20, 50
- 🎯 **15 total tests** (was 9)
- ⏱️ **~30 minutes total** (was 108 min)
- 💪 **Better coverage** - More connection counts tested
- 🚀 **Much faster** - 72% time reduction

**Perfect for rapid iteration and validation!**
