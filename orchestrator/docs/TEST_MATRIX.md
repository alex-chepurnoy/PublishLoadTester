# Load Test Matrix Specification

## Overview

This document defines the comprehensive test matrix for the Stream Load Tester. The tests are designed to determine the maximum capacity of streaming servers across different protocols, resolutions, and connection loads.

## Test Configuration

### Fixed Parameters
- **Video Codec**: H.264 (libx264)
- **Audio Codec**: AAC
- **Frame Rate**: 30 fps
- **GOP Size**: 60 frames (2-second keyframe interval)
- **FFmpeg Preset**: veryfast
- **Test Duration**: 15 minutes per test run
- **Cool-down Period**: 30 seconds between tests

### Variable Parameters
- **Protocols**: 3 (RTMP, RTSP, SRT)
- **Resolutions**: 4 (360p, 720p, 1080p, 4K)
- **Connection Levels**: 6 (1, 5, 10, 20, 50, 100)

### Server Configuration
- **Server IP**: Provided at runtime via orchestration script
- **Stream Names**: User input required
- **Application Names**: User input required
- **Endpoints**: Constructed as `protocol://server_ip:port/application/stream_name`

## Resolution & Bitrate Mapping

| Resolution | Dimensions | Video Bitrate | Audio Bitrate | Total Bitrate | Use Case |
|------------|------------|---------------|---------------|---------------|----------|
| 360p       | 640×360    | 800 kbps      | 96 kbps       | ~900 kbps     | Mobile/Low bandwidth |
| 720p       | 1280×720   | 2,500 kbps    | 128 kbps      | ~2,630 kbps   | HD streaming |
| 1080p      | 1920×1080  | 4,500 kbps    | 128 kbps      | ~4,630 kbps   | Full HD streaming |
| 4K         | 3840×2160  | 15,000 kbps   | 192 kbps      | ~15,190 kbps  | Ultra HD streaming |

## Test Execution Order

Tests are executed in the following order:

1. **By Resolution** (ascending): 360p → 720p → 1080p → 4K
2. **By Protocol** (for each resolution): RTMP → RTSP → SRT
3. **By Connection Count** (for each protocol/resolution): 1 → 5 → 10 → 20 → 50 → 100

### Example Execution Sequence
```
Test 1:  RTMP, 360p, 1 connection
Test 2:  RTMP, 360p, 5 connections
Test 3:  RTMP, 360p, 10 connections
...
Test 6:  RTMP, 360p, 100 connections
Test 7:  RTSP, 360p, 1 connection
...
Test 18: SRT, 360p, 100 connections
Test 19: RTMP, 720p, 1 connection
...
```

## Adaptive Testing & Stop Conditions

### Server Resource Thresholds

Tests automatically stop for a specific resolution when either threshold is reached:

- **CPU Usage**: ≥ 80%
- **Heap Memory**: ≥ 80%

### Behavior When Threshold Reached

1. **Current Test**: Immediately stops
2. **Remaining Tests**: All remaining connection levels for that protocol/resolution are skipped
3. **Logging**: Maximum capacity is recorded in logs
4. **Next Action**: Moves to next protocol or next resolution
5. **Result**: Last successful connection count is recorded as maximum capacity

### Example Scenario

```
RTMP, 720p, 1 connection   → Success (CPU: 5%, Heap: 10%)
RTMP, 720p, 5 connections  → Success (CPU: 20%, Heap: 25%)
RTMP, 720p, 10 connections → Success (CPU: 40%, Heap: 45%)
RTMP, 720p, 20 connections → Success (CPU: 65%, Heap: 60%)
RTMP, 720p, 50 connections → STOPPED (CPU: 82%, Heap: 70%)

Result: Maximum capacity for RTMP 720p = 20 connections
Action: Skip 100 connections test, move to RTSP 720p
```

## Complete Test Matrix

### RTMP Protocol Tests (Tests 1-24)

