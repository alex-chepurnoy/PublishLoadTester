# Phase 0 Quick Reference Card

## New Monitoring Functions

### Individual Metrics
```bash
# Get CPU usage (%)
cpu=$(get_server_cpu)
echo "CPU: $cpu%"

# Get Java heap usage (%)
heap=$(get_server_heap)
echo "Heap: $heap%"

# Get system memory usage (%)
mem=$(get_server_memory)
echo "Memory: $mem%"

# Get network throughput (Mbps)
net=$(get_server_network)
echo "Network: $net Mbps"
```

### Unified Status Check
```bash
# Get all metrics in one call (more efficient)
status=$(check_server_status)
IFS='|' read -r cpu heap mem net <<< "$status"
echo "CPU: $cpu% | Heap: $heap% | Mem: $mem% | Net: $net Mbps"
```

## Validation Commands

### Validate Server Setup
```bash
# Check if server has all required monitoring tools
./orchestrator/validate_server.sh ~/your-key.pem ubuntu@your-server-ip

# Example output:
# ✓ pidstat
# ✓ sar
# ✓ jcmd
# ✓ jstat
# ✓ jmap
# ✗ ifstat MISSING (will use sar instead)
```

### Test Monitoring Manually
```bash
# SSH to server and test jcmd
ssh -i ~/key.pem ubuntu@server-ip
WOWZA_PID=$(ps aux | grep -i wowza | grep java | grep -v grep | awk '{print $2}')
jcmd $WOWZA_PID GC.heap_info

# Test jstat
jstat -gc $WOWZA_PID

# Check CPU
python3 -c "
import time
with open('/proc/stat') as f: l1=f.readline().split()[1:]
t1=sum(map(int,l1)); idle1=int(l1[3])
time.sleep(1)
with open('/proc/stat') as f: l2=f.readline().split()[1:]
t2=sum(map(int,l2)); idle2=int(l2[3])
print('%.2f' % (100*(1-(idle2-idle1)/(t2-t1))))
"
```

## Remote Monitoring

### Check Remote Monitor Status
```bash
# SSH to server
ssh -i ~/key.pem ubuntu@server-ip

# Check if remote_monitor.sh is running
ps aux | grep remote_monitor.sh | grep -v grep

# View live monitoring output
tail -f /tmp/load_tester_*/monitors/monitor_*.log

# Check recent entries
tail -n 20 /tmp/load_tester_*/monitors/monitor_*.log
```

### Monitor Log Format
```csv
TIMESTAMP,CPU_PCT,HEAP_PCT,MEM_PCT,NET_MBPS,WOWZA_PID
2025-10-17_14:30:00,45.23,62.18,58.90,125.45,12345
2025-10-17_14:30:05,46.12,63.01,59.12,127.89,12345
```

## Troubleshooting

### Heap Monitoring Returns 0.00
```bash
# Check if Wowza is running
ssh -i ~/key.pem ubuntu@server-ip "ps aux | grep -i wowza | grep java"

# Check if jcmd works
ssh -i ~/key.pem ubuntu@server-ip "jcmd -l"

# Manually get heap
WOWZA_PID=<pid-from-above>
ssh -i ~/key.pem ubuntu@server-ip "jcmd $WOWZA_PID GC.heap_info"
```

### Network Monitoring Returns 0.00
```bash
# Check interface name
ssh -i ~/key.pem ubuntu@server-ip "ip link show"

# If not eth0, update get_server_network() function
# Common alternatives: ens5, ens3, eth1

# Test ifstat
ssh -i ~/key.pem ubuntu@server-ip "ifstat -i eth0 1 1"

# Test sar (fallback)
ssh -i ~/key.pem ubuntu@server-ip "sar -n DEV 1 1"
```

### Install Missing Tools
```bash
# Ubuntu/Debian
ssh -i ~/key.pem ubuntu@server-ip "sudo apt-get update && sudo apt-get install -y sysstat openjdk-11-jdk-headless ifstat"

# Amazon Linux
ssh -i ~/key.pem ec2-user@server-ip "sudo yum install -y sysstat java-11-openjdk-devel ifstat"
```

## Adaptive Stopping Thresholds

Current thresholds in main loop:
- **CPU >= 80%** → Stop tests
- **Heap >= 80%** → Stop tests

To temporarily adjust for testing:
```bash
# Edit run_orchestration.sh, find:
if (( cpu_int >= 80 )); then
if (( heap_int >= 80 )); then

# Change to lower value (e.g., 50) for faster testing:
if (( cpu_int >= 50 )); then
if (( heap_int >= 50 )); then
```

## Log Locations

### Orchestrator Logs
- Main orchestration log: `orchestrator/runs/<run_id>/orchestrator.log`
- Contains "Server Status:" lines with all metrics

### Server-side Logs
- Remote monitor: `/tmp/load_tester_<run_id>/monitors/monitor_*.log`
- pidstat: `/tmp/load_tester_<run_id>/pidstat.log`
- sar CPU: `/tmp/load_tester_<run_id>/sar_cpu.log`
- sar Network: `/tmp/load_tester_<run_id>/sar_net.log`
- jstat GC: `/tmp/load_tester_<run_id>/jstat_gc.log`

### Fetching Server Logs
```bash
# Logs are automatically fetched after each test
# Located in: orchestrator/runs/<run_id>/server_logs/
scp -i ~/key.pem ubuntu@server-ip:/tmp/load_tester_*/monitors/monitor_*.log ./
```

## Example Test Run

```bash
# 1. Validate server first
./orchestrator/validate_server.sh ~/key.pem ubuntu@server-ip

# 2. Start a short test
./orchestrator/run_orchestration.sh

# 3. Monitor in real-time (separate terminal)
ssh -i ~/key.pem ubuntu@server-ip "tail -f /tmp/load_tester_*/monitors/monitor_*.log"

# 4. Check orchestrator logs
tail -f orchestrator/runs/*/orchestrator.log | grep "Server Status"

# 5. Verify adaptive stopping
# Tests should stop when CPU or Heap reaches 80%
```

## Testing Checklist

- [ ] Run `validate_server.sh` - all tools present
- [ ] Test `get_server_cpu()` - returns valid percentage
- [ ] Test `get_server_heap()` - returns valid percentage
- [ ] Test `get_server_memory()` - returns valid percentage
- [ ] Test `get_server_network()` - returns valid Mbps
- [ ] Test `check_server_status()` - returns pipe-delimited string
- [ ] Verify `remote_monitor.sh` deploys and starts
- [ ] Verify CSV log file created and populated
- [ ] Verify adaptive stopping at 80% CPU
- [ ] Verify adaptive stopping at 80% Heap
- [ ] Verify fallback to jstat if jcmd fails
- [ ] Verify graceful handling if Wowza not running
