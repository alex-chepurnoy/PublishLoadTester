# Phase 0 Testing Guide

**Purpose:** Step-by-step testing procedures for Tasks 9 & 10  
**Status:** Implementation complete - ready for validation  
**Estimated Time:** 30-45 minutes  

---

## Prerequisites

Before starting tests:

- [ ] EC2 Wowza server is running
- [ ] You have SSH key for server access
- [ ] You know server IP address
- [ ] Wowza is running on the server
- [ ] You're in the PublishLoadTester directory

---

## Task 9: Validate Server Tools

### Step 1: Run Validation Script

```bash
./orchestrator/validate_server.sh ~/path/to/key.pem ubuntu@YOUR_SERVER_IP
```

**Replace:**
- `~/path/to/key.pem` with your actual SSH key path
- `YOUR_SERVER_IP` with your Wowza server IP

### Step 2: Review Validation Results

Look for these sections in the output:

#### ✅ Expected Output (All Tools Present)
```
=== Validating Monitoring Setup on YOUR_SERVER_IP ===

0. Checking local Python3 (required for parsing)...
  ✓ python3 Python 3.x.x

1. Checking monitoring tools availability on server...
  ✓ pidstat
  ✓ sar
  ✓ ps
  ✓ grep
  ✓ awk

2. Checking Java heap monitoring tools...
  ✓ jcmd
  ✓ jstat
  ✓ jmap

3. Checking optional tools...
  ✓ ifstat (optional)

4. Testing sar network monitoring...
  [sar output showing network stats]

5. Detecting Wowza process (Method 1: ps + grep)...
  ✓ Found Wowza PID: 12345
  Process details:
  [Process details showing Wowza Java process]

6. Testing Java heap monitoring (if Wowza found)...
  Testing jcmd GC.heap_info...
  [Heap info output]
  ✓ jcmd works
  
  Testing jstat -gc...
  [GC stats output]
  ✓ jstat works
  
  Testing jmap -heap (brief check only)...
  [Heap summary]
  ✓ jmap works (emergency fallback available)

7. Testing pidstat on detected Wowza PID...
  [pidstat output]

=== Validation Complete ===
✓ Server appears ready for orchestrated load testing
  Wowza PID: 12345
```

### Step 3: Install Missing Tools (If Needed)

#### If jcmd/jstat/jmap Missing:
```bash
# Ubuntu/Debian
ssh -i ~/key.pem ubuntu@YOUR_SERVER_IP "sudo apt-get install -y openjdk-11-jdk-headless"

# Amazon Linux
ssh -i ~/key.pem ec2-user@YOUR_SERVER_IP "sudo yum install -y java-11-openjdk-devel"
```

#### If pidstat/sar Missing:
```bash
# Ubuntu/Debian
ssh -i ~/key.pem ubuntu@YOUR_SERVER_IP "sudo apt-get install -y sysstat"

# Amazon Linux
ssh -i ~/key.pem ec2-user@YOUR_SERVER_IP "sudo yum install -y sysstat"
```

#### If ifstat Missing (Optional):
```bash
# Ubuntu/Debian
ssh -i ~/key.pem ubuntu@YOUR_SERVER_IP "sudo apt-get install -y ifstat"

# Amazon Linux
ssh -i ~/key.pem ec2-user@YOUR_SERVER_IP "sudo yum install -y ifstat"
```

**Note:** ifstat is optional. The system will use `sar -n DEV` as fallback.

### Step 4: Re-run Validation

After installing tools, run validation again:
```bash
./orchestrator/validate_server.sh ~/path/to/key.pem ubuntu@YOUR_SERVER_IP
```

**✅ PASS CRITERIA:** All required tools show ✓, Wowza PID detected, heap monitoring works

---

## Task 10: Test Monitoring Functions

### Step 1: Manual Function Tests

Open a terminal and source the orchestration script:

```bash
cd "c:\Users\alex.chepurnoy\Documents\Self Made Tools\PublishLoadTester"

# If using WSL
wsl
cd /mnt/c/Users/alex.chepurnoy/Documents/Self\ Made\ Tools/PublishLoadTester

# Set required variables (replace with your values)
export KEY_PATH="~/path/to/key.pem"
export SSH_USER="ubuntu"
export SERVER_IP="YOUR_SERVER_IP"
export SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

# Source the script to load functions
source orchestrator/run_orchestration.sh
```

### Step 2: Test Individual Functions

