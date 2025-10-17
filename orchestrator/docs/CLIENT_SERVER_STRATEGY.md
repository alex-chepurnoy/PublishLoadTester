# Client-Server Testing Strategy

## System Architecture

### Your Configuration
```
┌─────────────────────────────────────┐
│  CLIENT (EC2)                       │
│  - 8 cores, 16GB RAM                │
│  - Runs orchestrator                │
│  - Encodes streams with FFmpeg      │
│  - Can handle high load easily      │
└──────────────┬──────────────────────┘
               │
               │ Network (AWS internal)
               │ High bandwidth, low latency
               │
┌──────────────▼──────────────────────┐
│  SERVER (EC2) ← BOTTLENECK          │
│  - 4 cores, 8GB RAM                 │
│  - Runs Wowza/streaming server      │
│  - Processes incoming streams       │
│  - LIMITED RESOURCES                │
└─────────────────────────────────────┘
```

## Why This is Ideal for Test Matrix

### 1. **Client Has Overhead Capacity** ✅
```
Client capacity:
- 8 cores can encode 100+ streams easily
- 16GB RAM plenty for FFmpeg processes
- AWS network bandwidth: 1-10 Gbps depending on instance type
- No client-side bottleneck expected

Implication: Tests won't fail due to CLIENT limits
```

### 2. **Server Limits Are the Target** 🎯
```
Server is what you're testing:
- How many streams can Wowza handle on 4 cores?
- At what point does CPU hit 80%?
- When does heap memory become the limit?
- Which protocol is most efficient?

This is EXACTLY what you want to measure!
```

### 3. **Adaptive Stopping Protects Server** 🛡️
```
Scenario:
1. Test 10 connections @ 1080p → Server CPU: 65%, Heap: 55%
2. Test 20 connections @ 1080p → Server CPU: 82%, Heap: 68%
3. STOP! Skip 50 and 100 connection tests
4. Maximum capacity logged: 10 connections
5. Move to next resolution/protocol

Server never crashes, exact limit discovered!
```

## Expected Results

### Client (8 cores, 16GB) - Will NOT be the bottleneck

| Resolution | Encoding Load | Client CPU | Client RAM | Bottleneck? |
|------------|---------------|------------|------------|-------------|
| 360p × 100 | Low | ~20% | ~4GB | ❌ No |
| 720p × 100 | Medium | ~40% | ~6GB | ❌ No |
| 1080p × 100 | High | ~60% | ~8GB | ❌ No |
| 4K × 100 | Very High | ~85% | ~12GB | ⚠️ Maybe at 100 |

**Conclusion**: Client can handle all connection levels except possibly 100× 4K streams.

### Server (4 cores, 8GB) - THIS is what you're measuring

| Resolution | Bitrate | Expected Max Conn | Server Bottleneck | Test Behavior |
|------------|---------|------------------|-------------------|---------------|
| 360p | 800 kbps | **50-100** | Heap or Network | Tests all 6 levels |
| 720p | 2.5 Mbps | **20-50** | CPU at ~50 | Stops at level 5 |
| 1080p | 4.5 Mbps | **10-20** | CPU at ~20 | Stops at level 4 |
| 4K | 15 Mbps | **5-10** | CPU at ~10 | Stops at level 3 |

### Why These Predictions?

**Wowza on 4 cores processing streams:**
- Each stream = transcoding/packaging/serving
- CPU load depends on what Wowza does:
  - Passthrough only: 1-2% per stream
  - Transcoding: 10-20% per stream
  - Complex processing: 20-30% per stream

**Most likely**: Wowza in passthrough mode
- 360p: ~2% per stream → 40 streams before 80% CPU
- 720p: ~3% per stream → 25 streams before 80% CPU
- 1080p: ~4% per stream → 20 streams before 80% CPU
- 4K: ~8% per stream → 10 streams before 80% CPU

## Perfect Test Matrix Configuration

### ✅ Keep All Connection Levels: 1, 5, 10, 20, 50, 100

**Rationale:**

