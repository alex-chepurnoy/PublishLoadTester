# Orchestrator Documentation

This directory contains documentation specific to the orchestration system for automated load testing.

## Overview

The orchestrator is a comprehensive tool to run `stream_load_tester.sh` experiments from a single control machine while SSHing into the streaming server to start/stop monitors and fetch logs. It implements an adaptive testing approach based on server resource utilization.

## Core Documentation

- **[TEST_MATRIX.md](TEST_MATRIX.md)** - Complete test matrix specification with 72 tests covering all protocols, resolutions, and connection levels
- **[IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md)** - 11-phase implementation plan to build TEST_MATRIX features
- **[IMPLEMENTATION_SUMMARY.md](IMPLEMENTATION_SUMMARY.md)** - Quick overview of implementation phases
- **[SETUP_REQUIREMENTS.md](SETUP_REQUIREMENTS.md)** - Requirements and setup instructions for orchestration
- **[PILOT_MODE.md](PILOT_MODE.md)** - Pilot mode for testing orchestration functionality

## Phase 0 - Monitoring Infrastructure (✅ COMPLETED)

- **[PHASE_0_COMPLETE.md](PHASE_0_COMPLETE.md)** - Complete Phase 0 implementation summary
- **[PHASE_0_QUICKREF.md](PHASE_0_QUICKREF.md)** - Quick reference for monitoring commands
- **[PHASE_0_SUMMARY.md](PHASE_0_SUMMARY.md)** - Detailed Phase 0 design and requirements
- **[JCMD_VS_JSTAT.md](JCMD_VS_JSTAT.md)** - Comparison of Java heap monitoring tools

### What's New in Phase 0

✅ **4 New Monitoring Functions:**
- `get_server_heap()` - Java heap monitoring with jcmd→jstat→jmap fallback
- `get_server_memory()` - System memory usage percentage
- `get_server_network()` - Network throughput in Mbps
- `check_server_status()` - Unified status check (CPU|HEAP|MEM|NET)

✅ **Remote Monitoring Script:**
- `remote_monitor.sh` - Logs all metrics every 5 seconds on server
- Auto-deployed and started with each test run
- Creates CSV logs: `TIMESTAMP,CPU_PCT,HEAP_PCT,MEM_PCT,NET_MBPS,WOWZA_PID`

✅ **Server Validation:**
- `validate_server.sh` - Pre-flight check for all monitoring tools
- Verifies jcmd, jstat, jmap, pidstat, sar, ifstat availability
- Tests Wowza PID detection and heap monitoring

✅ **Adaptive Stopping Enhanced:**
- Now checks both CPU AND Heap thresholds
- Stops tests if CPU >= 80% OR Heap >= 80%
- Logs all 4 metrics before each test

## Architecture Documentation

- **[HARDWARE_PROFILES.md](HARDWARE_PROFILES.md)** - Hardware-specific test profiles
- **[CLIENT_SERVER_STRATEGY.md](CLIENT_SERVER_STRATEGY.md)** - Client/server architecture strategy

## Features & Capabilities

- **[PYTHON_DEPENDENCY_FLOW.md](PYTHON_DEPENDENCY_FLOW.md)** - Python dependency management flow
- **[PYTHON_CHECK_STATUS.md](PYTHON_CHECK_STATUS.md)** - Python environment status checking
- **[DATA_ANALYSIS.md](DATA_ANALYSIS.md)** - Data analysis and results processing

## Development & Review

- **[FIXES_SUMMARY.md](FIXES_SUMMARY.md)** - Summary of orchestrator-specific fixes
- **[REVIEW.md](REVIEW.md)** - Code review notes and improvements

## Test Matrix Overview

The orchestrator implements an adaptive testing approach with:

- **3 Protocols**: RTMP, RTSP, SRT
- **4 Resolutions**: 360p, 720p, 1080p, 4K
- **6 Connection Levels**: 1, 5, 10, 20, 50, 100
- **Adaptive Testing**: Automatically stops when server reaches 80% CPU or Heap
- **72 Total Tests**: ~18 hours maximum duration (8-12 hours actual)

See [TEST_MATRIX.md](TEST_MATRIX.md) for complete details.

## Quick Start

Files:
- `run_orchestration.sh` - Main bash orchestrator with interactive prompts and automated test matrix execution
- `parse_run.py` - Lightweight parser that aggregates `pidstat`, `ifstat`, and `sar` logs and appends a `results.csv` per run set

### Setup

1. Ensure you can SSH from the control machine to the streaming server (key-based auth is recommended). Place the `.pem` key locally.

2. Make the orchestrator executable and run it from the repo root or orchestrator folder:

```bash
chmod +x run_orchestration.sh
./run_orchestration.sh
```

3. The orchestrator will prompt for the key path, server IP, app name, and stream prefix. It will then execute the test sweep according to the test matrix and store per-run logs in `orchestrator/runs/`.

### Notes

- The orchestrator uses `pidstat`, `sar`, and `ifstat` on the remote server. If these utilities are not present, install `sysstat` and `ifstat` on the streaming server.
- Adaptive testing automatically stops tests when server resources reach 80% CPU or heap memory utilization
- Results are logged with maximum capacity information for each protocol/resolution combination

## Related Documentation

For main load tester documentation, see: [`docs/`](../../docs/README.md)

---

**Orchestrator Main**: [../run_orchestration.sh](../run_orchestration.sh)