```bash
# Test CPU monitoring
echo "Testing CPU..."
cpu=$(get_server_cpu)
echo "CPU: $cpu%"
# Expected: A number like 45.23

# Test Heap monitoring
echo "Testing Heap..."
heap=$(get_server_heap)
echo "Heap: $heap%"
# Expected: A number like 62.18

# Test Memory monitoring
echo "Testing Memory..."
mem=$(get_server_memory)
echo "Memory: $mem%"
# Expected: A number like 58.90

# Test Network monitoring
echo "Testing Network..."
net=$(get_server_network)
echo "Network: $net Mbps"
# Expected: A number like 125.45

# Test unified status check
echo "Testing unified status..."
status=$(check_server_status)
echo "Status: $status"
# Expected: CPU|HEAP|MEM|NET like "45.23|62.18|58.90|125.45"

# Parse the unified status
IFS='|' read -r cpu heap mem net <<< "$status"
echo "Parsed: CPU=$cpu% | Heap=$heap% | Mem=$mem% | Net=$net Mbps"
```

**✅ PASS CRITERIA:** All functions return valid numeric values (not 0.00 or empty)

### Step 3: Test Remote Monitoring Script Deployment

This requires running a short test. We'll modify the config temporarily:

```bash
# Edit config to create a very short test
cp config/default.conf config/test_phase0.conf

# Edit config/test_phase0.conf to set:
# PROTOCOLS=(rtmp)
# RESOLUTIONS=(360p)
# VIDEO_CODECS=(libx264)
# BITRATES_LOW[360p]=800
# CONNECTIONS=(1)
# TEST_DURATION_SECS=60  # 1 minute only
```

Run the short test:
```bash
# Start test
./orchestrator/run_orchestration.sh

# When prompted:
# - Select protocol: rtmp
# - Select resolution: 360p
# - Enter run ID: phase0_test
# - SSH key path: your key path
# - SSH user: ubuntu
# - Server IP: your server IP
# - Config file: config/test_phase0.conf
# - Pilot mode: No
```

### Step 4: Verify Remote Monitor During Test

While test is running, open a second terminal:

```bash
# SSH to server
ssh -i ~/key.pem ubuntu@YOUR_SERVER_IP

# Find the monitoring log
ls -la /tmp/load_tester_*/monitors/

# Should see:
# - remote_monitor.pid
# - monitor_*.log
# - remote_monitor_stdout.log

# Watch the monitoring log in real-time
tail -f /tmp/load_tester_*/monitors/monitor_*.log
```

**Expected Output:**
```
TIMESTAMP,CPU_PCT,HEAP_PCT,MEM_PCT,NET_MBPS,WOWZA_PID
2025-10-17_14:30:00,45.23,62.18,58.90,125.45,12345
2025-10-17_14:30:05,46.12,63.01,59.12,127.89,12345
2025-10-17_14:30:10,44.98,61.87,58.75,126.12,12345
```

**✅ PASS CRITERIA:** 
- CSV file created
- Header row present
- New row added every 5 seconds
- All columns have valid values

### Step 5: Check Orchestrator Logs

In the first terminal (where test is running):

```bash
# After test completes, check logs
cat orchestrator/runs/phase0_test/orchestrator.log | grep "Server Status"
```

**Expected Output:**
```
[2025-10-17 14:30:00] Server Status: CPU=45.23% | Heap=62.18% | Mem=58.90% | Net=125.45Mbps
[2025-10-17 14:31:00] Server Status: CPU=46.12% | Heap=63.01% | Mem=59.12% | Net=127.89Mbps
```

**✅ PASS CRITERIA:** Status logged before test start, showing all 4 metrics

### Step 6: Verify Log Fetching

After test completes:

```bash
# Check that server logs were fetched
ls orchestrator/runs/phase0_test/server_logs/

# Should contain:
# - monitor_*.log (from remote_monitor.sh)
# - pidstat.log
# - sar_cpu.log
# - sar_net.log
# - jstat_gc.log (if Wowza detected)

# Verify monitor log content
head -20 orchestrator/runs/phase0_test/server_logs/monitor_*.log
```

**✅ PASS CRITERIA:** All monitoring logs present and contain data

---

## Task 10: Test Adaptive Stopping

### Test 1: CPU Threshold

```bash
# TEMPORARILY edit run_orchestration.sh
# Find line: if (( cpu_int >= 80 )); then
# Change to: if (( cpu_int >= 30 )); then

# Run a test that will generate load
./orchestrator/run_orchestration.sh

# Use settings:
# - Protocol: rtmp
# - Resolution: 1080p
# - Connections: 20
# - Duration: 300 (5 minutes)

# Watch the logs - test should stop when CPU hits 30%
```

**Expected Output:**
```
Server Status: CPU=31.45% | Heap=55.23% | Mem=62.10% | Net=215.67Mbps
Server CPU >= 80% (current: 31.45%). Halting further tests.
```

**✅ PASS CRITERIA:** 
- Test stops when CPU threshold reached
- Correct reason logged
- No crash or error

### Test 2: Heap Threshold

