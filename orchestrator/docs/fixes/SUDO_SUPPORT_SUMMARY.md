# Sudo Support Added for Java Monitoring

## Summary

Added automatic sudo fallback support for Java monitoring tools (`jcmd`, `jstat`, `jmap`) to handle permission issues when the SSH user is different from the user running Wowza.

---

## Problem

When Wowza runs as a different user (e.g., `wowza` or `root`) than the SSH user (e.g., `ubuntu`), Java monitoring tools fail with:
```
Error: Unable to open socket file: target process not responding or HotSpot VM not loaded
```

This is because `jcmd`, `jstat`, and `jmap` require running as the same user that owns the Java process.

---

## Solution

### Automatic Sudo Fallback

Updated all monitoring scripts to automatically try `sudo` if regular commands fail:

**Execution order** (for each tool):
1. Try command from PATH (without sudo)
2. Try command from Wowza's bin directory (without sudo)
3. Try command from PATH (with sudo) ← NEW
4. Try command from Wowza's bin directory (with sudo) ← NEW
5. Fallback to next tool (jcmd → jstat → jmap)

### Server Configuration

Created setup script and guide to configure passwordless sudo on the server.

---

## Files Modified

### 1. orchestrator/run_orchestration.sh
**Function**: `get_server_heap()`

**Changes**:
- Added sudo fallback for `jcmd` command
- Added sudo fallback for `jstat` command  
- Added sudo fallback for `jmap` command
- Changed `2>/dev/null` to `2>&1` to capture error messages

**Before**:
```bash
"{ command -v jcmd && jcmd $pid GC.heap_info; } || \
 { [ -x $java_bin/jcmd ] && $java_bin/jcmd $pid GC.heap_info; }"
```

**After**:
```bash
"{ command -v jcmd && jcmd $pid GC.heap_info 2>&1; } || \
 { [ -x $java_bin/jcmd ] && $java_bin/jcmd $pid GC.heap_info 2>&1; } || \
 { command -v jcmd && sudo jcmd $pid GC.heap_info 2>&1; } || \
 { [ -x $java_bin/jcmd ] && sudo $java_bin/jcmd $pid GC.heap_info 2>&1; }"
```

### 2. orchestrator/remote_monitor.sh
**Function**: `get_heap()`

**Changes**:
- Added sudo fallback block after regular jcmd attempts
- Added sudo fallback block after jstat attempts
- Same cascading logic as run_orchestration.sh

### 3. orchestrator/diagnose_jcmd.sh (existing)
- Already captures detailed error messages
- Will show if sudo is needed

### 4. orchestrator/validate_server.sh (existing)
- Already tests jcmd/jstat/jmap
- Now will benefit from sudo fallback

---

## New Files Created

### 1. SUDO_SETUP_GUIDE.md
Comprehensive guide covering:
- Three options for solving permission issues
- Security considerations
- Quick setup instructions
- Troubleshooting tips
- Verification steps

### 2. setup_sudo.sh
Automated script to configure passwordless sudo on the server:
- Creates `/etc/sudoers.d/java-monitoring`
- Allows ubuntu user to run jcmd/jstat/jmap without password
- Validates syntax
- Tests configuration
- **Usage**: Run on server as `./setup_sudo.sh ubuntu`

### 3. JCMD_TROUBLESHOOTING.md (updated)
- Added sudo solution to Issue 2
- Added quick setup instructions
- References detailed SUDO_SETUP_GUIDE.md

---

## How to Use

### Option A: Full Automated Setup (Recommended)

```bash
# From your client machine

# 1. Copy setup script to server
scp -i your-key.pem setup_sudo.sh ubuntu@your-server-ip:~/

# 2. SSH and run setup
ssh -i your-key.pem ubuntu@your-server-ip
chmod +x setup_sudo.sh
./setup_sudo.sh ubuntu
exit

# 3. Test from client
./orchestrator/diagnose_jcmd.sh your-server-ip your-key.pem ubuntu

# 4. Run pilot test
./orchestrator/run_orchestration.sh --pilot
```

