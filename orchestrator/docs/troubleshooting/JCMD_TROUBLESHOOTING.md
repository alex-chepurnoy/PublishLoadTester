# jcmd Troubleshooting Guide

## Problem: jcmd Not Working

The `jcmd` command is failing to return heap data. Here are the likely causes and fixes:

---

## Issue 1: Wrong AWK Parsing Pattern (FIXED)

**Problem**: The AWK script was looking for lines like:
```
capacity = 123456
used = 78900
```

But `jcmd GC.heap_info` actually outputs:
```
PSYoungGen      total 76288K, used 45123K
ParOldGen       total 174592K, used 98234K
```

**Fix Applied**: Updated AWK parsing in:
- ✅ `orchestrator/run_orchestration.sh` (get_server_heap function)
- ✅ `orchestrator/remote_monitor.sh` (get_heap function)

**New parsing logic**:
```bash
awk '
  /PSYoungGen|ParOldGen|PSOldGen/ {
    if ($0 ~ /total [0-9]+K/) {
      for(i=1; i<=NF; i++) {
        if ($i == "total" && $(i+1) ~ /^[0-9]+K/) {
          gsub(/K/, "", $(i+1))
          total_kb += $(i+1)
        }
        if ($i == "used" && $(i+1) ~ /^[0-9]+K/) {
          gsub(/K/, "", $(i+1))
          used_kb += $(i+1)
        }
      }
    }
  }
  END { if(total_kb>0) printf "%.2f", (used_kb/total_kb)*100; else print "0.00" }
'
```

---

## Issue 2: Permission Denied (FIXED WITH SUDO)

**Problem**: `jcmd` requires running as the **same user** that started the Java process.

If Wowza runs as user `wowza` or `root`, but you SSH as `ubuntu`, jcmd will fail:
```
Error: Unable to open socket file: target process not responding or HotSpot VM not loaded
```

**Fix Applied**: Scripts now automatically try with `sudo` if permission denied.

**Server Setup Required**: Configure passwordless sudo on your server:

### Quick Setup (2 minutes):

```bash
# 1. Copy setup script to server
scp -i your-key.pem setup_sudo.sh ubuntu@your-server-ip:~/

# 2. SSH to server and run
ssh -i your-key.pem ubuntu@your-server-ip
chmod +x setup_sudo.sh
./setup_sudo.sh ubuntu
```

This creates `/etc/sudoers.d/java-monitoring` allowing passwordless sudo for jcmd/jstat/jmap.

**See SUDO_SETUP_GUIDE.md for detailed instructions and security considerations.**

**How to Check**:
```bash
# Run the diagnostic script
./orchestrator/diagnose_jcmd.sh <server-ip> <ssh-key> <ssh-user>
```

**Solutions**:

1. **Option A**: SSH as the Wowza user
   ```bash
   # If Wowza runs as 'wowza' user
   ssh -i key.pem wowza@server-ip
   ```

2. **Option B**: Use sudo with jcmd (update scripts)
   ```bash
   sudo -u wowza jcmd <PID> GC.heap_info
   ```

3. **Option C**: Run jstat instead (already implemented as fallback)
   - jstat works across users
   - Already in place as Fallback #1

---

## Issue 3: stderr Redirection Hiding Errors

**Problem**: The original code had `2>/dev/null` which hides error messages.

**Fix Applied**: Changed to `2>&1` to capture errors for diagnosis.

---

## Testing Your Fix

### Step 1: Run Diagnostic Script
```bash
./orchestrator/diagnose_jcmd.sh <your-server-ip> <your-key.pem> ubuntu
```

This will:
- ✅ Find Wowza process and PID
- ✅ Check which user runs Wowza
- ✅ Test jcmd access
- ✅ Show actual output
- ✅ Test AWK parsing
- ✅ Identify permission issues

### Step 2: Run Validation Script
```bash
./orchestrator/validate_server.sh
```

Expected output:
```
6. Testing Java heap monitoring...
  Testing jcmd GC.heap_info...
  ✓ jcmd works
  PSYoungGen      total 76288K, used 45123K [0x00000000ec000000, ...]
  ...
```

### Step 3: Test Pilot Mode
```bash
./orchestrator/run_orchestration.sh --pilot
```

Should now see clean heap percentages:
```
[2025-10-17...] Server Status - CPU: 45.2%, Heap: 32.5%, Memory: 48.3%, Network: 0.5 Mbps
```

---

## What Changed

### Files Modified:

1. **orchestrator/run_orchestration.sh**
   - Fixed `get_server_heap()` AWK parsing
   - Changed stderr handling from `2>/dev/null` to `2>&1`

2. **orchestrator/remote_monitor.sh**
   - Fixed `get_heap()` AWK parsing
   - Changed stderr handling from `2>/dev/null` to `2>&1`

3. **orchestrator/validate_server.sh**
   - Enhanced to show actual jcmd output
   - Better error diagnosis
   - Captures and displays stderr

4. **orchestrator/diagnose_jcmd.sh** (NEW)
   - Complete diagnostic tool
   - Tests permissions
   - Tests parsing
   - Shows solutions

---

## Fallback Chain

The system has a 3-level fallback:

1. **jcmd** (Primary - fastest, most accurate)
   - Now fixed with correct parsing
   - Requires same user as Wowza

2. **jstat** (Fallback #1 - reliable)
   - Works across users
   - Already working

3. **jmap** (Fallback #2 - emergency only)
   - Causes JVM pause
   - Only used if both above fail

---

## Next Steps

1. **Run diagnostic script** to identify the exact issue:
   ```bash
   ./orchestrator/diagnose_jcmd.sh <server-ip> <key> <user>
   ```

2. **If permission denied**:
   - Either SSH as Wowza user
   - Or rely on jstat fallback (already works)

3. **Test with pilot mode**:
   ```bash
   ./orchestrator/run_orchestration.sh --pilot
   ```

---

## Common jcmd Errors

| Error Message | Cause | Solution |
|--------------|-------|----------|
| `Unable to open socket file` | Permission denied | SSH as Wowza user or use jstat |
| `<PID> does not exist` | Wrong PID | Check Wowza is running |
| `<PID> not responding` | Process hung | Restart Wowza |
| No output but exit code 0 | AWK parsing failed | Now fixed! |
| `command not found` | jcmd not installed | Install openjdk-11-jdk-headless |

---

**Status**: Issues 1 and 3 are FIXED. Issue 2 (permissions) needs testing on your server.

**Next**: Run `./orchestrator/diagnose_jcmd.sh` to see which issue you're hitting.
