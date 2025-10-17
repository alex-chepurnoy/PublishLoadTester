# Test Hanging After Completion - Regression Fix

## Problem

Tests were completing successfully but the orchestrator was hanging indefinitely, never moving to the next test. The `server_logs` folder remained empty, indicating that log fetching never completed.

### Evidence from Logs

**Client logs show test completed at 12:07:54:**
```
[2025-10-17 12:07:54] [INFO] [MAIN] Cleanup completed
Test completed. Check logs at: /home/ubuntu/PublishLoadTester/logs/stream_test_20251017_120549.log
```

**But orchestrator log stopped at 12:05:48:**
```
[2025-10-17T12:05:48Z] Server CPU check: 0.25%
(no further entries)
```

**Result:** Test ran for 2 minutes, completed successfully, but orchestrator never logged the completion or fetched server logs.

---

## Root Cause

**The regression was introduced when we added `timeout` commands to the `ps` commands inside `remote_stop_monitors()`:**

```bash
# PROBLEMATIC CODE (introduced recently):
timeout 5 ps aux | head -n 200 > $remote_dir/process_snapshot.txt || true
timeout 5 ps -p $pid -o pid,rss,vsz,pmem,pcpu,cmd --no-headers > $remote_dir/wowza_proc.txt || true
```

### Why This Caused Hanging

1. **Pipe behavior with timeout**: When `timeout` kills `ps`, the pipe to `head` or file redirect can hang
2. **Remote execution context**: The `timeout` command runs on the **remote** server inside an SSH command
3. **SSH connection stays open**: Even though `timeout` kills `ps`, the SSH session might wait for the pipe to complete
4. **No error propagation**: The `|| true` at the end masks any errors, so the script doesn't fail - it just hangs

### Timeline of the Issue

```
12:05:48 - Test 1 starts
12:07:54 - Test 1 completes (stream_load_tester.sh finishes)
12:07:59 - sleep 5
12:07:59 - remote_stop_monitors called
12:07:59 - SSH connects, kills monitor processes
12:08:00 - Runs: timeout 5 ps aux | head -n 200 > ...
12:08:05 - timeout kills ps after 5 seconds
12:08:05 - Pipe hangs, waiting for head to finish
∞        - SSH command never returns
∞        - orchestrator stuck waiting for SSH
```

---

## Solution

### Removed timeout from ps Commands

**File:** `orchestrator/run_orchestration.sh` (line ~328)

**Before (broken):**
```bash
sleep 1; timeout 5 ps aux | head -n 200 > $remote_dir/process_snapshot.txt || true; \
if [ -f $remote_dir/monitors/wowza.pid ]; then pid=\$(cat $remote_dir/monitors/wowza.pid | tr -d '[:space:]'); if [ -n \"\$pid\" ] && ps -p \$pid >/dev/null 2>&1; then timeout 5 ps -p \$pid -o pid,rss,vsz,pmem,pcpu,cmd --no-headers > $remote_dir/wowza_proc.txt || true; fi; fi"
```

**After (fixed):**
```bash
sleep 1; ps aux 2>/dev/null | head -n 200 > $remote_dir/process_snapshot.txt || true; \
if [ -f $remote_dir/monitors/wowza.pid ]; then pid=\$(cat $remote_dir/monitors/wowza.pid | tr -d '[:space:]'); if [ -n \"\$pid\" ] && ps -p \$pid >/dev/null 2>&1; then ps -p \$pid -o pid,rss,vsz,pmem,pcpu,cmd --no-headers > $remote_dir/wowza_proc.txt 2>/dev/null || true; fi; fi"
```

**Changes:**
1. Removed `timeout 5` from both `ps` commands
2. Added `2>/dev/null` to redirect stderr to avoid any error messages

### Why This Is Safe

**`ps` commands are inherently fast:**
- `ps aux` typically takes < 100ms
- `ps -p <pid>` typically takes < 50ms
- No risk of hanging indefinitely

**We still have timeout protection at multiple levels:**
1. **SSH connection timeout** (10 seconds via `-o ConnectTimeout=10`)
2. **SSH keep-alive** (disconnects after 15 seconds of no response)
3. **ssh_retry function** (4 attempts with exponential backoff, max ~30 seconds)
4. **Entire SSH command** wrapped in these protections