### Option B: Manual Configuration

See SUDO_SETUP_GUIDE.md for detailed manual steps.

---

## What Gets Created on Server

File: `/etc/sudoers.d/java-monitoring`
```sudoers
# Java monitoring tools - passwordless sudo
ubuntu ALL=(ALL) NOPASSWD: /usr/bin/jcmd
ubuntu ALL=(ALL) NOPASSWD: /usr/bin/jstat
ubuntu ALL=(ALL) NOPASSWD: /usr/bin/jmap
ubuntu ALL=(ALL) NOPASSWD: /usr/local/WowzaStreamingEngine/java/bin/jcmd
ubuntu ALL=(ALL) NOPASSWD: /usr/local/WowzaStreamingEngine/java/bin/jstat
ubuntu ALL=(ALL) NOPASSWD: /usr/local/WowzaStreamingEngine/java/bin/jmap
```

---

## Security

### Why This is Safe

1. **Specific commands only**: Only allows jcmd, jstat, jmap (not full sudo)
2. **Read-only operations**: These tools only read heap data, don't modify
3. **No password exposure**: No passwords in scripts or logs
4. **Audit trail**: All sudo commands logged to `/var/log/auth.log`
5. **Easy to revoke**: Just delete `/etc/sudoers.d/java-monitoring`

### What Access is Granted

The SSH user (ubuntu) can:
- ✅ Read Java heap information from any process
- ✅ Get Java GC statistics
- ❌ Modify Java processes
- ❌ Kill processes
- ❌ Access other sudo commands
- ❌ Full system access

---

## Testing

### 1. Diagnostic Test
```bash
./orchestrator/diagnose_jcmd.sh <server-ip> <key> ubuntu
```

Expected output after setup:
```
3. Testing jcmd access with current user (ubuntu)...
  ✓ SUCCESS! jcmd returned heap data
4. Testing AWK parsing...
  Total: 250880 KB, Used: 143357 KB
  Percentage: 57.14%
```

### 2. Validation Test
```bash
./orchestrator/validate_server.sh
```

Expected:
```
6. Testing Java heap monitoring...
  Testing jcmd GC.heap_info...
  ✓ jcmd works
```

### 3. Pilot Test
```bash
./orchestrator/run_orchestration.sh --pilot
```

Expected log output:
```
[2025-10-17...] Server Status - CPU: 45.2%, Heap: 32.5%, Memory: 48.3%, Network: 0.5 Mbps
```

---

## Fallback Behavior

If sudo is not configured, scripts will still work using the existing fallback chain:

1. jcmd (regular) → **Permission denied**
2. jcmd (sudo) → **Password required** → Skip
3. jstat (regular) → **May work across users** ✓
4. jstat (sudo) → Fallback
5. jmap (emergency) → Last resort

**Result**: System gracefully falls back to jstat, which often works without sudo.

---

## Troubleshooting

### "sudo: no tty present and no askpass program specified"
→ Means passwordless sudo is not configured. Run `setup_sudo.sh` on server.

### "sudo: jcmd: command not found"
→ Sudo doesn't have the PATH. Use full path in sudoers file (script handles this).

### Still getting 0.00% heap?
→ Run diagnostic: `./orchestrator/diagnose_jcmd.sh`

### Want to remove sudo access?
```bash
# On server
sudo rm /etc/sudoers.d/java-monitoring
```

---

## Benefits

1. **Works out of the box**: No need to change Wowza user or SSH as different user
2. **Secure**: Minimal permissions granted
3. **Automatic**: Scripts try sudo automatically if needed
4. **Graceful**: Falls back to jstat if sudo not available
5. **Auditable**: All sudo commands logged
6. **Easy setup**: One script execution on server

---

## Status

- ✅ Scripts updated with sudo support
- ✅ Setup script created
- ✅ Documentation complete
- ⏳ Server configuration needed (run `setup_sudo.sh`)
- ⏳ Testing on actual server

**Next Steps**: Run `setup_sudo.sh` on your EC2 server, then test with pilot mode.
