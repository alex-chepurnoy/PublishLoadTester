# Wowza Java Tools Path Fix

**Issue:** Java heap monitoring tools (jcmd, jstat, jmap) not found in PATH  
**Root Cause:** Tools are installed with Wowza but located in `/usr/local/WowzaStreamingEngine/java/bin`  
**Resolution:** Updated all monitoring code to check both PATH and Wowza's java/bin directory  
**Date:** October 17, 2025

---

## Problem

During validation, the Java heap monitoring tools were reported as missing:

```
2. Checking Java heap monitoring tools...
  ✗ jcmd MISSING
  ✗ jstat MISSING
  ✗ jmap MISSING
```

However, these tools are actually installed with Wowza in:
```
/usr/local/WowzaStreamingEngine/java/bin
```

## Solution

Updated all scripts to check **both** locations:
1. First check if tool is in PATH (`command -v`)
2. If not in PATH, check Wowza's java/bin directory
3. Use whichever is found

### Files Modified

#### 1. `orchestrator/run_orchestration.sh`

**Updated `get_server_heap()` function:**
- Added `java_bin` variable pointing to Wowza's Java bin
- Updated jcmd call to check both locations:
  ```bash
  { command -v jcmd >/dev/null 2>&1 && jcmd $pid ...; } || \
  { [ -x $java_bin/jcmd ] && $java_bin/jcmd $pid ...; }
  ```
- Applied same pattern to jstat and jmap calls

**Lines Modified:** ~390-440

#### 2. `orchestrator/remote_monitor.sh`

**Updated `get_heap()` function:**
- Added `java_bin` variable
- Changed from simple `jcmd` call to conditional check:
  ```bash
  if command -v jcmd >/dev/null 2>&1; then
    heap=$(jcmd $pid ...)
  elif [ -x "$java_bin/jcmd" ]; then
    heap=$($java_bin/jcmd $pid ...)
  fi
  ```
- Applied same pattern to jstat fallback

**Lines Modified:** ~40-75

#### 3. `orchestrator/validate_server.sh`

**Section 2 - Tool Detection:**
- Updated to show location when found:
  ```bash
  ✓ jcmd (in PATH)           # or
  ✓ jcmd (in /usr/local/.../java/bin)
  ```

**Section 6 - Heap Monitoring Tests:**
- Updated all test commands to check both locations
- Now uses same pattern as runtime code

**Lines Modified:** ~30-35, ~60-70

---

## Verification

After fix, validation should show:

```
2. Checking Java heap monitoring tools...
  ✓ jcmd (in /usr/local/WowzaStreamingEngine/java/bin)
  ✓ jstat (in /usr/local/WowzaStreamingEngine/java/bin)
  ✓ jmap (in /usr/local/WowzaStreamingEngine/java/bin)

6. Testing Java heap monitoring (if Wowza found)...
  Testing jcmd GC.heap_info...
  [heap info output]
  ✓ jcmd works
  
  Testing jstat -gc...
  [gc stats output]
  ✓ jstat works
  
  Testing jmap -heap (brief check only)...
  [heap summary output]
  ✓ jmap works (emergency fallback available)
```

---

## Testing Commands

### Re-run Validation
```bash
./orchestrator/validate_server.sh ~/key.pem ubuntu@54.67.101.210
```

### Test Heap Monitoring Manually
```bash
# SSH to server
ssh -i ~/key.pem ubuntu@54.67.101.210

# Get Wowza PID
WOWZA_PID=$(ps aux | grep -i wowza | grep java | grep -v grep | awk '{print $2}')

# Test jcmd with full path
/usr/local/WowzaStreamingEngine/java/bin/jcmd $WOWZA_PID GC.heap_info

# Test jstat with full path
/usr/local/WowzaStreamingEngine/java/bin/jstat -gc $WOWZA_PID
```

### Test from Orchestrator
```bash
# Source the script
source orchestrator/run_orchestration.sh

# Set variables
export KEY_PATH="~/key.pem"
export SSH_USER="ubuntu"
export SERVER_IP="54.67.101.210"
export SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

# Test heap function
get_server_heap
# Expected: A percentage like 45.67 (not 0.00)

# Test unified status
check_server_status
# Expected: CPU|HEAP|MEM|NET like "23.45|45.67|58.90|125.34"
```

---

## Technical Details

### Command Pattern

**Before (broken):**
```bash
jcmd $pid GC.heap_info
```

**After (works):**
```bash
{ command -v jcmd >/dev/null 2>&1 && jcmd $pid GC.heap_info; } || \
{ [ -x /usr/local/WowzaStreamingEngine/java/bin/jcmd ] && \
  /usr/local/WowzaStreamingEngine/java/bin/jcmd $pid GC.heap_info; }
```

### Why Not Add to PATH?

We **could** add Wowza's java/bin to PATH, but:
1. Requires modifying server configuration
2. May conflict with system Java installation
3. This approach works without any server changes
4. More portable across different Wowza installations

---

## Impact

**No Breaking Changes:**
- If tools are in PATH, uses PATH (works as before)
- If tools are in Wowza's bin, uses that (new capability)
- If tools missing entirely, falls back gracefully (0.00)

**Performance:**
- Negligible overhead (one extra directory check)
- Fallback only triggers if PATH check fails

**Compatibility:**
- Works with standard JDK installations (tools in PATH)
- Works with Wowza bundled JDK (tools in Wowza's bin)
- Works with both configurations simultaneously

---

## Alternative Solutions Considered

### 1. Add to PATH (Rejected)
```bash
export PATH="/usr/local/WowzaStreamingEngine/java/bin:$PATH"
```
**Pros:** Simpler code  
**Cons:** Requires server modification, potential conflicts

### 2. Symlinks (Rejected)
```bash
ln -s /usr/local/WowzaStreamingEngine/java/bin/jcmd /usr/local/bin/jcmd
```
**Pros:** Works system-wide  
**Cons:** Requires root access, may conflict with system Java

### 3. Runtime PATH Modification (Rejected)
```bash
PATH="/usr/local/WowzaStreamingEngine/java/bin:$PATH" jcmd ...
```
**Pros:** No permanent changes  
**Cons:** Verbose, harder to read

### 4. Dual Location Check (CHOSEN) ✅
**Pros:** 
- No server changes required
- Works with any configuration
- Graceful fallback
- Maintains code readability

**Cons:**
- Slightly more complex code
- Need to update multiple places

---

## Status

✅ **COMPLETE** - All scripts updated and syntax-validated

**Next Step:** Re-run validation script to confirm Java tools are now detected

---

*Fix applied: October 17, 2025*  
*Scripts updated: 3*  
*Functions updated: 2*  
*Syntax errors: 0*