| Test # | Resolution | Connections | Video Bitrate | Audio Bitrate | Duration | Expected Bandwidth |
|--------|------------|-------------|---------------|---------------|----------|-------------------|
| 1      | 360p       | 1           | 800 kbps      | 96 kbps       | 15 min   | ~0.9 Mbps         |
| 2      | 360p       | 5           | 800 kbps      | 96 kbps       | 15 min   | ~4.5 Mbps         |
| 3      | 360p       | 10          | 800 kbps      | 96 kbps       | 15 min   | ~9 Mbps           |
| 4      | 360p       | 20          | 800 kbps      | 96 kbps       | 15 min   | ~18 Mbps          |
| 5      | 360p       | 50          | 800 kbps      | 96 kbps       | 15 min   | ~45 Mbps          |
| 6      | 360p       | 100         | 800 kbps      | 96 kbps       | 15 min   | ~90 Mbps          |
| 7      | 720p       | 1           | 2,500 kbps    | 128 kbps      | 15 min   | ~2.6 Mbps         |
| 8      | 720p       | 5           | 2,500 kbps    | 128 kbps      | 15 min   | ~13 Mbps          |
| 9      | 720p       | 10          | 2,500 kbps    | 128 kbps      | 15 min   | ~26 Mbps          |
| 10     | 720p       | 20          | 2,500 kbps    | 128 kbps      | 15 min   | ~53 Mbps          |
| 11     | 720p       | 50          | 2,500 kbps    | 128 kbps      | 15 min   | ~131 Mbps         |
| 12     | 720p       | 100         | 2,500 kbps    | 128 kbps      | 15 min   | ~263 Mbps         |
| 13     | 1080p      | 1           | 4,500 kbps    | 128 kbps      | 15 min   | ~4.6 Mbps         |
| 14     | 1080p      | 5           | 4,500 kbps    | 128 kbps      | 15 min   | ~23 Mbps          |
| 15     | 1080p      | 10          | 4,500 kbps    | 128 kbps      | 15 min   | ~46 Mbps          |
| 16     | 1080p      | 20          | 4,500 kbps    | 128 kbps      | 15 min   | ~93 Mbps          |
| 17     | 1080p      | 50          | 4,500 kbps    | 128 kbps      | 15 min   | ~231 Mbps         |
| 18     | 1080p      | 100         | 4,500 kbps    | 128 kbps      | 15 min   | ~463 Mbps         |
| 19     | 4K         | 1           | 15,000 kbps   | 192 kbps      | 15 min   | ~15.2 Mbps        |
| 20     | 4K         | 5           | 15,000 kbps   | 192 kbps      | 15 min   | ~76 Mbps          |
| 21     | 4K         | 10          | 15,000 kbps   | 192 kbps      | 15 min   | ~152 Mbps         |
| 22     | 4K         | 20          | 15,000 kbps   | 192 kbps      | 15 min   | ~304 Mbps         |
| 23     | 4K         | 50          | 15,000 kbps   | 192 kbps      | 15 min   | ~760 Mbps         |
| 24     | 4K         | 100         | 15,000 kbps   | 192 kbps      | 15 min   | ~1.5 Gbps         |

### RTSP Protocol Tests (Tests 25-48)

