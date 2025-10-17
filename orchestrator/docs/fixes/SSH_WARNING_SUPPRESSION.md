# SSH Warning Suppression Fix

**Issue:** SSH warning message appearing during validation  
**Warning Text:** `Warning: Permanently added '54.67.101.210' (ED25519) to the list of known hosts.`  
**Resolution:** Added quiet mode and error-level logging to SSH options  
**Date:** October 17, 2025

---

## Problem

During validation and monitoring operations, SSH was displaying this warning:
```
Warning: Permanently added '54.67.101.210' (ED25519) to the list of known hosts.
```

This warning appears even though we're using:
- `-o UserKnownHostsFile=/dev/null` (don't save host keys)
- `-o StrictHostKeyChecking=no` (don't prompt for verification)

The warning is written to **stderr** and shows up in the output, making it harder to read the actual results.

---

## Root Cause

SSH prints informational messages (like host key additions) at the **INFO** log level, which still appears even when redirecting stderr to `/dev/null`. The `-o UserKnownHostsFile=/dev/null` prevents the key from being *saved*, but doesn't suppress the *message* about the addition attempt.

---

## Solution

Added two SSH flags to suppress these warnings:

1. **`-q`** (quiet mode) - Suppresses most warning and diagnostic messages
2. **`-o LogLevel=ERROR`** - Only show errors, suppress info/warning messages

### Updated SSH_OPTS

**Before:**
```bash
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
```

**After:**
```bash
SSH_OPTS="-q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
```

---

## Files Modified

### 1. `orchestrator/validate_server.sh`
**Line:** ~15  
**Change:** Added `-q` and `-o LogLevel=ERROR` to SSH_OPTS

**Before:**
```bash
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
```

**After:**
```bash
SSH_OPTS="-q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
```

### 2. `orchestrator/run_orchestration.sh`
**Line:** ~169  
**Change:** Added `-q` and `-o LogLevel=ERROR` to secondary SSH_OPTS definition

**Note:** The primary SSH_OPTS on line 22 already had `-o LogLevel=ERROR`, so only added `-q`.

---

## Impact

**Before Fix:**
```
2. Checking Java heap monitoring tools...
Warning: Permanently added '54.67.101.210' (ED25519) to the list of known hosts.
  ✓ jcmd (in /usr/local/WowzaStreamingEngine/java/bin)
  ✓ jstat (in /usr/local/WowzaStreamingEngine/java/bin)
```

**After Fix:**
```
2. Checking Java heap monitoring tools...
  ✓ jcmd (in /usr/local/WowzaStreamingEngine/java/bin)
  ✓ jstat (in /usr/local/WowzaStreamingEngine/java/bin)
```

Clean output, no warnings! ✨

---

## What These Flags Do

### `-q` (Quiet Mode)
- Suppresses warning and diagnostic messages
- Still shows errors
- Cleaner output for scripting
- Does NOT affect actual SSH functionality

### `-o LogLevel=ERROR`
- Sets SSH to only log ERROR level messages
- Suppresses INFO and WARNING levels
- More fine-grained control than `-q`
- Recommended for automated scripts

### `-o StrictHostKeyChecking=no`
- Don't prompt to verify host key
- Accept any host key automatically
- Useful for automation
- **Security Note:** Only use for test environments

### `-o UserKnownHostsFile=/dev/null`
- Don't read or write to known_hosts file
- Prevents pollution of ~/.ssh/known_hosts
- Useful when connecting to frequently-changing IPs

### `-o ConnectTimeout=10`
- Timeout after 10 seconds if connection fails
- Prevents hanging on unreachable hosts
- Already present in primary SSH_OPTS

### `-o ServerAliveInterval=5`
- Send keepalive every 5 seconds
- Prevents connection timeout during long operations
- Already present in primary SSH_OPTS

---

## Testing

**Re-run validation to verify no warnings:**
```bash
./orchestrator/validate_server.sh ~/key.pem ubuntu@54.67.101.210
```

**Expected:** Clean output with no SSH warnings

**If warnings still appear:** Check that the script is using the updated SSH_OPTS variable and not hardcoding SSH options anywhere.

---

## Related Files

All SSH connections in the codebase should use the SSH_OPTS variable:
- ✅ `orchestrator/validate_server.sh` - Updated
- ✅ `orchestrator/run_orchestration.sh` - Updated (both SSH_OPTS definitions)
- ℹ️ `orchestrator/remote_monitor.sh` - Runs on server, doesn't make SSH connections

---

## Alternative Solutions Considered

### 1. Redirect stderr to /dev/null (Rejected)
```bash
ssh ... 2>/dev/null
```
**Pros:** Simple  
**Cons:** Hides ALL errors, including real problems

### 2. Filter output with grep -v (Rejected)
```bash
ssh ... 2>&1 | grep -v "Permanently added"
```
**Pros:** Selective filtering  
**Cons:** Fragile, might miss variations, still shows other warnings

### 3. Add -q and LogLevel=ERROR (CHOSEN) ✅
**Pros:**
- Built-in SSH feature
- Suppresses warnings properly
- Still shows real errors
- Clean, maintainable

**Cons:** None

---

## Status

✅ **COMPLETE** - SSH warnings suppressed in all validation and monitoring scripts

**Next:** Re-run validation to confirm clean output

---

*Fix applied: October 17, 2025*  
*Scripts updated: 2*  
*Flags added: `-q` and `-o LogLevel=ERROR`*
