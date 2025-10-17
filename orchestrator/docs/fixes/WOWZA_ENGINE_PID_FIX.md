# Fixed: Now Monitoring Correct Wowza Process

## Problem Identified

The scripts were monitoring the **Wowza Manager** process instead of the **Wowza Streaming Engine** process.

### Two Java Processes on Wowza Server:

1. **Wowza Manager** (PID 569)
   - Command: `launch.Main` (Tomcat-based web UI)
   - Small heap: ~87 MB
   - Not the streaming engine ❌
   
2. **Wowza Streaming Engine** (Different PID)
   - Command: `com.wowza.wms.bootstrap.Bootstrap start`
   - Larger heap: ~350 MB (or configured size)
   - **This is what we need to monitor** ✅

---

## What Was Fixed

### Updated PID Detection in All Scripts:

**Before** (Wrong - gets Manager):
```bash
ps aux | grep -E '[Ww]owza|WowzaStreamingEngine' | grep java | grep -v grep | head -n1
```

**After** (Correct - gets Engine):
```bash
ps aux | grep 'com.wowza.wms.bootstrap.Bootstrap start' | grep -v grep | head -n1
```

---

## Files Updated (4 scripts):

### 1. orchestrator/run_orchestration.sh
**Function**: `get_server_heap()`
- Line ~399: Updated Wowza PID detection
- Now targets streaming engine process

### 2. orchestrator/remote_monitor.sh
**Function**: `get_wowza_pid()`
- Line ~18: Updated PID detection
- Server-side monitoring now tracks correct process

### 3. orchestrator/diagnose_jcmd.sh
**Section**: "Finding Wowza process"
- Line ~21: Updated to find Bootstrap process
- Better error message explaining what it's looking for

### 4. orchestrator/validate_server.sh
**Section**: "Detecting Wowza process"
- Line ~50: Updated PID detection
- Now validates correct process

---

## Impact

### Before Fix:
- ❌ Monitored Manager (87 MB heap, 84% used)
- ❌ Small heap, not representative of streaming load
- ❌ Wrong process for capacity planning
- ❌ Adaptive stopping would trigger incorrectly

### After Fix:
- ✅ Monitors Streaming Engine (actual heap size)
- ✅ Real heap usage for streaming workload
- ✅ Correct process for load testing
- ✅ Adaptive stopping works correctly

---

## Testing

### Re-run Diagnostic:

```bash
./orchestrator/diagnose_jcmd.sh 54.67.101.210 ~/AlexC_Dev2_EC2.pem ubuntu
```

**Expected Output**:
```
1. Finding Wowza Engine process...
  ✓ Found Wowza:
    PID: [Different PID than 569]
    User: root
    Command: ...com.wowza.wms.bootstrap.Bootstrap start...

4. Testing jcmd with sudo...
  ✓ SUCCESS! sudo jcmd works

5. Testing AWK parsing...
  Total: [Much larger than 89088 KB]
  Used: [Actual streaming engine heap]
  Percentage: [Realistic percentage]
```

### What to Expect:

If Wowza Engine heap is configured properly (e.g., 2 GB):
```
Total: 2097152 KB (2 GB)
Used: 524288 KB (512 MB)
Percentage: 25.00%
```

Or if using default settings:
```
Total: ~524288 KB (512 MB)
Used: ~262144 KB (256 MB)  
Percentage: ~50%
```

---

## Verifying the Correct Process

### On the Wowza Server:

```bash
# SSH to server
ssh ubuntu@54.67.101.210

# List all Java processes
sudo jcmd

# Look for TWO processes:
# 569 - [Manager process - ignore]
# XXXX - com.wowza.wms.bootstrap.Bootstrap - [THIS IS THE ONE]

# Get heap info for correct process
sudo jcmd XXXX GC.heap_info
```

**Expected**: You should see the 350 MB heap you mentioned.

---

## Why This Matters

### Manager Process (Old Detection):
- Web UI only
- Minimal heap (87 MB)
- Not affected by streaming load
- Irrelevant for load testing

### Engine Process (New Detection):
- Actual streaming server
- Large heap (512 MB - 4 GB typical)
- Grows with active connections
- **THIS is what we test!**

### Load Testing Impact:

**Before**: Testing against Manager's 87 MB heap
- Would hit 80% immediately
- Not representative of streaming capacity
- Wrong adaptive stopping point

**After**: Testing against Engine's actual heap
- Real capacity measurement
- Correct adaptive stopping at 80%
- Accurate maximum connection count

---

## Heap Size Discovery

After running the diagnostic with the fix, you'll see the **actual heap size** configured for your Wowza Streaming Engine.

### Common Configurations:

| Config | Total Heap | Expected Use % |
|--------|-----------|----------------|
| Minimal | 512 MB | 40-60% idle |
| Standard | 1 GB - 2 GB | 20-40% idle |
| Production | 2 GB - 4 GB | 10-30% idle |
| High Load | 4 GB - 8 GB | 10-20% idle |

Your 350 MB total process memory suggests:
- Heap: ~256-512 MB
- Off-heap + metaspace: ~100-150 MB

The diagnostic will show exact numbers!

---

## Next Steps

1. **Re-run diagnostic** to see real Wowza Engine heap:
   ```bash
   ./orchestrator/diagnose_jcmd.sh 54.67.101.210 ~/AlexC_Dev2_EC2.pem ubuntu
   ```

2. **Check heap size** in output:
   - If < 1 GB: Consider increasing for load testing
   - If >= 1 GB: Ready to test!

3. **Run pilot mode**:
   ```bash
   ./orchestrator/run_orchestration.sh --pilot
   ```

4. **Verify logs** show realistic heap percentages

---

## If Heap Still Seems Small

If the diagnostic shows heap < 1 GB, increase it:

```bash
# SSH to server
ssh ubuntu@54.67.101.210

# Find setenv.sh
sudo find /usr/local/WowzaStreamingEngine -name "setenv.sh"

# Edit it
sudo nano /usr/local/WowzaStreamingEngine/bin/setenv.sh

# Change -Xmx to 2048m or higher
# Save and restart Wowza

sudo /usr/local/WowzaStreamingEngine/bin/restart.sh
```

---

## Summary

✅ **Fixed**: Now monitoring `com.wowza.wms.bootstrap.Bootstrap` (Streaming Engine)  
✅ **Updated**: 4 scripts with correct PID detection  
✅ **Validated**: All scripts pass syntax checks  
⏳ **Test**: Re-run diagnostic to see actual heap size  

**The monitoring will now show the correct streaming engine heap usage!**
