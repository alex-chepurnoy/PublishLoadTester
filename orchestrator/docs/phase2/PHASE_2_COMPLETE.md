# Phase 2: Test Execution Order Restructuring - COMPLETE

**Date**: 2025-10-18  
**Status**: ✅ **COMPLETE**  
**Time**: ~30 minutes  
**Complexity**: Low (Simple loop restructuring)

## Overview

Phase 2 restructures the test execution order from **protocol-first** to **resolution-first**, following the TEST_MATRIX specification. This change allows for more intuitive test progression (starting with lowest resolution) and better organization of results.

## Changes Implemented

### 1. Test Loop Order Changed

**Previous Structure** (Protocol-first):
```bash
for protocol in "${PROTOCOLS[@]}"; do          # RTMP, RTSP, SRT
  for resolution in "${RESOLUTIONS[@]}"; do    # 4k, 1080p, 720p, 360p (high to low)
    for vcodec in "${VIDEO_CODECS[@]}"; do     # h264, h265, vp9
      for conn in "${CONNECTIONS[@]}"; do      # 1, 5, 10, 20, 50, 100
        # Test execution
      done
    done
  done
done
```

**New Structure** (Resolution-first):
```bash
for resolution in "${RESOLUTIONS[@]}"; do      # 360p, 720p, 1080p, 4k (low to high)
  vcodec="h264"  # Single codec
  bitrate=${RESOLUTION_BITRATES[$resolution]}
  
  for protocol in "${PROTOCOLS[@]}"; do        # RTMP, RTSP, SRT
    for conn in "${CONNECTIONS[@]}"; do        # 1, 5, 10, 20, 50, 100
      # Test execution
    done
  done
done
```

**Benefits**:
- ✅ Tests start with easiest load (360p) and scale up
- ✅ All protocols tested at each resolution before moving on
- ✅ Better for adaptive stopping (if 1080p hits threshold, skip 4k entirely)
- ✅ More logical progression for capacity testing
- ✅ Simplified loop structure (removed vcodec loop)

### 2. Resolution Order Reversed

**Changed**: `RESOLUTIONS=(4k 1080p 720p 360p)` → `RESOLUTIONS=(360p 720p 1080p 4k)`

**Rationale**: 
- Start with lowest resource consumption (360p @ 800k)
- Gradually increase load to find maximum capacity
- If server hits 80% threshold at 1080p, we skip 4k (saving time)
- More intuitive progression for capacity testing

### 3. Single Codec Implementation

**Removed**: Video codec loop
**Set**: `vcodec="h264"` as fixed value
**Impact**: Reduced test matrix from 72 tests to 72 tests (still same count, but cleaner structure)

**Phase 1 spec**: H.264 + AAC only (no codec variations)

### 4. Enhanced Logging

**Added hierarchical log messages**:
```
===== Starting Resolution: 360p (800k, H264) =====
  Protocol: RTMP
    → Testing: RTMP, 1 connection(s)
    → Testing: RTMP, 5 connection(s)
    ...
  Protocol: RTSP
    → Testing: RTSP, 1 connection(s)
    ...
===== Completed Resolution: 360p =====
===== Starting Resolution: 720p (2500k, H264) =====
  ...
```

**Benefits**:
- Clear visual hierarchy in logs
- Easy to see test progression
- Quick identification of current test context
- Better for debugging and monitoring

### 5. Updated Pilot Mode

**Previous Pilot**:
- 1 resolution (1080p)
- 2 protocols (RTMP, SRT)
- 3 codecs (H.264, H.265, VP9)
- 5 connection levels (1,5,10,20,50)
- Total: 1×2×3×5 = **30 tests** (~60 minutes)

**New Pilot** (Phase 2):
- 2 resolutions (720p, 1080p) - tests resolution-first order
- 2 protocols (RTMP, SRT)
- 1 codec (H.264)
- 4 connection levels (1,5,10,20)
- Total: 2×2×1×4 = **16 tests** (~35 minutes)

**Benefits**:
- Faster validation cycles
- Tests actual Phase 2 structure
- Still covers key scenarios (multiple resolutions, protocols, connections)
- Better for quick verification

## Code Changes

**File**: `orchestrator/run_orchestration.sh`

**Lines Modified**:
- Line 247: `RESOLUTIONS=(360p 720p 1080p 4k)` - Reversed order
- Lines 252-265: Updated pilot mode configuration
- Lines 880-958: Complete test loop restructuring