| Test # | Resolution | Connections | Video Bitrate | Audio Bitrate | Duration | Expected Bandwidth |
|--------|------------|-------------|---------------|---------------|----------|-------------------|
| 25     | 360p       | 1           | 800 kbps      | 96 kbps       | 15 min   | ~0.9 Mbps         |
| 26     | 360p       | 5           | 800 kbps      | 96 kbps       | 15 min   | ~4.5 Mbps         |
| 27     | 360p       | 10          | 800 kbps      | 96 kbps       | 15 min   | ~9 Mbps           |
| 28     | 360p       | 20          | 800 kbps      | 96 kbps       | 15 min   | ~18 Mbps          |
| 29     | 360p       | 50          | 800 kbps      | 96 kbps       | 15 min   | ~45 Mbps          |
| 30     | 360p       | 100         | 800 kbps      | 96 kbps       | 15 min   | ~90 Mbps          |
| 31     | 720p       | 1           | 2,500 kbps    | 128 kbps      | 15 min   | ~2.6 Mbps         |
| 32     | 720p       | 5           | 2,500 kbps    | 128 kbps      | 15 min   | ~13 Mbps          |
| 33     | 720p       | 10          | 2,500 kbps    | 128 kbps      | 15 min   | ~26 Mbps          |
| 34     | 720p       | 20          | 2,500 kbps    | 128 kbps      | 15 min   | ~53 Mbps          |
| 35     | 720p       | 50          | 2,500 kbps    | 128 kbps      | 15 min   | ~131 Mbps         |
| 36     | 720p       | 100         | 2,500 kbps    | 128 kbps      | 15 min   | ~263 Mbps         |
| 37     | 1080p      | 1           | 4,500 kbps    | 128 kbps      | 15 min   | ~4.6 Mbps         |
| 38     | 1080p      | 5           | 4,500 kbps    | 128 kbps      | 15 min   | ~23 Mbps          |
| 39     | 1080p      | 10          | 4,500 kbps    | 128 kbps      | 15 min   | ~46 Mbps          |
| 40     | 1080p      | 20          | 4,500 kbps    | 128 kbps      | 15 min   | ~93 Mbps          |
| 41     | 1080p      | 50          | 4,500 kbps    | 128 kbps      | 15 min   | ~231 Mbps         |
| 42     | 1080p      | 100         | 4,500 kbps    | 128 kbps      | 15 min   | ~463 Mbps         |
| 43     | 4K         | 1           | 15,000 kbps   | 192 kbps      | 15 min   | ~15.2 Mbps        |
| 44     | 4K         | 5           | 15,000 kbps   | 192 kbps      | 15 min   | ~76 Mbps          |
| 45     | 4K         | 10          | 15,000 kbps   | 192 kbps      | 15 min   | ~152 Mbps         |
| 46     | 4K         | 20          | 15,000 kbps   | 192 kbps      | 15 min   | ~304 Mbps         |
| 47     | 4K         | 50          | 15,000 kbps   | 192 kbps      | 15 min   | ~760 Mbps         |
| 48     | 4K         | 100         | 15,000 kbps   | 192 kbps      | 15 min   | ~1.5 Gbps         |

### SRT Protocol Tests (Tests 49-72)

| Test # | Resolution | Connections | Video Bitrate | Audio Bitrate | Duration | Expected Bandwidth |
|--------|------------|-------------|---------------|---------------|----------|-------------------|
| 49     | 360p       | 1           | 800 kbps      | 96 kbps       | 15 min   | ~0.9 Mbps         |
| 50     | 360p       | 5           | 800 kbps      | 96 kbps       | 15 min   | ~4.5 Mbps         |
| 51     | 360p       | 10          | 800 kbps      | 96 kbps       | 15 min   | ~9 Mbps           |
| 52     | 360p       | 20          | 800 kbps      | 96 kbps       | 15 min   | ~18 Mbps          |
| 53     | 360p       | 50          | 800 kbps      | 96 kbps       | 15 min   | ~45 Mbps          |
| 54     | 360p       | 100         | 800 kbps      | 96 kbps       | 15 min   | ~90 Mbps          |
| 55     | 720p       | 1           | 2,500 kbps    | 128 kbps      | 15 min   | ~2.6 Mbps         |
| 56     | 720p       | 5           | 2,500 kbps    | 128 kbps      | 15 min   | ~13 Mbps          |
| 57     | 720p       | 10          | 2,500 kbps    | 128 kbps      | 15 min   | ~26 Mbps          |
| 58     | 720p       | 20          | 2,500 kbps    | 128 kbps      | 15 min   | ~53 Mbps          |
| 59     | 720p       | 50          | 2,500 kbps    | 128 kbps      | 15 min   | ~131 Mbps         |
| 60     | 720p       | 100         | 2,500 kbps    | 128 kbps      | 15 min   | ~263 Mbps         |
| 61     | 1080p      | 1           | 4,500 kbps    | 128 kbps      | 15 min   | ~4.6 Mbps         |
| 62     | 1080p      | 5           | 4,500 kbps    | 128 kbps      | 15 min   | ~23 Mbps          |
| 63     | 1080p      | 10          | 4,500 kbps    | 128 kbps      | 15 min   | ~46 Mbps          |
| 64     | 1080p      | 20          | 4,500 kbps    | 128 kbps      | 15 min   | ~93 Mbps          |
| 65     | 1080p      | 50          | 4,500 kbps    | 128 kbps      | 15 min   | ~231 Mbps         |
| 66     | 1080p      | 100         | 4,500 kbps    | 128 kbps      | 15 min   | ~463 Mbps         |
| 67     | 4K         | 1           | 15,000 kbps   | 192 kbps      | 15 min   | ~15.2 Mbps        |
| 68     | 4K         | 5           | 15,000 kbps   | 192 kbps      | 15 min   | ~76 Mbps          |
| 69     | 4K         | 10          | 15,000 kbps   | 192 kbps      | 15 min   | ~152 Mbps         |
| 70     | 4K         | 20          | 15,000 kbps   | 192 kbps      | 15 min   | ~304 Mbps         |
| 71     | 4K         | 50          | 15,000 kbps   | 192 kbps      | 15 min   | ~760 Mbps         |
| 72     | 4K         | 100         | 15,000 kbps   | 192 kbps      | 15 min   | ~1.5 Gbps         |

