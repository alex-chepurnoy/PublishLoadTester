# Phase 0: Monitoring Infrastructure - Summary

## Quick Reference

**Priority**: 🔥 **CRITICAL** - Must complete before all other phases  
**Time**: 6-8 hours  
**Status**: 📋 Ready for implementation

## What Phase 0 Delivers

### 1. Live Monitoring Functions
```bash
get_server_cpu()      # Returns current CPU usage (0-100%)
get_server_heap()     # Returns current heap usage (0-100%) - NEW
get_server_memory()   # Returns current memory usage (0-100%) - NEW
get_server_network()  # Returns current network throughput (Mbps) - NEW
check_server_status() # Returns all metrics: CPU|HEAP|MEM|NET - NEW
```

### 2. Server-Side Continuous Logging
```
monitors/cpu_live.log      # Timestamped CPU every 5s
monitors/heap_live.log     # Timestamped heap every 5s
monitors/memory_live.log   # Timestamped memory every 5s
monitors/network_live.log  # Timestamped network every 5s
```

### 3. Validation Tools
```bash
orchestrator/validate_monitoring.sh  # Pre-test validation script - NEW
# Checks:
# - SSH connectivity
# - Wowza PID detection
# - jstat availability
# - All monitoring tools
# - Live query functionality
```

### 4. Health Checks
- Monitor process health during tests
- Auto-restart failed monitoring
- Alert on logging gaps
- Graceful degradation

## Why This is Critical

```
Current State:                      Phase 0 Delivers:
├─ CPU: ✅ Works                ──► ✅ Keep working
├─ Heap: ⚠️ Logged only        ──► 🔥 Live queries (CRITICAL)
├─ Memory: ❌ Not monitored    ──► ✅ Live queries
├─ Network: ❌ Not monitored   ──► ✅ Live queries
└─ Validation: ❌ None         ──► 🔥 Pre-test checks (CRITICAL)
```

**Adaptive stopping requires:**
- Live heap monitoring (doesn't exist yet)
- Validated monitoring setup (doesn't exist yet)
- Reliable metric queries (needs enhancement)

## Implementation Checklist

### Tasks

- [ ] **0.1** Document current monitoring (already done)
- [ ] **0.2** Create `get_server_heap()` function
- [ ] **0.3** Create `get_server_memory()` function
- [ ] **0.4** Create `get_server_network()` function
- [ ] **0.5** Create `check_server_status()` unified function
- [ ] **0.6** Enhance server-side continuous monitoring
- [ ] **0.7** Create `validate_monitoring.sh` script
- [ ] **0.8** Add health checks to main orchestrator

### Files to Create/Modify

**New Files**:
1. `orchestrator/validate_monitoring.sh` (validation script)
2. Server-side `/var/tmp/wlt_monitor.sh` (continuous logging)

**Modified Files**:
1. `orchestrator/run_orchestration.sh`:
   - Add `get_server_heap()` function (~line 377)
   - Add `get_server_memory()` function
   - Add `get_server_network()` function
   - Add `check_server_status()` function
   - Enhance `remote_start_monitors()` function
   - Add monitoring health checks to main loop

## Testing Plan

### Step 1: Server Preparation
```bash
# SSH to server
ssh ubuntu@[SERVER_IP]

# Install required tools
sudo apt-get update
sudo apt-get install -y sysstat ifstat openjdk-11-jdk-headless

# Verify jstat works
which jstat
jstat -help

# Start Wowza
# [Your Wowza start command]
```

### Step 2: Run Validation
```bash
# On orchestrator machine
./orchestrator/validate_monitoring.sh \
  --server-ip [SERVER_IP] \
  --ssh-key ~/.ssh/key.pem \
  --ssh-user ubuntu

# Expected: All checks pass ✅
```

### Step 3: Test Live Queries
```bash
# Run orchestrator
./run_orchestration.sh

# During prompts, check logs for:
# - Wowza PID detected
# - CPU query successful
# - Heap query successful
# - Memory query successful
# - Network query successful
```

### Step 4: Pilot Test
```bash
./run_orchestration.sh --pilot

# Verify during/after test:
# 1. monitors/cpu_live.log populated
# 2. monitors/heap_live.log populated
# 3. monitors/memory_live.log populated
# 4. monitors/network_live.log populated
# 5. No gaps in timestamps
# 6. All values within 0-100% (or Mbps for network)
```

## Success Criteria

- ✅ `get_server_heap()` returns valid percentage
- ✅ `get_server_memory()` returns valid percentage
- ✅ `get_server_network()` returns valid Mbps
- ✅ `check_server_status()` returns all metrics
- ✅ Validation script passes all checks
- ✅ Continuous logs populated without gaps
- ✅ Graceful handling when Wowza not running
- ✅ No SSH timeouts or hangs
- ✅ Health checks detect and restart failed monitoring

## Common Issues & Solutions

### Issue 1: Wowza PID Not Detected
```bash
# Test PID detection manually:
ssh ubuntu@[SERVER_IP] "ps aux | grep -E '[Ww]owza|java.*com.wowza' | grep -v grep"

# If no results, Wowza not running
# Start Wowza and retry
```

### Issue 2: jcmd/jstat Not Found
```bash
# Install Java JDK:
sudo apt-get install -y openjdk-11-jdk-headless

# Verify jcmd (preferred):
which jcmd
jcmd -h

# Verify jstat (fallback):
which jstat
jstat -help
```

### Issue 3: Heap Query Returns 0.00
```bash
# Test jcmd manually:
ssh ubuntu@[SERVER_IP]
jcmd [WOWZA_PID] GC.heap_info

# If fails, try jstat:
jstat -gc [WOWZA_PID]

# If both fail, check Java version compatibility:
java -version

# Ensure PID is correct:
ps aux | grep -E '[Ww]owza|java.*com.wowza'
```

### Issue 4: SSH Timeouts
```bash
# Increase timeout in get_server_heap():
timeout 10 ssh ...  # Change to: timeout 30 ssh ...

# Add SSH keepalive:
SSH_OPTS="-o ServerAliveInterval=5 -o ServerAliveCountMax=3"
```

## Next Steps After Phase 0

Once Phase 0 complete:
1. ✅ Phase 4: Adaptive Stopping (uses heap monitoring)
2. ✅ Phase 1: Core Configuration (needs validation)
3. ✅ Phase 2: Test Order (needs working metrics)
4. ✅ Continue remaining phases

## Time Breakdown

| Task | Estimated Time |
|------|----------------|
| 0.2 - Heap function | 1.5 hours |
| 0.3 - Memory function | 0.5 hours |
| 0.4 - Network function | 0.5 hours |
| 0.5 - Status function | 0.5 hours |
| 0.6 - Continuous logging | 1.5 hours |
| 0.7 - Validation script | 1.5 hours |
| 0.8 - Health checks | 1 hour |
| Testing | 1-2 hours |
| **Total** | **6-8 hours** |

---

**Ready to Implement**: Yes ✅  
**Blockers**: None  
**Dependencies**: Server must have jstat, jmap, pidstat, sar installed  
**Last Updated**: October 17, 2025