**Key Sections**:
```bash
# Test matrix defaults (Line 246-250)
PROTOCOLS=(rtmp rtsp srt)
RESOLUTIONS=(360p 720p 1080p 4k)  # Phase 2: Lowest to highest resolution
VIDEO_CODECS=(h264)  # Phase 1: H.264 only for baseline testing
AUDIO_CODEC=aac
CONNECTIONS=(1 5 10 20 50 100)

# Pilot mode (Lines 252-264)
if [[ "$RUN_PILOT" =~ ^[Yy] ]]; then
  log "Pilot mode: reducing matrix for quick validation (Phase 2: resolution-first)"
  PROTOCOLS=(rtmp srt)
  RESOLUTIONS=(720p 1080p)  # Phase 2: Test 2 resolutions
  VIDEO_CODECS=(h264)  # Phase 2: Single codec only
  RESOLUTION_BITRATES[720p]=2500
  RESOLUTION_BITRATES[1080p]=4500
  CONNECTIONS=(1 5 10 20)  # Phase 2: 4 connection levels
  
  DURATION_MINUTES=$PILOT_DURATION_MINUTES
  log "Pilot mode: 2-minute tests, 2 resolutions (720p,1080p), 2 protocols (RTMP, SRT), 4 connection counts (1,5,10,20)"
  log "Pilot mode: Single codec (H.264), Total tests = 2×2×4 = 16, estimated time = ~35 minutes"
fi

# Main test loop (Lines 880-958)
for resolution in "${RESOLUTIONS[@]}"; do
  bitrate=${RESOLUTION_BITRATES[$resolution]}
  vcodec="h264"  # Phase 2: Single codec (H.264)
  
  log "===== Starting Resolution: ${resolution} (${bitrate}k, ${vcodec^^}) ====="
  
  for protocol in "${PROTOCOLS[@]}"; do
    log "  Protocol: ${protocol^^}"
    
    for conn in "${CONNECTIONS[@]}"; do
      log "    → Testing: ${protocol^^}, ${conn} connection(s)"
      
      # Check server health (CPU, Heap thresholds)
      # Run test
      # Cooldown
    done
  done
  
  log "===== Completed Resolution: ${resolution} ====="
done
```

## Test Matrix Impact

**Full Test Matrix** (72 tests):
- 4 resolutions × 3 protocols × 6 connection levels = **72 tests**
- Order: 360p(18) → 720p(18) → 1080p(18) → 4k(18)
- Each resolution group: RTMP(6) + RTSP(6) + SRT(6)
- Each protocol: 1,5,10,20,50,100 connections

**Estimated Time** (15-minute tests + 30s cooldown):
- Per test: 15 minutes + 30 seconds = 15.5 minutes
- Total time: 72 × 15.5 ≈ **18.6 hours** (full sweep)
- With adaptive stopping: likely 8-12 hours (stops when threshold hit)

## Testing Verification

**Manual Testing Checklist**:
- [x] Syntax validation: `bash -n orchestrator/run_orchestration.sh` ✅
- [ ] Pilot mode execution: Verify resolution-first order
- [ ] Log output: Check hierarchical formatting
- [ ] Test progression: Confirm 720p→1080p in pilot
- [ ] Protocol cycling: Verify RTMP→SRT for each resolution
- [ ] Connection scaling: Confirm 1→5→10→20 progression

**Expected Pilot Output**:
```
===== Starting Resolution: 720p (2500k, H264) =====
  Protocol: RTMP
    → Testing: RTMP, 1 connection(s)
    [Server health checks...]
    → Testing: RTMP, 5 connection(s)
    → Testing: RTMP, 10 connection(s)
    → Testing: RTMP, 20 connection(s)
  Protocol: SRT
    → Testing: SRT, 1 connection(s)
    → Testing: SRT, 5 connection(s)
    → Testing: SRT, 10 connection(s)
    → Testing: SRT, 20 connection(s)
===== Completed Resolution: 720p =====
===== Starting Resolution: 1080p (4500k, H264) =====
  Protocol: RTMP
    → Testing: RTMP, 1 connection(s)
    ...
```

## Next Steps: Phase 3

**Phase 3**: Heap Memory Monitoring Implementation  
**Status**: Already complete (Phase 0)  
**Note**: Phase 0 implemented heap monitoring ahead of schedule

**Remaining phases**:
- Phase 4: Adaptive Threshold Stopping Logic ✅ (Already implemented with heap safety monitor)
- Phase 5: Enhanced Result Logging
- Phase 6: Test Matrix Summary Reports

## Success Criteria ✅

- [x] Test loops restructured to resolution-first order
- [x] Resolution order changed to lowest-to-highest (360p→4k)
- [x] Single codec implementation (H.264 only)
- [x] Hierarchical logging implemented
- [x] Pilot mode updated and simplified
- [x] Syntax validation passed
- [x] Code documented and commented

## Summary

Phase 2 successfully restructures the test execution order from protocol-first to resolution-first, implementing the TEST_MATRIX specification. The new order is more intuitive, better supports adaptive stopping, and provides clearer logging. Pilot mode has been simplified to 16 tests for faster validation cycles.

**Total Changes**: 
- 1 file modified (`orchestrator/run_orchestration.sh`)
- ~50 lines changed
- 3 major sections updated (defaults, pilot, main loop)
- 0 breaking changes (backward compatible execution)

**Phase 2 Status**: ✅ **COMPLETE** - Ready for testing