## Test Timeline & Duration

### Maximum Possible Duration
- **Total Tests**: 72
- **Test Duration**: 15 minutes each
- **Cool-down**: 30 seconds between tests
- **Maximum Time**: (72 × 15 min) + (71 × 0.5 min) = 1,080 + 35.5 = **1,115.5 minutes (~18.6 hours)**

### Expected Actual Duration
Due to adaptive testing (stopping at 80% thresholds), actual duration will likely be significantly shorter:
- **Low Resolutions (360p, 720p)**: May reach 100 connections before hitting limits
- **High Resolutions (1080p, 4K)**: Likely to hit limits at 20-50 connections
- **Estimated Actual Time**: 8-12 hours depending on server capacity

### Per-Resolution Breakdown
| Resolution | Tests per Protocol | Total Tests | Max Duration | With Cool-down |
|------------|-------------------|-------------|--------------|----------------|
| 360p       | 6                 | 18          | 270 min      | 278.5 min      |
| 720p       | 6                 | 18          | 270 min      | 278.5 min      |
| 1080p      | 6                 | 18          | 270 min      | 278.5 min      |
| 4K         | 6                 | 18          | 270 min      | 278.5 min      |

## Monitoring & Metrics

### Server-Side Monitoring (Required)
- **CPU Usage**: Real-time monitoring, 80% threshold
- **Heap Memory**: Real-time monitoring, 80% threshold
- **Network Bandwidth**: Total ingress traffic
- **Active Connections**: Number of active streams

### Client-Side Monitoring
- **FFmpeg Process Status**: Running/Failed
- **Stream Stability**: Continuous publishing
- **Encoding Performance**: Frame rate consistency
- **Error Rate**: Connection failures

### Test Success Criteria
A test is considered successful if:
1. All connections establish successfully
2. Streams publish for full 15-minute duration
3. Server CPU < 80%
4. Server Heap < 80%
5. No encoding errors or stream failures

## Logging Requirements

### Per-Test Logs
Each test must log:
```
Test Number: [1-72]
Timestamp: [Start/End times]
Protocol: [RTMP/RTSP/SRT]
Resolution: [360p/720p/1080p/4K]
Connections: [1/5/10/20/50/100]
Video Bitrate: [kbps]
Audio Bitrate: [kbps]
Duration: [actual duration in minutes]
Server URL: [full endpoint]
Stream Names: [list of all stream names]

Server Metrics:
  - Initial CPU: [%]
  - Peak CPU: [%]
  - Final CPU: [%]
  - Initial Heap: [%]
  - Peak Heap: [%]
  - Final Heap: [%]
  - Peak Bandwidth: [Mbps]

Result: [SUCCESS/STOPPED/FAILED]
Reason: [if stopped: threshold reached, if failed: error description]
Max Capacity Reached: [Yes/No]
```

