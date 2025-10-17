# Orchestrator Setup Requirements

## Local (Control Machine) Requirements

The orchestrator runs on your **local machine** (laptop/desktop) and controls remote tests.

### Required Tools

#### 1. **Bash Shell** (Required)
- **Linux/macOS:** Built-in ✓
- **Windows:** Use WSL (Windows Subsystem for Linux)

#### 2. **SSH Client** (Required)
- **Linux/macOS:** Built-in ✓
- **Windows:** Built-in in PowerShell/WSL ✓

#### 3. **Python 3** (Required for results parsing)
- **Check if installed:**
  ```bash
  python3 --version
  ```
  
- **Install if missing:**
  ```bash
  # Ubuntu/Debian/WSL
  sudo apt-get update && sudo apt-get install -y python3
  
  # macOS
  brew install python3
  
  # Windows (native)
  # Download from python.org or use WSL
  ```

- **What happens if Python is missing?**
  - ✅ Tests will still run
  - ✅ Logs will be collected
  - ❌ **No CSV results generated**
  - ❌ **No aggregated metrics**
  
#### 4. **SSH Key File** (Required)
- Must have `.pem` key file with proper permissions
- Permissions must be `600` (script will attempt to fix)

---

## Remote (Server) Requirements

The orchestrator connects to your **Wowza server** via SSH to collect metrics.

### Required Tools on Server

#### 1. **sysstat package** (Required - includes pidstat, sar, iostat)
- **Check if installed:**
  ```bash
  ssh user@server "which pidstat sar"
  ```

- **Install if missing:**
  ```bash
  ssh user@server "sudo apt-get update && sudo apt-get install -y sysstat"
  ```

#### 2. **ps, grep, awk** (Required - usually pre-installed)
- Standard Unix tools ✓

#### 3. **ifstat** (Optional - for network monitoring)
- **Check if installed:**
  ```bash
  ssh user@server "which ifstat"
  ```

- **Install if missing (optional):**
  ```bash
  ssh user@server "sudo apt-get install -y ifstat"
  ```
  
- **Fallback:** If not installed, orchestrator uses `sar -n DEV` instead

#### 4. **Wowza Streaming Engine** (Required - obviously!)
- Must be running during tests
- Process name should contain "Wowza" or "WowzaMediaServer"

---

## Quick Setup Checklist

### On Your Local Machine:

```bash
# 1. Check Python
python3 --version
# If missing: sudo apt-get install python3 (or brew install python3)

# 2. Check SSH
which ssh scp
# Should show: /usr/bin/ssh and /usr/bin/scp

# 3. Verify SSH key permissions
chmod 600 ~/path/to/your-key.pem

# 4. Navigate to orchestrator directory
cd orchestrator

# 5. Make scripts executable
chmod +x run_orchestration.sh validate_server.sh

# 6. Validate server setup
./validate_server.sh ~/your-key.pem ubuntu@your-server-ip
```

### On Your Remote Server (one-time):

```bash
# Install sysstat (required)
sudo apt-get update
sudo apt-get install -y sysstat

# Enable sar data collection
sudo systemctl enable sysstat
sudo systemctl start sysstat

# Optional: Install ifstat for better network monitoring
sudo apt-get install -y ifstat

# Verify Wowza is running
ps aux | grep -i wowza | grep java
```

---

## Validation

### Run the Validation Script

```bash
cd orchestrator
./validate_server.sh ~/path/to/key.pem ubuntu@server-ip
```

**Expected Output (Success):**
```
0. Checking local Python3 (required for parsing)...
  ✓ python3 Python 3.10.12

1. Checking monitoring tools availability on server...
  ✓ pidstat
  ✓ sar
  ✓ ps
  ✓ grep
  ✓ awk

2. Checking optional tools...
  ⚠ ifstat not found (will use sar instead)

3. Testing sar network monitoring...
  [Shows network stats]

4. Detecting Wowza process (Method 1: ps + grep)...
  ✓ Found Wowza PID: 12345
  Process details:
  [Shows Wowza process info]

5. Testing pidstat on detected Wowza PID...
  [Shows pidstat output]

✓ Server appears ready for orchestrated load testing
  Wowza PID: 12345
```

---

## Troubleshooting

### Problem: "python3: command not found"

**Solution:**
```bash
# Ubuntu/Debian/WSL
sudo apt-get install python3

# Verify installation
python3 --version
```

---

### Problem: "pidstat: command not found" (on server)

**Solution:**
```bash
ssh user@server "sudo apt-get install -y sysstat"
```

---

### Problem: "WARNING: UNPROTECTED PRIVATE KEY FILE"

**Solution:**
```bash
chmod 600 ~/path/to/your-key.pem
```

---

### Problem: "Wowza process not detected"

**Possible causes:**
1. Wowza is not running
   ```bash
   ssh user@server "sudo systemctl status WowzaStreamingEngine"
   ```

2. Wowza process name is unusual
   ```bash
   # Check what Java processes are running
   ssh user@server "ps aux | grep java"
   ```

3. Need to adjust PID detection pattern in orchestrator

---

### Problem: "Results CSV not generated"

**Causes:**
- Python3 not installed locally → Install Python3
- Parser script errors → Check `orchestrator.log`
- No data collected → Check server logs in `runs/*/server_logs/`

---

## Minimal Setup (Quick Start)

If you just want to test quickly:

**Local:**
```bash
# Must have
python3 --version  # Install if missing

# Test SSH works
ssh -i ~/key.pem ubuntu@server "echo OK"
```

**Server:**
```bash
# Must have
sudo apt-get install -y sysstat

# Start Wowza
sudo systemctl start WowzaStreamingEngine
```

That's the bare minimum to run tests and get results!

---

## Advanced: Running Without Python

If you really can't install Python3 locally:

1. Tests will still run and collect logs
2. Raw logs saved in: `orchestrator/runs/*/`
3. You can manually parse results later:
   ```bash
   # Install Python3, then retroactively parse
   python3 parse_run.py --run-dir runs/RUN_ID --run-id RUN_ID \
     --protocol rtmp --resolution 1080p --video-codec h264 \
     --audio-codec aac --bitrate 3000 --connections 5
   ```

But this is **not recommended** - just install Python3! 🐍
