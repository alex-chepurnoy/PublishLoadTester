# Script Permissions Management

## Question: Does install.sh chmod +x all .sh files?

### Answer: NOW YES! ✅ (Updated)

---

## Previous Behavior (❌ Incomplete)

**Before the update**, `install.sh` only made **specific scripts** executable:

```bash
chmod +x "$PROJECT_ROOT/stream_load_tester.sh"
chmod +x "$SCRIPT_DIR/check_dependencies.sh"
chmod +x "$SCRIPT_DIR/cleanup.sh"
chmod +x "$SCRIPT_DIR/ensure_ffmpeg_requirements.sh"
chmod +x "$SCRIPT_DIR/fix_ffmpeg_codecs.sh"
chmod +x "$PROJECT_ROOT/orchestrator/run_orchestration.sh"
chmod +x "$PROJECT_ROOT/orchestrator/validate_server.sh"
```

**Problem:** Missed some scripts:
- ❌ `scripts/install.sh` (itself!)
- ❌ `scripts/lib/ffmpeg_checks.sh` (library script)
- ❌ Any future `.sh` files added

---

## Current Behavior (✅ Complete)

**After the update**, `install.sh` now makes **ALL** `.sh` files executable:

```bash
# Primary approach: Use find to make all .sh files executable
find "$PROJECT_ROOT" -type f -name "*.sh" -exec chmod +x {} \;

# Fallback: If find fails (e.g., Windows/Git Bash), chmod specific scripts
chmod +x [specific scripts...]
```

**Advantages:**
- ✅ Finds all `.sh` files recursively
- ✅ Works for current and future scripts
- ✅ Includes library scripts (`lib/ffmpeg_checks.sh`)
- ✅ Includes itself (`install.sh`)
- ✅ Has fallback for systems where `find` doesn't work

---

## All Shell Scripts in Project

After running `install.sh`, these files will be executable:

### Root Level
- `stream_load_tester.sh` - Main load testing tool

### scripts/
- `install.sh` - Installation script (NEW: now makes itself executable)
- `check_dependencies.sh` - Dependency checker
- `cleanup.sh` - Process cleanup utility
- `ensure_ffmpeg_requirements.sh` - FFmpeg requirement checker
- `fix_ffmpeg_codecs.sh` - FFmpeg codec fixer

### scripts/lib/
- `ffmpeg_checks.sh` - FFmpeg checking library (NEW: now made executable)

### orchestrator/
- `run_orchestration.sh` - Main orchestration script
- `validate_server.sh` - Server validation script

---

## How It Works

### Primary Method: find Command
```bash
find "$PROJECT_ROOT" -type f -name "*.sh" -exec chmod +x {} \;
```

**What it does:**
1. Searches from `$PROJECT_ROOT` recursively
2. Finds all files (`-type f`)
3. Matching pattern `*.sh`
4. Executes `chmod +x` on each file

**Advantages:**
- Automatic - no need to maintain a list
- Future-proof - works for new scripts
- Recursive - finds scripts in subdirectories

### Fallback Method: Explicit chmod
```bash
chmod +x "$PROJECT_ROOT/stream_load_tester.sh" 2>/dev/null || true
chmod +x "$SCRIPT_DIR/check_dependencies.sh" 2>/dev/null || true
# ... etc
```

**When used:**
- If `find` command fails (rare)
- Some Windows/Git Bash environments
- Systems with restricted `find` access

**Advantages:**
- Guaranteed to work on main scripts
- Silent failures (`2>/dev/null || true`)
- Covers all critical scripts

---

## Testing

### Verify All Scripts Are Executable

After running `install.sh`, check permissions:

```bash
# List all .sh files and their permissions
find . -type f -name "*.sh" -ls

# Or simpler:
ls -la stream_load_tester.sh
ls -la scripts/*.sh
ls -la scripts/lib/*.sh
ls -la orchestrator/*.sh
```

**Expected output:**
```
-rwxr-xr-x  1 user group  12345 Oct 17 12:34 stream_load_tester.sh
-rwxr-xr-x  1 user group  12345 Oct 17 12:34 scripts/install.sh
-rwxr-xr-x  1 user group  12345 Oct 17 12:34 scripts/check_dependencies.sh
...
```

Note the `x` (executable) permission in `-rwxr-xr-x`.

---

## Manual Permission Fix

If for some reason permissions are wrong, you can fix them manually:

### Option 1: Run install.sh
```bash
bash scripts/install.sh --yes
```

### Option 2: Use find (Linux/macOS/WSL)
```bash
find . -type f -name "*.sh" -exec chmod +x {} \;
```

### Option 3: Manual chmod
```bash
chmod +x stream_load_tester.sh
chmod +x scripts/*.sh
chmod +x scripts/lib/*.sh
chmod +x orchestrator/*.sh
```

### Option 4: Git (if using Git Bash on Windows)
```bash
git update-index --chmod=+x stream_load_tester.sh
git update-index --chmod=+x scripts/*.sh
# etc.
```

---

## Common Issues

### Issue 1: "Permission denied" when running scripts

**Symptoms:**
```bash
./stream_load_tester.sh
bash: ./stream_load_tester.sh: Permission denied
```

**Solution:**
```bash
# Quick fix for one file
chmod +x ./stream_load_tester.sh

# Or run install.sh to fix all
bash scripts/install.sh --yes
```

---

### Issue 2: Scripts not executable after git clone

**Cause:** Git doesn't preserve executable permissions on some systems (especially Windows)

**Solution:**
```bash
# After cloning, run install.sh
cd PublishLoadTester
bash scripts/install.sh --yes
```

---

### Issue 3: find command not working

**Symptoms:**
```bash
find: command not found
```

**Solution:** The install.sh fallback will handle this automatically. If not, use manual chmod:
```bash
chmod +x stream_load_tester.sh
chmod +x scripts/*.sh
chmod +x scripts/lib/*.sh
chmod +x orchestrator/*.sh
```

---

## Why This Matters

### For Users
- ✅ Don't need to manually `chmod +x` every script
- ✅ Scripts work immediately after installation
- ✅ No "permission denied" errors

### For Developers
- ✅ Don't need to remember to add new scripts to install.sh
- ✅ Works automatically for new `.sh` files
- ✅ Consistent permissions across the project

### For CI/CD
- ✅ Automated setup works reliably
- ✅ No manual permission fixes needed
- ✅ Scripts are executable in pipelines

---

## Best Practices

### When Creating New Scripts

1. **Name with .sh extension**
   ```bash
   my_new_script.sh  # ✅ Will be made executable
   my_script         # ❌ Won't be found by install.sh
   ```

2. **Add shebang line**
   ```bash
   #!/bin/bash
   # or
   #!/usr/bin/env bash
   ```

3. **Run install.sh after creating**
   ```bash
   bash scripts/install.sh --yes
   ```

---

## Summary

**Question:** Does install.sh chmod +x all .sh files?

**Answer:** **YES!** ✅ (After the update)

**How:**
1. Uses `find` to recursively make all `.sh` files executable
2. Has fallback for systems where `find` doesn't work
3. Future-proof - works for new scripts automatically

**Before:** Only specific scripts (7 files)  
**After:** ALL `.sh` files in the project (8+ files, including future ones)

**What changed:**
- Added `find` command to automatically find all `.sh` files
- Added fallback for compatibility
- Now includes `install.sh` itself and `lib/ffmpeg_checks.sh`

**Run this to ensure all scripts are executable:**
```bash
./scripts/install.sh --yes
```

✅ **All scripts will be executable after running install.sh!**