### Summary Report
After all tests complete, generate summary:
```
=== Load Test Summary Report ===
Date: [timestamp]
Server IP: [IP address]
Total Tests Run: [X/72]
Total Duration: [hours:minutes]

Maximum Capacities:
RTMP:
  - 360p: [X] connections (CPU: Y%, Heap: Z%)
  - 720p: [X] connections (CPU: Y%, Heap: Z%)
  - 1080p: [X] connections (CPU: Y%, Heap: Z%)
  - 4K: [X] connections (CPU: Y%, Heap: Z%)

RTSP:
  - 360p: [X] connections (CPU: Y%, Heap: Z%)
  - 720p: [X] connections (CPU: Y%, Heap: Z%)
  - 1080p: [X] connections (CPU: Y%, Heap: Z%)
  - 4K: [X] connections (CPU: Y%, Heap: Z%)

SRT:
  - 360p: [X] connections (CPU: Y%, Heap: Z%)
  - 720p: [X] connections (CPU: Y%, Heap: Z%)
  - 1080p: [X] connections (CPU: Y%, Heap: Z%)
  - 4K: [X] connections (CPU: Y%, Heap: Z%)

Total Bandwidth Achieved:
  - RTMP: [Mbps]
  - RTSP: [Mbps]
  - SRT: [Mbps]
```

## Usage with Orchestration Script

### Required User Inputs
```bash
# Server Configuration
Server IP: [e.g., 192.168.1.100]
RTMP Port: [default: 1935]
RTSP Port: [default: 554]
SRT Port: [default: 9999]

# Application Names
RTMP Application: [e.g., live]
RTSP Application: [e.g., stream]
SRT Application: [e.g., live]

# Stream Naming
Base Stream Name: [e.g., test]
# Results in: test001, test002, test003, etc.
```

### Example Orchestration Command
```bash
./run_orchestration.sh \
  --server-ip 192.168.1.100 \
  --rtmp-app live \
  --rtsp-app stream \
  --srt-app live \
  --stream-name loadtest \
  --test-matrix TEST_MATRIX.md
```

## FFmpeg Command Template

For reference, each stream will use parameters similar to:
```bash
ffmpeg -re -f lavfi -i testsrc=size=WxH:rate=30 \
  -f lavfi -i sine=frequency=1000:sample_rate=48000 \
  -c:v libx264 -preset veryfast -b:v [BITRATE]k \
  -g 60 -keyint_min 60 -sc_threshold 0 \
  -c:a aac -b:a [AUDIO_BITRATE]k -ar 48000 \
  -f flv rtmp://[SERVER]/[APP]/[STREAM]
```

Where:
- `WxH`: Resolution dimensions (e.g., 1920x1080)
- `[BITRATE]`: Video bitrate in kbps (e.g., 4500)
- `[AUDIO_BITRATE]`: Audio bitrate (e.g., 128)
- `[SERVER]`, `[APP]`, `[STREAM]`: User-provided values

## Notes & Recommendations

1. **Network Capacity**: Ensure test client has sufficient network bandwidth
   - Minimum 2 Gbps recommended for full 4K/100 connection tests
   
2. **Client Resources**: Test client machine should have:
   - Multi-core CPU (8+ cores recommended)
   - 16+ GB RAM
   - Fast network interface (1 Gbps minimum)

3. **Server Monitoring**: Set up proper monitoring on server before starting tests
   - Use tools like `top`, `htop`, or monitoring APIs
   - Ensure CPU and heap metrics are accessible in real-time

4. **Test Interruption**: If tests must be interrupted:
   - All FFmpeg processes should be cleanly terminated
   - Current test results should be saved
   - Resume capability should allow starting from next test

5. **Result Analysis**: After completion, analyze:
   - Which protocol performs best at each resolution
   - Where bottlenecks occur (CPU vs Heap)
   - Bandwidth limits vs processing limits
   - Optimal resolution/connection combinations

---

**Last Updated**: October 17, 2025
**Version**: 1.0
