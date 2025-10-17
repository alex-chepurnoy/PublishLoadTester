# Orchestrator Bug Fixes - October 17, 2025

## Issues Resolved

### 1. Script Terminating After First Test ✅
**Problem**: The orchestrator was exiting immediately after the first test completed, before parsing results or moving to the next test. A "Terminated" message appeared and the script returned to the shell prompt.

**Root Cause**: The script uses `set -o pipefail` which causes any command in a pipe to fail if any part of the pipe fails. When the stream_load_tester.sh killed the FFmpeg process, it caused a SIGPIPE error in the `tee` command, which made the entire pipeline fail and triggered `set -e` to exit the script immediately.

**Fix**: Added `|| true` to the end of the tee pipeline in `run_orchestration.sh` line 423:
```bash
"$STREAM_TOOL" \
  --yes \
  --protocol "$protocol" \
  ... \
    2>&1 | tee "$local_run_dir/client_logs/stream_load_tester.log" || true
```

**Result**: The script now continues after the "Terminated" message (which is normal when FFmpeg is killed) and proceeds through:
- Stopping remote monitors
- Fetching server logs
- Parsing results
- Moving to the next test

---

### 2. False "Unable to get server CPU" Warning ✅
**Problem**: The script logged "WARNING: Unable to get server CPU, continuing anyway..." even when the server had low CPU usage (0.00%), which is a valid reading.

**Root Cause**: The CPU check logic at line 492 was treating "0.00" as a failure:
```bash
if [[ -z "$cpu" ]] || [[ "$cpu" == "0.00" ]]; then
```

This caused false warnings when the server was idle between tests (which is expected behavior).

**Fix**: Removed the `|| [[ "$cpu" == "0.00" ]]` check:
```bash
if [[ -z "$cpu" ]]; then
```

Now the script only warns if the CPU value is truly empty, not when it's a valid "0.00".

**Result**: No more false warnings. The script correctly reports low CPU values like:
```
[2025-10-17T12:52:53Z] Server CPU check: 0.00%
[2025-10-17T12:52:53Z] Server CPU check: 1.25%
```

---

## Current Status

### Working Features ✅
- First test completes successfully
- Server logs are fetched properly
- Results are parsed and written to CSV
- Script moves to second test automatically
- CPU checks work correctly (no false warnings)
- 10-second cooldown between tests
- Parser with Wowza PID detection
- Proper error handling and logging

### Expected Behavior
1. Test runs for 2 minutes
2. FFmpeg cleanup shows "Terminated" (normal)
3. Sleep 5 seconds
4. Stop remote monitors
5. Fetch server logs
6. Parse results → `results.csv` created
7. Complete message logged
8. 10-second cooldown
9. CPU check (reports actual value, no false warnings)
10. Move to next test

---

## Testing Notes

The "Terminated" message that appears after FFmpeg cleanup is **normal and expected**. This is the shell reporting that a process received SIGTERM when we kill FFmpeg. This is not an error.

The script should now run all 15 pilot tests successfully without premature termination.

---

## Files Modified
- `orchestrator/run_orchestration.sh`
  - Line 423: Added `|| true` to tee pipeline
  - Line 492: Removed false "0.00" CPU check
