# Python Dependency Flow in Orchestrator

## Overview

The orchestrator now has **defense-in-depth** for Python3 dependency:
1. **Early check** (startup) - Proactive installation
2. **Runtime check** (per-test) - Safety fallback

---

## Flow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│ START: run_orchestration.sh                                 │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ [CHECKPOINT 1] Startup Dependency Check (Lines 44-91)      │
│                                                              │
│ if check_dependencies.sh fails:                             │
│   ├─> Offer to auto-install                                 │
│   ├─> Run install.sh --yes                                  │
│   ├─> Re-check dependencies                                 │
│   └─> Exit if still missing (or user continues)             │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ Collect user inputs (SSH key, server, app name, etc.)      │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ Run test sweep (for each protocol/resolution/bitrate/conn) │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ [CHECKPOINT 2] Per-Test Parsing (Lines 422-437)            │
│                                                              │
│ if python3 available:                                        │
│   └─> Parse results, generate CSV  ✅                       │
│ else:                                                        │
│   ├─> Log ERROR (shouldn't happen)                          │
│   ├─> Warn user                                             │
│   └─> Provide manual parsing instructions                   │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ Continue to next test or finish                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Why Two Checks?

### Checkpoint 1: Startup (Proactive)
**Location:** Lines 44-91  
**Purpose:** Ensure Python3 is installed before any tests run  
**Behavior:**
- Runs `check_dependencies.sh`
- If Python missing: Offers auto-install via `install.sh --yes`
- User can choose to continue without Python (not recommended)
- **Most users will never see Checkpoint 2 fail**

### Checkpoint 2: Runtime (Safety Net)
**Location:** Lines 422-437 (per-test parsing)  
**Purpose:** Graceful degradation if Python somehow unavailable  
**Behavior:**
- Checks Python3 availability before parsing each test
- If missing: Logs error, warns user, continues with raw logs
- **Should rarely/never trigger** due to Checkpoint 1

---

## Scenarios

### Scenario 1: Normal Flow (99% of cases)
```
1. User runs: ./run_orchestration.sh
2. Checkpoint 1: Python not found
3. System offers auto-install
4. User accepts (Y)
5. Python installs successfully
6. Tests run
7. Checkpoint 2: Python found ✅
8. Results parsed to CSV ✅
```

### Scenario 2: Python Already Installed
```
1. User runs: ./run_orchestration.sh
2. Checkpoint 1: Python found ✅
3. Tests run
4. Checkpoint 2: Python found ✅
5. Results parsed to CSV ✅
```

### Scenario 3: User Declines Installation
```
1. User runs: ./run_orchestration.sh
2. Checkpoint 1: Python not found
3. System offers auto-install
4. User declines (n)
5. System warns but continues
6. Tests run, logs collected
7. Checkpoint 2: Python not found ⚠️
8. Warning logged per test
9. Raw logs saved (no CSV)
```

### Scenario 4: Python Removed During Run (edge case)
```
1. Tests running with Python installed
2. External action removes Python (very rare)
3. Checkpoint 2: Python not found ⚠️
4. Error logged: "should have been caught at startup"
5. Warning issued
6. Remaining tests save raw logs only
```

---

## Updated Error Messages

### Before (Old - Confusing)
```
python3 not available locally; skipping parsing. Raw logs are in /path/to/run
```
**Problem:** 
- Doesn't explain why Python wasn't installed
- No guidance on what to do
- Sounds normal, not an error

### After (New - Clear)
```
ERROR: python3 not available - this should have been caught during startup dependency check
WARNING: python3 not available; skipping result parsing for 20251017_001234_RTMP_1080p_H264_3000k_5conn
Raw logs available in: /path/to/run
To parse manually later: python3 /path/to/parse_run.py --run-dir /path/to/run --run-id 20251017_001234_RTMP_1080p_H264_3000k_5conn ...
```
**Improvements:**
- ✅ Logs ERROR (easier to spot in logs)
- ✅ Explains this is unexpected
- ✅ Shows exact run_id affected
- ✅ Provides manual parsing command

---

## Manual Parsing

If Python wasn't available during a run, you can parse results retroactively:

```bash
# Parse a single run
python3 orchestrator/parse_run.py \
  --run-dir orchestrator/runs/20251017_001234_RTMP_1080p_H264_3000k_5conn \
  --run-id 20251017_001234_RTMP_1080p_H264_3000k_5conn \
  --protocol rtmp \
  --resolution 1080p \
  --video-codec h264 \
  --audio-codec aac \
  --bitrate 3000 \
  --connections 5

# Parse all unparsed runs in bulk
for run_dir in orchestrator/runs/*/; do
  if [[ ! -f "$run_dir/../results.csv" ]]; then
    echo "Parsing $(basename $run_dir)..."
    # Extract params from directory name and parse
  fi
done
```

---

## Code Locations

### Checkpoint 1: Startup Check
**File:** `orchestrator/run_orchestration.sh`  
**Lines:** 44-91

```bash
if [[ -f "$SCRIPTS_DIR/check_dependencies.sh" ]]; then
  log "Checking local dependencies (Bash, Python3, FFmpeg)..."
  if ! "$SCRIPTS_DIR/check_dependencies.sh" >/dev/null 2>&1; then
    # Offer auto-install
    read -p "Run automatic installation? (Y/n): " run_install
    if [[ ! "$run_install" =~ ^[Nn] ]]; then
      "$SCRIPTS_DIR/install.sh" --yes
    fi
  fi
fi
```

### Checkpoint 2: Runtime Check
**File:** `orchestrator/run_orchestration.sh`  
**Lines:** 422-437

```bash
if command -v python3 >/dev/null 2>&1; then
  # Parse with Python
else
  log "ERROR: python3 not available - this should have been caught during startup"
  # Warn and skip
fi
```

---

## Best Practices

### For Users
1. **Always accept auto-install** when prompted
2. Don't decline Python installation (unless you have a reason)
3. If you see Checkpoint 2 warnings, check why Python is missing

### For Developers
1. Keep both checkpoints - defense in depth
2. Checkpoint 1 is proactive (prevents problems)
3. Checkpoint 2 is reactive (handles edge cases)
4. Both improve user experience

---

## Summary

**Question:** "Will this skip parsing?"

**Answer:** **NO**, not under normal circumstances!

**Why:**
- Checkpoint 1 (startup) installs Python3 automatically
- User would have explicitly declined installation
- Checkpoint 2 is a safety net for edge cases
- Error message now makes it clear this is unexpected

**Normal Flow:**
```
Startup → Python Check → Auto-Install → Tests Run → Results Parsed ✅
```

**Edge Case Flow:**
```
Startup → Python Check → User Declines → Tests Run → Warning Per Test ⚠️
```

The updated error message makes it clear that if Checkpoint 2 triggers, something unexpected happened (or the user chose to skip installation).

**Your workflow is solid!** The auto-install at startup means users will rarely/never see parsing skipped. 🎉
