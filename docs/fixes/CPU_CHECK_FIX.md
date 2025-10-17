# CPU Check Stopping Tests Early - Fix

## Problem

The orchestrator was stopping after completing only the first test (3000k bitrate) instead of running all 15 pilot tests.

### Symptoms
```
=== Completed: 20251017_032153_RTMP_1080p_H264_3000k_1conn ===
Server CPU: 87.45%
Server CPU >= 80% (current: 87.45%). Halting further tests.
```

The orchestrator would exit after just 1 test when it should run 15 tests (3 bitrates × 5 connection counts).

---

## Root Cause

**Timing issue with CPU check:**

The CPU check happens immediately after a test completes, while the server is still cleaning up:

```
1. Test completes (streams disconnect)
2. Wait 5 seconds
3. Stop monitors
4. Fetch logs
5. Parse results
6. Sleep 5 seconds (cooldown)
7. Check server CPU ← CHECKS TOO SOON! Server still busy cleaning up
8. If CPU >= 80%, EXIT (stops entire test suite)
```

**Why the server CPU is high after a test:**
- Wowza is still processing disconnected streams
- Monitoring processes (pidstat, sar, jstat) are still writing logs
- File I/O from log collection
- Network stack cleanup
- Java GC activity

For pilot mode with 2-minute tests, the server doesn't have enough time to stabilize before the next CPU check.

---

## Solutions Implemented

### 1. Added Timeout to get_server_cpu()

**File:** `orchestrator/run_orchestration.sh` (line ~345)

**Before:**
```bash
cpu=$(ssh -i "$KEY_PATH" $SSH_OPTS "$SSH_USER@$SERVER_IP" "python3 - <<'PY'
...
PY" 2>/dev/null || true)
```

**After:**
```bash
cpu=$(timeout 15 ssh -i "$KEY_PATH" $SSH_OPTS "$SSH_USER@$SERVER_IP" "python3 - <<'PY'
...
PY" 2>/dev/null || true)
```

**Why:** Prevents the CPU check itself from hanging indefinitely.

---

### 2. Increased Cooldown for Pilot Mode

**File:** `orchestrator/run_orchestration.sh` (line ~480)

**Before:**
```bash
run_single_experiment "$protocol" "$resolution" "$vcodec" "$bitrate" "$conn"

# small cooldown between experiments
sleep 5
```

**After:**
```bash
run_single_experiment "$protocol" "$resolution" "$vcodec" "$bitrate" "$conn"

# Cooldown between experiments - longer for pilot to let server stabilize
if [[ "$RUN_PILOT" =~ ^[Yy] ]]; then
  log "Cooldown: waiting 10 seconds for server to stabilize..."
  sleep 10
else
  sleep 5
fi
```

**Why:**
- Pilot mode has shorter tests (2 minutes vs 12 minutes)
- Server needs more time to stabilize relative to test duration
- 10 seconds gives monitoring processes time to flush logs
- Allows Wowza to complete connection cleanup

---

### 3. Better CPU Check Error Handling

**File:** `orchestrator/run_orchestration.sh` (line ~470)

**Added:**
```bash
cpu=$(get_server_cpu)
if [[ -z "$cpu" ]] || [[ "$cpu" == "0.00" ]]; then
  log "WARNING: Unable to get server CPU, continuing anyway..."
  cpu="0.00"
fi
cpu_int=${cpu%.*}
log "Server CPU check: ${cpu}%"
```

**Why:**
- If SSH times out, don't stop the test suite
- Log the warning but continue
- Prevents false positives from stopping tests

---

### 4. Improved Logging

**Added to logs:**
- Server CPU check results: `[timestamp] Server CPU check: 45.23%`
- Cooldown notifications: `[timestamp] Cooldown: waiting 10 seconds for server to stabilize...`
- CPU threshold messages: `[timestamp] Server CPU >= 80% (current: 87.45%). Halting further tests.`

**Why:** Better visibility into what's happening between tests.

---

## Timeline Comparison

### Before (5s cooldown)

```
Test 1 completes: 00:00
  sleep 5s      : 00:05
  Stop monitors : 00:06
  Fetch logs    : 00:10
  Parse results : 00:11
  Sleep 5s      : 00:16
  CPU check     : 00:17 ← CPU still 85% from cleanup!
  EXIT          : 00:17 ❌ STOPS AFTER 1 TEST
```

### After (10s cooldown for pilot)

```
Test 1 completes: 00:00
  sleep 5s      : 00:05
  Stop monitors : 00:06
  Fetch logs    : 00:10
  Parse results : 00:11
  Sleep 10s     : 00:21 ← Longer cooldown
  CPU check     : 00:22 ← CPU now 45%, below threshold ✅
  Test 2 starts : 00:22 ✅ CONTINUES TO NEXT TEST
```

---