1. **Client Won't Struggle**
   - 8 cores is plenty for encoding
   - 16GB handles all FFmpeg processes
   - Won't hit client-side limits (except maybe 4K×100)

2. **Server Limits Will Be Discovered**
   - Adaptive stopping kicks in naturally
   - 360p might reach 100 connections
   - 720p likely stops at 50
   - 1080p/4K stop much earlier
   - EXACTLY what test matrix is designed for!

3. **Time Efficiency**
   ```
   Without adaptive stopping:
   72 tests × 15 min = 18 hours (many failures)
   
   With adaptive stopping:
   ~40-50 tests × 15 min = 10-12.5 hours
   (30-32 tests skipped automatically)
   ```

4. **Maximum Value**
   - Discovers exact server capacity per resolution/protocol
   - Creates capacity planning data
   - Shows where to invest (more CPU? more RAM?)
   - Identifies most efficient protocol

## Network Considerations

### AWS Internal Network

```
EC2 to EC2 in same region:
- Bandwidth: Up to 10 Gbps (depending on instance type)
- Latency: <1ms typically
- Reliability: Very high

Maximum theoretical bandwidth needed:
- 100 × 4K @ 15 Mbps = 1.5 Gbps

Conclusion: Network will NOT be bottleneck
```

### Instance Type Check

What EC2 instance types are you using?

| Instance Type | Network | Sufficient for 100×4K? |
|--------------|---------|----------------------|
| t3.medium | Up to 5 Gbps | ✅ Yes |
| t3.large | Up to 5 Gbps | ✅ Yes |
| m5.xlarge | Up to 10 Gbps | ✅ Yes |
| c5.2xlarge | Up to 10 Gbps | ✅ Yes |

## Heap Memory Monitoring - Critical!

### Why Heap Matters on Server

```
Wowza uses Java → Heap is critical

Typical Wowza heap allocation on 8GB RAM:
- Initial heap: 2-4 GB
- Maximum heap: 6 GB (leaving 2GB for OS)

Each stream consumes heap:
- RTMP connection: ~2-5 MB
- RTSP connection: ~1-3 MB  
- SRT connection: ~1-3 MB

100 RTMP streams = 200-500 MB heap
If base heap usage is 4GB:
- 4GB + 500MB = 4.5GB (still safe at 75%)
- But if doing transcoding: much higher!
```

**This is why heap monitoring in Phase 3 is critical!**

You might hit heap limits before CPU limits.

## Updated Recommendations

### 1. **Use Full Connection Array** ✅
```bash
CONNECTIONS=(1 5 10 20 50 100)
```

**Why**: 
- Client can handle it
- Server limits will stop tests naturally
- Gets maximum capacity data
- No time wasted

### 2. **Prioritize Heap Monitoring** 🚨
```bash
Phase 3 becomes CRITICAL:
- Wowza heap might hit 80% before CPU
- Especially with many connections
- Need jstat monitoring working
```

### 3. **Expected Test Matrix Completion**

Based on 4-core server:

```
Resolution: 360p (all protocols)
├─ 1 connection:   ✅ Complete (15 min)
├─ 5 connections:  ✅ Complete (15 min)
├─ 10 connections: ✅ Complete (15 min)
├─ 20 connections: ✅ Complete (15 min)
├─ 50 connections: ✅ Complete (15 min)
└─ 100 connections: ⚠️ May complete or stop
   Total: ~90 min per protocol × 3 = 4.5 hours

Resolution: 720p (all protocols)
├─ 1 connection:   ✅ Complete (15 min)
├─ 5 connections:  ✅ Complete (15 min)
├─ 10 connections: ✅ Complete (15 min)
├─ 20 connections: ✅ Complete (15 min)
├─ 50 connections: 🛑 STOP (CPU/Heap limit)
└─ 100 connections: ⏭️ SKIPPED
   Total: ~60 min per protocol × 3 = 3 hours

Resolution: 1080p (all protocols)
├─ 1 connection:   ✅ Complete (15 min)
├─ 5 connections:  ✅ Complete (15 min)
├─ 10 connections: ✅ Complete (15 min)
├─ 20 connections: 🛑 STOP (CPU limit)
├─ 50 connections: ⏭️ SKIPPED
└─ 100 connections: ⏭️ SKIPPED
   Total: ~45 min per protocol × 3 = 2.25 hours

Resolution: 4K (all protocols)
├─ 1 connection:   ✅ Complete (15 min)
├─ 5 connections:  ✅ Complete (15 min)
├─ 10 connections: 🛑 STOP (CPU limit)
├─ 20 connections: ⏭️ SKIPPED
├─ 50 connections: ⏭️ SKIPPED
└─ 100 connections: ⏭️ SKIPPED
   Total: ~30 min per protocol × 3 = 1.5 hours

TOTAL ESTIMATED TIME: ~11.25 hours
Tests run: ~45 out of 72
Tests skipped: ~27 (saved ~7 hours!)
```