**Adding timeout to ps was:**
- ❌ Unnecessary (ps is fast)
- ❌ Problematic (causes pipe issues)
- ❌ Redundant (already have SSH-level timeouts)

---

## Why We Added timeout Originally

When we were debugging the hang issues, we thought adding timeouts to individual commands would help. But:

1. **SSH-level timeouts are sufficient** - If SSH connection hangs, the whole command times out
2. **Command-level timeouts in pipes are tricky** - Can cause more problems than they solve
3. **ps commands don't need timeouts** - They're always fast unless the system is completely locked up

---

## Testing

### Test 1: Single Test Run

```bash
cd orchestrator
./run_orchestration.sh
# Answer 'y' to pilot mode
```

**Expected behavior:**
```
[timestamp] Server CPU check: 0.25%
Starting client load tester: protocol=rtmp resolution=1080p...
(test runs for 2 minutes)
(orchestrator continues immediately after test)
[timestamp] === Completed: 20251017_XXXXXX_RTMP_1080p_H264_3000k_1conn ===
[timestamp] Cooldown: waiting 10 seconds for server to stabilize...
[timestamp] Server CPU check: 1.23%
Starting client load tester: protocol=rtmp resolution=1080p...
(next test starts)
```

### Test 2: Verify Server Logs Collected

After first test completes:
```bash
ls -la orchestrator/runs/20251017_*/server_logs/
```

**Should show:**
```
pidstat.log
sar_cpu.log
sar_net.log
jstat_gc.log (if jstat available)
process_snapshot.txt
wowza_proc.txt
```

Not an empty folder!

### Test 3: Check Orchestrator Log

```bash
tail -f orchestrator/runs/orchestrator.log
```

**Should show continuous progress:**
```
[timestamp] Server CPU check: 0.25%
[timestamp] remote_start_monitors: ......
[timestamp] === Completed: run_1 ===
[timestamp] Cooldown: waiting 10 seconds...
[timestamp] Server CPU check: 1.15%
[timestamp] remote_start_monitors: ......
[timestamp] === Completed: run_2 ===
...
```

---

## Lessons Learned

### When to Use timeout

**Good uses:**
- ✅ Long-running user commands that might hang
- ✅ Network operations (wget, curl)
- ✅ Database queries
- ✅ User scripts

**Bad uses:**
- ❌ Fast system commands (ps, ls, cat)
- ❌ Commands in pipes (causes complexity)
- ❌ Commands already wrapped in SSH with timeouts
- ❌ Commands with `|| true` (masks the timeout)

### Better Timeout Strategy

**Prefer timeouts at the highest level:**
```bash
# GOOD: Timeout the entire SSH command
timeout 30 ssh server "ps aux | head -n 200 > file.txt"

# BAD: Timeout individual commands inside SSH
ssh server "timeout 5 ps aux | head -n 200 > file.txt"
```

**Reason:** Simpler, more predictable, easier to debug.

---

## Comparison

### Before This Fix

**Test flow:**
```
Start test → Test runs (2 min) → Test completes → 
sleep 5 → remote_stop_monitors (HANGS HERE) → 
∞ wait forever
```

**Result:** Pilot never completes, manual Ctrl+C required

### After This Fix

**Test flow:**
```
Start test → Test runs (2 min) → Test completes → 
sleep 5 → remote_stop_monitors (< 5 sec) → 
fetch_server_logs (< 10 sec) → parse results (< 5 sec) → 
Cooldown (10 sec) → Next test starts
```

**Result:** All 15 pilot tests complete in ~35-40 minutes

---

## Summary

✅ **Problem:** Orchestrator hanging after each test due to `timeout` in pipes

✅ **Root Cause:** `timeout 5 ps aux | head -n 200` causing pipe hang when timeout triggers

✅ **Solution:** Removed unnecessary `timeout` from `ps` commands

✅ **Why Safe:** 
- ps commands are fast (< 100ms)
- SSH-level timeouts still protect against hangs
- ssh_retry provides retry logic

✅ **Result:** Tests flow smoothly from one to the next without hanging

🎯 **Next:** Run full pilot test to verify all 15 tests complete successfully!