```bash
# Edit run_orchestration.sh
# Change CPU threshold back to 80
# Find line: if (( heap_int >= 80 )); then
# Change to: if (( heap_int >= 40 )); then

# Run test again
# Should stop when heap reaches 40%
```

**Expected Output:**
```
Server Status: CPU=45.23% | Heap=41.18% | Mem=58.90% | Net=125.45Mbps
Server Heap >= 80% (current: 41.18%). Halting further tests.
```

**✅ PASS CRITERIA:** 
- Test stops when Heap threshold reached
- Correct reason logged
- No crash or error

### Restore Thresholds

**IMPORTANT:** After testing, restore original thresholds:

```bash
# Edit run_orchestration.sh
# Change back to:
# if (( cpu_int >= 80 )); then
# if (( heap_int >= 80 )); then
```

---

## Error Handling Tests

### Test 1: Wowza Not Running

```bash
# SSH to server and stop Wowza
ssh -i ~/key.pem ubuntu@YOUR_SERVER_IP
sudo systemctl stop wowza  # or however you stop Wowza

# Run monitoring functions
get_server_heap
# Expected: 0.00 or N/A with warning log

get_server_cpu
# Expected: Still works (doesn't depend on Wowza)
```

**✅ PASS CRITERIA:** Functions handle missing Wowza gracefully

### Test 2: jcmd Not Available

```bash
# SSH to server
ssh -i ~/key.pem ubuntu@YOUR_SERVER_IP

# Temporarily make jcmd unavailable
sudo mv /usr/bin/jcmd /usr/bin/jcmd.bak

# Run heap monitoring
get_server_heap
# Expected: Falls back to jstat, still returns valid value

# Restore jcmd
sudo mv /usr/bin/jcmd.bak /usr/bin/jcmd
```

**✅ PASS CRITERIA:** Fallback to jstat works automatically

---

## Final Checklist

After completing all tests above:

- [ ] Validation script runs successfully
- [ ] All required tools installed on server
- [ ] Wowza PID detected correctly
- [ ] `get_server_cpu()` returns valid percentage
- [ ] `get_server_heap()` returns valid percentage
- [ ] `get_server_memory()` returns valid percentage
- [ ] `get_server_network()` returns valid Mbps
- [ ] `check_server_status()` returns pipe-delimited string
- [ ] `remote_monitor.sh` deploys automatically
- [ ] Monitor log created with CSV format
- [ ] Logs update every 5 seconds
- [ ] Server logs fetched after test
- [ ] Adaptive stopping works for CPU threshold
- [ ] Adaptive stopping works for Heap threshold
- [ ] Fallback to jstat works if jcmd unavailable
- [ ] Graceful handling when Wowza not running

---

## Troubleshooting

### Problem: Validation shows "Wowza process not detected"

**Solution:**
```bash
# Check if Wowza is running
ssh -i ~/key.pem ubuntu@YOUR_SERVER_IP "ps aux | grep java | grep -i wowza"

# If not running, start it
ssh -i ~/key.pem ubuntu@YOUR_SERVER_IP "sudo systemctl start wowza"

# Run validation again
```

### Problem: jcmd/jstat/jmap not found

**Solution:**
```bash
# Install JDK (not just JRE)
ssh -i ~/key.pem ubuntu@YOUR_SERVER_IP "sudo apt-get install -y openjdk-11-jdk-headless"
```

### Problem: Network monitoring returns 0.00

**Solution:**
```bash
# Check network interface name
ssh -i ~/key.pem ubuntu@YOUR_SERVER_IP "ip link show"

# If not eth0, edit get_server_network() in run_orchestration.sh
# Common alternatives: ens5, ens3, eth1
```

### Problem: Permission denied errors

**Solution:**
```bash
# Ensure key has correct permissions
chmod 600 ~/path/to/key.pem

# Ensure SSH user is correct (ubuntu vs ec2-user)
```

---

## Success Criteria Summary

**Phase 0 is validated when:**

1. ✅ Server has all required monitoring tools
2. ✅ All monitoring functions return valid data
3. ✅ Remote monitoring script deploys and runs
4. ✅ CSV logs are created and populated
5. ✅ Health checks log all 4 metrics
6. ✅ Adaptive stopping works for both thresholds
7. ✅ Fallback mechanisms work
8. ✅ Error handling is graceful

**After validation:** Ready to proceed with Phase 1 (Core Configuration)

---

## Next Steps After Testing

Once all tests pass:

1. Document any issues found and resolved
2. Update PHASE_0_COMPLETE.md with actual test results
3. Create Phase 1 implementation plan
4. Begin Phase 1: Core Configuration updates

---

**Estimated Testing Time:** 30-45 minutes  
**Prerequisites:** EC2 server with Wowza running  
**Risk Level:** Low (monitoring only, no config changes)