### 4. **Key Metrics to Watch**

#### Server-Side (Critical)
- ✅ CPU usage
- ✅ Heap memory
- ✅ Network throughput
- ✅ Active stream count

#### Client-Side (Monitor but not critical)
- ⚠️ FFmpeg process count
- ⚠️ Encoding CPU usage
- ⚠️ Memory usage

## Test Matrix Value Proposition

### What You'll Learn

1. **Maximum Capacity per Resolution**
   ```
   Example Results:
   - RTMP: 360p=100, 720p=50, 1080p=20, 4K=10
   - RTSP: 360p=100, 720p=45, 1080p=18, 4K=8
   - SRT: 360p=100, 720p=48, 1080p=20, 4K=10
   ```

2. **Bottleneck Identification**
   ```
   - 360p/720p: Heap limited (many connections)
   - 1080p/4K: CPU limited (processing overhead)
   ```

3. **Protocol Efficiency**
   ```
   Which protocol handles most streams?
   Which uses least CPU/Heap?
   Which is most stable under load?
   ```

4. **Capacity Planning**
   ```
   For production:
   - Need 50× 1080p streams?
   - Current: 4 cores = 20 streams max
   - Upgrade: 8 cores = ~40 streams
   - Or: Scale horizontal (2× 4-core servers)
   ```

## Implementation Priority Update

Based on this architecture, I recommend adjusting Phase priorities:

### HIGH PRIORITY (Do First)
1. **Phase 3: Heap Monitoring** 🔥
   - Critical for server bottleneck detection
   - Wowza heap will likely limit before CPU on low resolutions

2. **Phase 4: Adaptive Stopping** 🔥
   - Protects your 4-core server
   - Saves massive amounts of time

3. **Phase 1: Core Configuration** ⚡
   - Quick wins, sets foundation

### MEDIUM PRIORITY
4. **Phase 5: Logging & Reports** 📊
   - Captures capacity data
   - Critical for analysis

5. **Phase 2: Test Order** ⚡
   - Important but not blocking

### LOWER PRIORITY
6. **Phase 6-10**: Polish, documentation, etc.

## Final Recommendation

### ✅ **PROCEED WITH FULL TEST MATRIX**

**Your setup is IDEAL for this approach:**

✅ Client has capacity overhead (8 cores)  
✅ Server is the test target (4 cores)  
✅ Adaptive stopping protects server  
✅ Discovers exact server limits  
✅ Time-efficient (skips impossible tests)  
✅ Generates actionable capacity data  

**Action Items:**

1. ✅ Keep connections: `1, 5, 10, 20, 50, 100`
2. 🔥 Prioritize Phase 3 (Heap Monitoring)
3. 🔥 Prioritize Phase 4 (Adaptive Stopping)
4. 🎯 Expect ~11-12 hours for full run
5. 📊 Expect ~45-50 tests to complete (27-30 skipped)

**This is textbook adaptive load testing!** Your architecture is perfect for discovering server capacity limits without risking crashes.

---

**Created**: October 17, 2025  
**System**: Client (8C/16GB) → Server (4C/8GB)  
**Strategy**: Adaptive threshold testing
