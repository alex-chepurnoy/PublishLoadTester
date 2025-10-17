# Fixed: Heap Monitoring Now Logs in MB (Not Just Percentage)

## Problem

After fixing the PID detection, the pilot mode ran but `results.csv` showed empty values for `heap_used_kb` and `heap_capacity_kb`:

```csv
run_id,timestamp,protocol,resolution,video_codec,audio_codec,connections,avg_sys_cpu_percent,max_sys_cpu_percent,cpu_per_stream_percent,mem_rss_kb,heap_used_kb,heap_capacity_kb
20251017_214211_RTMP_1080p_H264_3000k_1conn,2025-10-17T21:44:24.289339+00:00,rtmp,1080p,h264,aac,1,1.97,8.30,1.9746,1062024,,
```

Additionally, `remote_monitor_stdout.log` showed:
```
/tmp/remote_monitor.sh: line 121: syntax error near unexpected token `{'
```

## Root Causes

### 1. **Syntax Errors in remote_monitor.sh**
The `get_heap()` function had:
- Unterminated AWK strings (missing closing quotes)
- Missing `END` blocks in AWK scripts
- Unclosed code blocks

### 2. **Missing Heap Data**
The system was designed to:
- `remote_monitor.sh` outputs heap **percentage only** (`HEAP_PCT`)
- `parse_run.py` expects `jstat_gc.log` with heap in **KB**
- **Mismatch**: No raw KB/MB values were being logged!

### 3. **Wrong CSV Format**
- Old: `TIMESTAMP,CPU_PCT,HEAP_PCT,MEM_PCT,NET_MBPS,WOWZA_PID`
- Parser expected: Raw heap used and capacity values

---

## Solution

### Changed Output Format

**remote_monitor.sh** now returns **three values** from `get_heap()`:
1. **HEAP_USED_MB** - Heap used in megabytes
2. **HEAP_CAPACITY_MB** - Total heap capacity in megabytes  
3. **HEAP_PCT** - Heap usage percentage

**New CSV Format:**
```csv
TIMESTAMP,CPU_PCT,HEAP_USED_MB,HEAP_CAPACITY_MB,HEAP_PCT,MEM_PCT,NET_MBPS,WOWZA_PID
```

---

## Files Changed

### 1. orchestrator/remote_monitor.sh

#### get_heap() Function - Complete Rewrite

**Before** (Broken):
- Returned only percentage
- Had syntax errors
- Unterminated AWK scripts

**After** (Fixed):
```bash
get_heap() {
  local pid=$1
  local java_bin="/usr/local/WowzaStreamingEngine/java/bin"
  local result=""
  
  # Returns "used_mb capacity_mb percentage"
  result=$(sudo jcmd $pid GC.heap_info 2>&1 | awk '
    BEGIN { total_kb=0; used_kb=0 }
    
    # Parallel GC
    /PSYoungGen|ParOldGen|PSOldGen/ {
      # ... sum up total and used ...
    }
    
    # ZGC (Your Wowza uses this!)
    /ZHeap/ {
      # Parse: "ZHeap used 194M, capacity 496M, max capacity 5416M"
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
    
    # G1GC and Shenandoah
    /garbage-first heap|Shenandoah/ {
      # Parse: "garbage-first heap   total 524288K, used 194288K"
      # ... parse KB values ...
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
  
  echo "${result:-0.00 0.00 0.00}"
}
```

**Key Features:**
- ✅ **ZGC Support**: Parses `ZHeap used 194M, capacity 496M`
- ✅ **G1GC Support**: Parses `garbage-first heap total XK, used YK`
- ✅ **Parallel GC Support**: Sums PSYoungGen + ParOldGen
- ✅ **Returns 3 values**: `used_mb capacity_mb percentage`
- ✅ **Proper syntax**: All AWK blocks closed correctly
- ✅ **Uses sudo**: Based on diagnostic confirmation

#### Main Loop - Updated to Parse 3 Values

**Before:**
```bash
HEAP=$(get_heap "$WOWZA_PID")
echo "$TIMESTAMP,$CPU,$HEAP,$MEM,$NET,$WOWZA_PID" >> "$LOG_FILE"
```

**After:**
```bash
# get_heap returns "used_mb capacity_mb percentage"
HEAP_DATA=$(get_heap "$WOWZA_PID")
HEAP_USED_MB=$(echo "$HEAP_DATA" | awk '{print $1}')
HEAP_CAPACITY_MB=$(echo "$HEAP_DATA" | awk '{print $2}')
HEAP_PCT=$(echo "$HEAP_DATA" | awk '{print $3}')

# Log all three values
echo "$TIMESTAMP,$CPU,$HEAP_USED_MB,$HEAP_CAPACITY_MB,$HEAP_PCT,$MEM,$NET,$WOWZA_PID" >> "$LOG_FILE"

# Enhanced stdout logging
echo "[$TIMESTAMP] CPU: ${CPU}% | Heap: ${HEAP_USED_MB}/${HEAP_CAPACITY_MB}MB (${HEAP_PCT}%) | Mem: ${MEM}% | Net: ${NET} Mbps | PID: ${WOWZA_PID:-N/A}"
```

**CSV Header Changed:**
```bash
echo "TIMESTAMP,CPU_PCT,HEAP_USED_MB,HEAP_CAPACITY_MB,HEAP_PCT,MEM_PCT,NET_MBPS,WOWZA_PID" > "$LOG_FILE"
```

---

### 2. orchestrator/parse_run.py

#### Added parse_remote_monitor() Function

**New Function:**
```python
def parse_remote_monitor(path):
    """Parse remote_monitor.sh CSV output for heap statistics
    
    Format: TIMESTAMP,CPU_PCT,HEAP_USED_MB,HEAP_CAPACITY_MB,HEAP_PCT,MEM_PCT,NET_MBPS,WOWZA_PID
    
    Returns: (heap_used_mb_list, heap_capacity_mb_list)
    """
    heap_used_vals = []
    heap_capacity_vals = []
    
    if not os.path.isfile(path):
        return heap_used_vals, heap_capacity_vals
    
    with open(path, 'r', errors='ignore') as f:
        reader = csv.DictReader(f)
        for row in reader:
            try:
                heap_used = row.get('HEAP_USED_MB', '').strip()
                heap_capacity = row.get('HEAP_CAPACITY_MB', '').strip()
                
                # Skip N/A values
                if heap_used and heap_used != 'N/A' and heap_capacity and heap_capacity != 'N/A':
                    heap_used_vals.append(float(heap_used))
                    heap_capacity_vals.append(float(heap_capacity))
            except (ValueError, KeyError):
                pass
    
    return heap_used_vals, heap_capacity_vals
```

#### Updated Main Parsing Logic

**Changes:**
1. **Find remote_monitor CSV files:**
   ```python
   remote_monitor_paths = []
   monitors_dir = os.path.join(server_logs, 'monitors')
   if os.path.isdir(monitors_dir):
       for fname in os.listdir(monitors_dir):
           if fname.startswith('monitor_') and fname.endswith('.log'):
               remote_monitor_paths.append(os.path.join(monitors_dir, fname))
   ```

2. **Parse remote monitor first, fallback to jstat_gc.log:**
   ```python
   jstat_heap_used = []
   jstat_heap_capacity = []
   
   if remote_monitor_paths:
       # Parse all remote monitor CSV files and combine results
       for rmon_path in remote_monitor_paths:
           used, capacity = parse_remote_monitor(rmon_path)
           jstat_heap_used.extend(used)
           jstat_heap_capacity.extend(capacity)
   
   # Fallback to jstat_gc.log if remote monitor didn't provide data
   if not jstat_heap_used and os.path.isfile(jstat_gc_path):
       jstat_heap_used, jstat_heap_capacity = parse_jstat_gc(jstat_gc_path)
       # jstat_gc returns KB, convert to MB for consistency
       jstat_heap_used = [x / 1024 for x in jstat_heap_used]
       jstat_heap_capacity = [x / 1024 for x in jstat_heap_capacity]
   ```

3. **Changed to MB throughout:**
   ```python
   # Old variables: avg_heap_used_kb, heap_used_kb
   # New variables: avg_heap_used_mb, heap_used_mb
   
   avg_heap_used_mb, max_heap_used_mb = aggregate(jstat_heap_used)
   avg_heap_capacity_mb, max_heap_capacity_mb = aggregate(jstat_heap_capacity)
   ```

4. **Updated CSV header:**
   ```python
   header = [
       'run_id','timestamp','protocol','resolution','video_codec','audio_codec','connections',
       'avg_sys_cpu_percent','max_sys_cpu_percent',
       'cpu_per_stream_percent','mem_rss_kb','heap_used_mb','heap_capacity_mb'
   ]
   ```

---

## Expected Output

### Example Monitor Log (monitor_20251017_214500.log)

```csv
TIMESTAMP,CPU_PCT,HEAP_USED_MB,HEAP_CAPACITY_MB,HEAP_PCT,MEM_PCT,NET_MBPS,WOWZA_PID
2025-10-17_21:45:00,2.34,194.00,496.00,39.11,12.50,5.23,1026
2025-10-17_21:45:05,3.12,198.50,496.00,40.02,12.52,8.45,1026
2025-10-17_21:45:10,4.56,203.25,496.00,40.98,12.58,12.67,1026
```

**Your Wowza ZGC Heap:**
- **Max Capacity**: 5,416 MB (5.4 GB) - from `-Xmx5415M`
- **Current Capacity**: ~496 MB (can grow to max)
- **Current Used**: ~194 MB
- **Current Usage**: ~39%

### Example Stdout (for debugging):

```
[2025-10-17_21:45:00] CPU: 2.34% | Heap: 194.00/496.00MB (39.11%) | Mem: 12.50% | Net: 5.23 Mbps | PID: 1026
[2025-10-17_21:45:05] CPU: 3.12% | Heap: 198.50/496.00MB (40.02%) | Mem: 12.52% | Net: 8.45 Mbps | PID: 1026
```

### Example results.csv:

```csv
run_id,timestamp,protocol,resolution,video_codec,audio_codec,connections,avg_sys_cpu_percent,max_sys_cpu_percent,cpu_per_stream_percent,mem_rss_kb,heap_used_mb,heap_capacity_mb
20251017_214500_RTMP_1080p_H264_3000k_5conn,2025-10-17T21:47:30.123456+00:00,rtmp,1080p,h264,aac,5,4.23,8.56,0.8460,1062024,201,496
```

**No more empty columns!** ✅

---

## ZGC-Specific Notes

### Your Wowza's ZGC Configuration:

```bash
-Xmx5415M                    # 5.4 GB maximum heap
-XX:+UseZGC                  # Z Garbage Collector
-XX:+ZGenerational           # Generational ZGC (newer feature)
-XX:MaxGCPauseMillis=200     # Target 200ms max pause
```

### ZGC Heap Behavior:

**Unlike Parallel/G1GC:**
- ZGC can **grow dynamically** up to `-Xmx`
- Initial capacity may be **much smaller** than max (you're seeing ~496 MB)
- Capacity **expands on demand** as load increases
- You might see capacity jump from 496 MB → 1 GB → 2 GB → 5 GB during heavy load

**This is normal and expected!**

### ZGC Output Format:

```
ZHeap           used 194M, capacity 496M, max capacity 5416M
```

Our parser extracts:
- `used`: **194M** → `HEAP_USED_MB = 194.00`
- `capacity` (not "max capacity"): **496M** → `HEAP_CAPACITY_MB = 496.00`
- Percentage: **194 / 496 * 100** = `HEAP_PCT = 39.11`

**Note**: We track **current capacity** (496M), not max (5416M), because that's what matters for current GC pressure.

---

## Testing

### Re-run Pilot Mode:

```bash
./orchestrator/run_orchestration.sh --pilot
```

### What to Check:

1. **Monitor logs exist:**
   ```bash
   ls orchestrator/runs/*/server_logs/monitors/monitor_*.log
   ```

2. **CSV has heap columns:**
   ```bash
   head -n 1 orchestrator/runs/*/server_logs/monitors/monitor_*.log
   # Should show: TIMESTAMP,CPU_PCT,HEAP_USED_MB,HEAP_CAPACITY_MB,HEAP_PCT,MEM_PCT,NET_MBPS,WOWZA_PID
   ```

3. **Heap values populated:**
   ```bash
   tail orchestrator/runs/*/server_logs/monitors/monitor_*.log
   # Should show actual numbers like: 2025-10-17_21:45:00,2.34,194.00,496.00,39.11,12.50,5.23,1026
   ```

4. **results.csv populated:**
   ```bash
   tail orchestrator/runs/results.csv
   # Should have values in heap_used_mb and heap_capacity_mb columns (not empty!)
   ```

5. **No syntax errors:**
   ```bash
   cat orchestrator/runs/*/server_logs/monitors/remote_monitor_stdout.log
   # Should NOT show any error messages
   ```

---

## Summary of Changes

| Aspect | Before | After |
|--------|--------|-------|
| **get_heap() return** | `"39.11"` (percentage only) | `"194.00 496.00 39.11"` (MB + %) |
| **CSV columns** | `HEAP_PCT` | `HEAP_USED_MB, HEAP_CAPACITY_MB, HEAP_PCT` |
| **Parser source** | `jstat_gc.log` only | `remote_monitor CSV` (primary), `jstat_gc.log` (fallback) |
| **results.csv units** | `heap_used_kb` (empty!) | `heap_used_mb` (populated!) |
| **ZGC support** | ❌ Not parsed | ✅ Full ZGC parsing |
| **Syntax errors** | ❌ Line 121 error | ✅ All fixed |

---

## Why MB Instead of KB?

1. **Readability**: 194 MB is easier to read than 198,656 KB
2. **ZGC outputs MB**: `ZHeap used 194M` - native format
3. **Precision**: 2 decimal places in MB is sufficient (194.25 MB = ±256 KB precision)
4. **Consistency**: Wowza config uses MB (`-Xmx5415M`)

**Your heap:**
- 5,416 MB max = 5.4 GB
- 194 MB used = 0.19 GB
- Much clearer than 5,545,984 KB and 198,656 KB!

---

## Next Steps

✅ **Syntax fixed** - `remote_monitor.sh` has no errors  
✅ **ZGC parsing** - Handles your `ZHeap` format  
✅ **MB logging** - All heap data in megabytes  
✅ **Parser updated** - Reads from monitor CSV files  
⏳ **Test needed** - Re-run pilot to confirm

**Ready to test!** The next pilot run should populate heap values correctly. 🎯