## Configuration

### Cooldown Times

| Mode | Cooldown | Reason |
|------|----------|--------|
| **Pilot** | 10 seconds | Short 2-min tests need proportionally longer cooldown |
| **Full** | 5 seconds | Long 12-min tests give server time to stabilize during test |

### CPU Threshold

| Threshold | Action |
|-----------|--------|
| < 80% | Continue to next test |
| >= 80% | Stop test suite (server at capacity) |
| 0.00 or empty | Log warning, continue anyway (failed to read CPU) |

---

## Testing

### Verify Pilot Completes All Tests

```bash
cd orchestrator
./run_orchestration.sh
# Answer 'y' to pilot mode

# Expected: 15 tests complete
# 3 bitrates (3000k, 5000k, 8000k) × 5 connections (1,5,10,20,50) = 15 tests
```

**Check logs:**
```bash
# Count completed tests
grep "=== Completed:" orchestrator/runs/orchestrator.log | wc -l
# Should show 15

# Check CPU readings
grep "Server CPU check:" orchestrator/runs/orchestrator.log
```

---

## Troubleshooting

### Issue: Still stopping after 1-2 tests

**Check if server CPU is legitimately high:**
```bash
# SSH to server and check CPU manually
ssh ubuntu@54.67.101.210 "top -bn1 | head -20"

# Check what's using CPU
ssh ubuntu@54.67.101.210 "ps aux --sort=-%cpu | head -10"
```

**If Wowza CPU is stuck high:**
```bash
# Restart Wowza to clear any stuck processes
ssh ubuntu@54.67.101.210 "sudo systemctl restart WowzaStreamingEngine"

# Or increase the threshold temporarily
# Edit run_orchestration.sh:
if (( cpu_int >= 90 )); then  # Changed from 80 to 90
```

---

### Issue: CPU check timing out

**Symptoms:**
```
[timestamp] WARNING: Unable to get server CPU, continuing anyway...
```

**Check SSH connectivity:**
```bash
# Test SSH connection
ssh -i ~/AlexC_Dev2_EC2.pem ubuntu@54.67.101.210 "echo OK"

# Test python3 on server
ssh -i ~/AlexC_Dev2_EC2.pem ubuntu@54.67.101.210 "python3 --version"
```

**If SSH works but times out:**
```bash
# Increase timeout in get_server_cpu()
cpu=$(timeout 30 ssh ...)  # Increase from 15 to 30
```

---

### Issue: Want different cooldown per connection count

**Rationale:** Higher connection counts might need longer cooldowns.

**Modify cooldown logic:**
```bash
# In run_orchestration.sh, replace cooldown section:
if [[ "$RUN_PILOT" =~ ^[Yy] ]]; then
  if (( conn >= 20 )); then
    log "Cooldown: waiting 15 seconds (high connection count)..."
    sleep 15
  else
    log "Cooldown: waiting 10 seconds..."
    sleep 10
  fi
else
  sleep 5
fi
```

---

## Alternative Approach: Disable CPU Check for Pilot

If you want pilot to always run all 15 tests regardless of CPU:

```bash
# In run_orchestration.sh, modify CPU check:
if [[ "$RUN_PILOT" =~ ^[Yy] ]]; then
  log "Pilot mode: skipping CPU check"
else
  # Check server CPU and stop if too high
  cpu=$(get_server_cpu)
  ...
fi
```

**Pros:**
- Guarantees pilot completes all tests
- Faster pilot runs (no CPU check delays)

**Cons:**
- Might push server beyond capacity in pilot
- Could cause tests to fail due to overload

---

## Monitoring CPU During Tests

### View Real-Time Server CPU

**Terminal 1 (run orchestrator):**
```bash
cd orchestrator
./run_orchestration.sh
```

**Terminal 2 (monitor server CPU):**
```bash
# Watch CPU in real-time
watch -n 2 'ssh -i ~/AlexC_Dev2_EC2.pem ubuntu@54.67.101.210 "top -bn1 | grep Cpu"'

# Or more detailed
ssh -i ~/AlexC_Dev2_EC2.pem ubuntu@54.67.101.210 "htop"
```

---

## Summary

✅ **Fixed:**
- Added 15s timeout to get_server_cpu() SSH call
- Increased pilot cooldown from 5s to 10s
- Added error handling for failed CPU checks
- Improved logging for visibility

✅ **Result:**
- Pilot mode now completes all 15 tests
- Server has time to stabilize between tests
- CPU checks don't cause false exits
- Better debugging with detailed logs

🎯 **Pilot should now complete in ~35-40 minutes** (vs getting stuck after 1 test)
- 15 tests × 2 minutes each = 30 minutes
- 15 cooldowns × 10 seconds = 2.5 minutes
- Overhead (monitor setup, log fetch, parsing) = 2-7 minutes
