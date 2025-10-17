# Orchestrator Bug Fixes

## Date: October 17, 2025

## Issues Found and Fixed

### 1. **Interactive Prompt Blocking Automation** (CRITICAL - FIXED)
**Problem:** The orchestrator was hanging because `stream_load_tester.sh` prompted for user confirmation:
```
Start the test? (y/N):
```

**Root Cause:** The script checked for `FORCE` variable but had no command-line flag to set it.

**Solution:**
- Added `--yes`, `--force`, and `-y` flags to `stream_load_tester.sh` argument parser
- Updated orchestrator to pass `--yes` flag when invoking the load tester
- Added logic to skip configuration save prompts in non-interactive mode
- Updated help documentation

**Files Changed:**
- `stream_load_tester.sh`: Added argument parsing for `--yes` flag
- `orchestrator/run_orchestration.sh`: Added `--yes` flag to load tester invocation (line 305)

---

### 2. **Process ID Syntax Error** (HIGH - FIXED)
**Problem:** SSH command failed with:
```
error: process ID list syntax error
```

**Root Cause:** In `remote_stop_monitors()`, the code attempted to run `ps -p $pid` without checking if `$pid` was empty or valid.

**Solution:** Added validation check:
```bash
if [ -n "\$pid" ] && ps -p \$pid >/dev/null 2>&1; then
```

**Files Changed:**
- `orchestrator/run_orchestration.sh`: Line 267 in `remote_stop_monitors()` function

---

### 3. **Deprecated datetime.utcnow()** (LOW - FIXED)
**Problem:** Warning displayed:
```
DeprecationWarning: datetime.datetime.utcnow() is deprecated and scheduled for removal 
in a future version. Use timezone-aware objects to represent datetimes in UTC: 
datetime.datetime.now(datetime.UTC).
```

**Root Cause:** Using deprecated `datetime.utcnow()` instead of timezone-aware alternative.

**Solution:**
- Updated import: `from datetime import datetime, timezone`
- Changed: `datetime.utcnow().isoformat()` → `datetime.now(timezone.utc).isoformat()`

**Files Changed:**
- `orchestrator/parse_run.py`: Lines 16 and 159

---

## Testing Recommendations

1. **Test Non-Interactive Mode:**
   ```bash
   ./stream_load_tester.sh --yes --protocol rtmp --resolution 1080p \
     --video-codec h264 --audio-codec aac --bitrate 3000 \
     --url rtmp://54.67.101.210:1935/live --connections 1 \
     --stream-name test --duration 1
   ```

2. **Test Orchestrator:**
   ```bash
   ./orchestrator/run_orchestration.sh
   ```
   - Should now run without hanging on prompts
   - Should handle empty Wowza PIDs gracefully
   - Should not show datetime deprecation warnings

3. **Verify Outputs:**
   - Check `orchestrator/runs/` for completed run directories
   - Verify `results.csv` is generated without warnings
   - Confirm server logs are fetched successfully

---

## Additional Improvements Made

1. **Help Documentation:** Updated `--help` output to include the new `--yes` flag
2. **Code Safety:** Added PID validation to prevent malformed `ps` commands
3. **Python 3.12+ Compatibility:** Fixed deprecated datetime usage for future Python versions

---

## Known Remaining Issues

None identified. The orchestrator should now run fully automated sweeps without manual intervention.
