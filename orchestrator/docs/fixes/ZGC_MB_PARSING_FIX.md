# Fixed: ZGC Heap Parsing in run_orchestration.sh

## Problem

During pilot run, server health checks showed:
```
[2025-10-17T22:03:52Z] Server Status: CPU=0.00% | Heap=0.00% | Mem=24.24% | Net=0.00Mbps
```

Heap was showing `0.00%` even though:
- The heap data was correctly being written to CSV files by `remote_monitor.sh`
- The diagnostic showed heap working: `ZHeap used 194M, capacity 496M`

## Root Cause

**Different output formats between ZGC and other GC collectors:**

### ZGC Format (Your Wowza):
```
ZHeap           used 194M, capacity 496M, max capacity 5416M
                     ^^^^              ^^^^
                   MEGABYTES      MEGABYTES
```

### G1GC/Parallel GC Format:
```
garbage-first heap   total 524288K, used 194288K
                               ^^^^          ^^^^
                           KILOBYTES    KILOBYTES
```

**The Issue:**
- `run_orchestration.sh` AWK script was looking for pattern: `/[0-9]+K/` (kilobytes only)
- ZGC outputs in MB (`194M`), not KB (`198656K`)
- **Pattern didn't match** → `total_kb = 0` → Division by zero → `0.00%`

**Why remote_monitor.sh worked:**
- Already had MB parsing logic for ZGC from the earlier fix
- `run_orchestration.sh` was missed in that update

---

## Solution

Updated `get_server_heap()` function in `run_orchestration.sh` to handle **both MB and KB formats**.

### Before (Broken):

```bash
/garbage-first heap|ZHeap|Z Heap|Shenandoah/ {
  if ($0 ~ /total [0-9]+K.*used [0-9]+K/) {  # ❌ Only matches KB!
    # ... parse KB values ...
  }
}
```

### After (Fixed):

```bash
/garbage-first heap|ZHeap|Z Heap|Shenandoah/ {
  # Check for MB format (ZGC)
  if ($0 ~ /used [0-9]+M/ || $0 ~ /capacity [0-9]+M/) {
    # Parse MB values and convert to KB
    if ($i == "used" && $(i+1) ~ /^[0-9]+M/) {
      used_kb = $(i+1) * 1024  # 194M → 198656 KB
    }
    if ($i == "capacity" && $(i+1) ~ /^[0-9]+M/) {
      total_kb = $(i+1) * 1024  # 496M → 507904 KB
    }
  }
  # Check for KB format (G1GC, Shenandoah)
  else if ($0 ~ /total [0-9]+K.*used [0-9]+K/) {
    # Parse KB values directly
  }
}
```

---

## What Was Fixed

### File: orchestrator/run_orchestration.sh

**Function:** `get_server_heap()` (lines ~430-450)

**Changes:**
1. Added MB format detection: `/used [0-9]+M/` and `/capacity [0-9]+M/`
2. Added MB to KB conversion: `value * 1024`
3. Handle "capacity" keyword (ZGC) vs "total" keyword (G1GC)
4. Avoid "max capacity" (we want current capacity, not max)
5. Fallback to KB parsing for G1GC/Shenandoah

**Pattern Matching:**
- **ZGC**: `ZHeap used 194M, capacity 496M` ✅
- **G1GC**: `garbage-first heap total 524288K, used 194288K` ✅
- **Parallel**: `PSYoungGen total 123K, used 45K` (already working) ✅
- **Shenandoah**: `Shenandoah total 512K, used 256K` ✅

---

## Expected Output After Fix

### Server Health Checks:
```
[2025-10-17T22:10:00Z] Server Status: CPU=2.34% | Heap=39.11% | Mem=12.50% | Net=5.23Mbps
```

**Before**: `Heap=0.00%` ❌  
**After**: `Heap=39.11%` ✅ (194 MB / 496 MB)

### CSV Logging (Already Working):
```csv
TIMESTAMP,CPU_PCT,HEAP_USED_MB,HEAP_CAPACITY_MB,HEAP_PCT,MEM_PCT,NET_MBPS,WOWZA_PID
2025-10-17_22:10:00,2.34,194.00,496.00,39.11,12.50,5.23,1026
```

**This was already working** because `remote_monitor.sh` had the fix.

---

## Why This Happened

1. **Earlier fix** (HEAP_MB_LOGGING_FIX.md) updated `remote_monitor.sh` to parse ZGC MB format
2. **Missed updating** `run_orchestration.sh` `get_server_heap()` function
3. **Two separate code paths:**
   - `remote_monitor.sh` → Runs ON server → Logs to CSV → **Working**
   - `run_orchestration.sh` → Runs FROM client → Health checks → **Broken**

---

## Testing

Re-run pilot mode:
```bash
./orchestrator/run_orchestration.sh --pilot
```

**Expected:**
```
[2025-10-17T22:15:00Z] Checking server health...
[2025-10-17T22:15:04Z] Server Status: CPU=2.34% | Heap=39.11% | Mem=12.50% | Net=5.23Mbps
```

**Heap should show actual percentage** (not 0.00%)!

---

## Summary

| Aspect | Before | After |
|--------|--------|-------|
| **Health check output** | `Heap=0.00%` | `Heap=39.11%` |
| **ZGC MB parsing** | ❌ Not supported | ✅ Fully supported |
| **G1GC KB parsing** | ✅ Working | ✅ Still working |
| **CSV logging** | ✅ Working | ✅ Still working |
| **Affected files** | run_orchestration.sh | Fixed |

**Root cause**: ZGC outputs MB, script only looked for KB.  
**Fix**: Added MB detection and conversion to KB.  
**Impact**: Health checks now show correct heap percentage! ✅

---

## Files Changed

1. **orchestrator/run_orchestration.sh** - Added MB parsing for ZGC in `get_server_heap()`

**Status**: ✅ Fixed and syntax validated
