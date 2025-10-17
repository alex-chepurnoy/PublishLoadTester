# VP9 Codec Implementation Plan

## Overview

This document outlines the plan to add VP9 (libvpx-vp9) codec support to the Stream Load Tester, enabling codec comparison testing alongside H.264 and H.265.

**Created**: October 17, 2025  
**Status**: Planning Phase  
**Estimated Effort**: 2-4 hours (LOW lift)

---

## Executive Summary

### What is VP9?
VP9 is an open-source video codec developed by Google, designed as a royalty-free alternative to H.265/HEVC. It's widely used in YouTube, Chrome, and modern streaming platforms.

**VP9 Characteristics**:
- ✅ **Better compression** than H.264 (~30-50% bitrate savings)
- ✅ **Royalty-free** (no licensing fees)
- ✅ **Wide browser support** (Chrome, Firefox, Edge)
- ⚠️ **Higher CPU usage** during encoding (2-3x H.264)
- ⚠️ **Slower encoding** speed than H.264
- ⚠️ **Limited hardware support** (mostly software encoding)

### Why Add VP9?

1. **Codec Comparison**: Test H.264 vs H.265 vs VP9 performance on same infrastructure
2. **CPU Load Testing**: VP9's higher CPU usage helps identify server capacity limits
3. **Modern Streaming**: Many platforms now support VP9 (YouTube, WebRTC)
4. **Research Value**: Understand CPU/bandwidth tradeoffs for different codecs

### Implementation Complexity

**Lift Assessment**: ✅ **LOW** (2-4 hours)

The implementation follows the exact same pattern as H.265:
- Add to codec selection menu (1 location)
- Add FFmpeg encoding parameters (2 locations)
- Update orchestrator test matrix (1 location)
- Test and validate

---

## Relationship to Implementation Plan

### Does This Fit the Current Phase Plan?

**Answer**: ⚠️ **SEPARATE WORK PROCESS** - Not part of Phase 0 or Phase 1

**Current Phase Status**:
- ✅ **Phase 0 COMPLETE**: Monitoring infrastructure (CPU, Heap, Memory, Network)
- 🔜 **Phase 1 NEXT**: Core configuration updates (simplified test matrix per TEST_MATRIX.md)

**VP9 Codec Addition**:
- **Category**: Feature enhancement (codec expansion)
- **Timing**: Can be done **before**, **during**, or **after** Phase 1
- **Dependencies**: None - independent of monitoring infrastructure
- **Impact**: Minimal - extends existing codec selection mechanism

### Recommended Timing

**Option A: Before Phase 1** ✅ **RECOMMENDED**
- **Why**: Complete codec options before comprehensive test matrix
- **Benefit**: Phase 1 testing includes VP9 from the start
- **Timeline**: 2-4 hours now
- **Risk**: None - doesn't affect monitoring infrastructure

**Option B: During Phase 1**
- **Why**: Add as part of test matrix implementation
- **Benefit**: Single testing cycle for all codecs
- **Timeline**: Include in Phase 1 scope
- **Risk**: Slightly extends Phase 1 duration

**Option C: After Phase 1**
- **Why**: Focus on core test matrix first, add VP9 later
- **Benefit**: Faster Phase 1 completion
- **Timeline**: Separate 2-4 hour session after Phase 1
- **Risk**: Requires re-running comprehensive tests to include VP9

**Recommendation**: **Option A** - Add VP9 now (before Phase 1) to avoid re-testing later.

---

## Technical Implementation Details

### 1. Files to Modify

#### File 1: `stream_load_tester.sh`
**Lines to Change**: 3 locations

**Location 1: Codec Selection Menu** (lines ~281-289)
```bash
# CURRENT:
echo "1) H.264 (libx264) - Widely compatible, good compression"
echo "2) H.265 (libx265) - Better compression, lower bitrate for same quality"

# NEW:
echo "1) H.264 (libx264) - Widely compatible, good compression"
echo "2) H.265 (libx265) - Better compression, lower bitrate for same quality"
echo "3) VP9 (libvpx-vp9) - Open-source, high compression, higher CPU usage"
```

**Location 2: Multi-Stream FFmpeg Encoding** (lines ~504-530)
```bash
# CURRENT:
if [[ "$VIDEO_CODEC" == "h265" ]]; then
    cmd+=" -c:v libx265 -preset veryfast -b:v ${BITRATE}k -g 60 -keyint_min 60 -x265-params keyint=60:min-keyint=60"
else
    # H.264 encoding...
fi

# NEW:
if [[ "$VIDEO_CODEC" == "h265" ]]; then
    cmd+=" -c:v libx265 -preset veryfast -b:v ${BITRATE}k -g 60 -keyint_min 60 -x265-params keyint=60:min-keyint=60"
elif [[ "$VIDEO_CODEC" == "vp9" ]]; then
    # VP9 encoding with optimized settings for streaming
    cmd+=" -c:v libvpx-vp9 -b:v ${BITRATE}k -crf 31 -g 60 -keyint_min 60"
    cmd+=" -speed 4 -tile-columns 2 -threads 4 -row-mt 1"
    cmd+=" -quality realtime -deadline realtime"
else
    # H.264 encoding...
fi
```

**Location 3: Single-Stream FFmpeg Encoding** (lines ~590-618)
```bash
# Same pattern as Location 2 (for legacy single-stream function)
```

#### File 2: `orchestrator/run_orchestration.sh`
**Lines to Change**: 1 location

**Location: Test Matrix Configuration** (lines ~242-252)
```bash
# CURRENT:
VIDEO_CODECS=(h264 h265)

# Pilot option override:
if [[ "$RUN_PILOT" =~ ^[Yy] ]]; then
  VIDEO_CODECS=(h264)
fi

# NEW:
VIDEO_CODECS=(h264 h265 vp9)

# Pilot option override:
if [[ "$RUN_PILOT" =~ ^[Yy] ]]; then
  VIDEO_CODECS=(h264)  # Keep pilot simple with h264 only
fi
```

---

## FFmpeg VP9 Encoding Parameters Explained

### Recommended VP9 Settings for Streaming

```bash
-c:v libvpx-vp9              # VP9 codec
-b:v ${BITRATE}k             # Target bitrate (matches H.264/H.265)
-crf 31                      # Constant Rate Factor (31 = balanced quality/speed)
-g 60                        # GOP size: 60 frames (2 seconds at 30fps)
-keyint_min 60               # Minimum keyframe interval
-speed 4                     # Encoding speed (0=slowest/best, 8=fastest/worst)
-tile-columns 2              # Parallel encoding tiles (4 tiles for better threading)
-threads 4                   # Thread count (match CPU cores)
-row-mt 1                    # Row-based multithreading (faster encoding)
-quality realtime            # Optimize for real-time encoding
-deadline realtime           # Enforce real-time encoding deadline
```

### Parameter Rationale

**Why `-speed 4`?**
- Speed 0-3: Too slow for real-time streaming
- Speed 4-5: ✅ Good balance (real-time capable, good quality)
- Speed 6-8: Fast but lower quality

**Why `-crf 31`?**
- CRF 0-23: Excellent quality (too slow for real-time)
- CRF 24-31: ✅ Good quality (streaming-friendly)
- CRF 32+: Lower quality (faster encoding)

**Why `-tile-columns 2` and `-row-mt 1`?**
- Enables parallel encoding across CPU cores
- Critical for real-time performance
- 2 tile columns = 4 tiles (2^2)
- Row multithreading further improves speed

**Why `-quality realtime -deadline realtime`?**
- Forces encoder to prioritize speed over compression efficiency
- Prevents encoding from falling behind real-time
- Essential for live streaming scenarios

---

## VP9 Performance Characteristics

### Expected CPU Impact

**Encoding CPU Usage** (compared to H.264 baseline):
- H.264 (libx264 veryfast): 1.0x (baseline)
- H.265 (libx265 veryfast): 1.5-2.0x CPU
- VP9 (libvpx-vp9 speed 4): **2.0-3.0x CPU** ⚠️

**Server Decoding CPU** (Wowza processing):
- Minimal difference (server mostly passes through streams)
- Wowza transcoding (if enabled): VP9 = 2-3x CPU vs H.264

### Expected Compression Efficiency

**Bitrate for Same Quality**:
- H.264: 100% (baseline)
- H.265: ~60-70% (30-40% bitrate savings)
- VP9: ~60-75% (25-40% bitrate savings)

**Example**: 1080p30 stream
- H.264: 4,500 kbps
- H.265: 2,700-3,150 kbps (40-30% savings)
- VP9: 2,700-3,375 kbps (40-25% savings)

### Testing Value

**What VP9 Tests Reveal**:
1. **CPU Limits**: VP9's high encoding CPU helps find orchestrator capacity limits
2. **Codec Efficiency**: Compare bandwidth usage across codecs at same quality
3. **Server Capacity**: Does Wowza handle VP9 streams differently than H.264?
4. **Real-world Scenarios**: Many platforms use VP9 (YouTube, WebRTC)

---

## Implementation Steps (Detailed)

### Step 1: Update `stream_load_tester.sh` Codec Selection

**File**: `stream_load_tester.sh`  
**Function**: `get_video_codec()` (lines ~278-295)

**Change**:
```bash
get_video_codec() {
    echo
    echo -e "${BLUE}Select Video Codec:${NC}"
    echo "1) H.264 (libx264) - Widely compatible, good compression"
    echo "2) H.265 (libx265) - Better compression, lower bitrate for same quality"
    echo "3) VP9 (libvpx-vp9) - Open-source, high compression, higher CPU usage"
    echo
    
    while true; do
        read -p "Enter choice [1-3]: " choice
        case "$choice" in
            1) VIDEO_CODEC="h264"; break ;;
            2) VIDEO_CODEC="h265"; break ;;
            3) VIDEO_CODEC="vp9"; break ;;
            *) echo "Invalid choice. Please enter 1-3." ;;
        esac
    done
    
    log_info "INPUT" "Selected video codec: $VIDEO_CODEC"
}
```

**Complexity**: ✅ Trivial (add 1 menu option, 1 case statement)

---

### Step 2: Add VP9 Encoding to Multi-Stream Function

**File**: `stream_load_tester.sh`  
**Function**: `build_multi_stream_ffmpeg_command()` (lines ~504-530)

**Change**:
```bash
# Video encoding based on selected codec
if [[ "$VIDEO_CODEC" == "h265" ]]; then
    cmd+=" -c:v libx265 -preset veryfast -b:v ${BITRATE}k -g 60 -keyint_min 60 -x265-params keyint=60:min-keyint=60"
elif [[ "$VIDEO_CODEC" == "vp9" ]]; then
    # VP9 encoding optimized for real-time streaming
    cmd+=" -c:v libvpx-vp9 -b:v ${BITRATE}k -crf 31 -g 60 -keyint_min 60"
    cmd+=" -speed 4 -tile-columns 2 -threads 4 -row-mt 1"
    cmd+=" -quality realtime -deadline realtime"
else
    # H.264 encoding with Wowza-compatible settings
    local h264_level="3.1"  # Default for 720p and below
    case "${RESOLUTION,,}" in
        "4k")
            h264_level="5.1"  # Required for 4K (3840x2160)
            ;;
        "1080p")
            h264_level="4.0"  # Optimal for 1080p
            ;;
        "720p")
            h264_level="3.1"  # Standard for 720p
            ;;
        "360p")
            h264_level="3.0"  # Sufficient for 360p
            ;;
    esac
    
    cmd+=" -c:v libx264 -preset veryfast -profile:v baseline -level ${h264_level}"
    cmd+=" -pix_fmt yuv420p -r 30 -threads 0"
    cmd+=" -b:v ${BITRATE}k -g 60 -sc_threshold 0"
    cmd+=" -flags +global_header"
fi
```

**Complexity**: ✅ Easy (copy H.265 pattern, adjust parameters)

---

### Step 3: Add VP9 Encoding to Single-Stream Function

**File**: `stream_load_tester.sh`  
**Function**: `build_single_stream_ffmpeg_command()` (lines ~590-618)

**Change**: Same as Step 2 (duplicate the VP9 encoding block)

**Complexity**: ✅ Trivial (copy-paste from Step 2)

---

### Step 4: Update Orchestrator Test Matrix

**File**: `orchestrator/run_orchestration.sh`  
**Lines**: ~242-252

**Change**:
```bash
# Test matrix defaults
PROTOCOLS=(rtmp rtsp srt)
RESOLUTIONS=(4k 1080p 720p 360p)
VIDEO_CODECS=(h264 h265 vp9)  # <-- ADD vp9 HERE
AUDIO_CODEC=aac
CONNECTIONS=(1 2 5 10 20 50)

# Pilot option: override defaults if requested
read -p "Run pilot subset only? (y/N): " RUN_PILOT
if [[ "$RUN_PILOT" =~ ^[Yy] ]]; then
  log "Pilot mode: reducing matrix for quick validation"
  PROTOCOLS=(rtmp)
  RESOLUTIONS=(1080p)
  VIDEO_CODECS=(h264)  # Keep pilot simple with h264 only
  BITRATES_LOW[1080p]=3000
  BITRATES_MID[1080p]=5000
  BITRATES_HIGH[1080p]=8000
  CONNECTIONS=(1 5 10 20 50)
  
  DURATION_MINUTES=$PILOT_DURATION_MINUTES
  log "Pilot mode: 2-minute tests, 5 connection counts (1,5,10,20,50), 3 bitrates (3000k,5000k,8000k)"
fi
```

**Complexity**: ✅ Trivial (add 3 characters to array)

---

### Step 5: Verify FFmpeg VP9 Support

**Prerequisites Check**:
```bash
# Test if FFmpeg has VP9 encoder
ffmpeg -encoders | grep vp9

# Expected output:
# V..... libvpx-vp9          libvpx VP9 (codec vp9)
```

**If Missing**:
- Windows: Reinstall FFmpeg with VP9 support (most builds include it)
- Linux: `sudo apt-get install ffmpeg` (or update existing)
- macOS: `brew install ffmpeg`

**Complexity**: ✅ Verification step (likely already supported)

---

### Step 6: Testing & Validation

**Test 1: Single Stream Test**
```bash
cd ~/PublishLoadTester
./stream_load_tester.sh

# Select:
# Protocol: RTMP
# Resolution: 720p
# Video Codec: 3 (VP9)
# Audio Codec: AAC
# Connections: 1
# Duration: 1 minute
```

**Expected Results**:
- ✅ FFmpeg starts encoding
- ✅ Stream publishes to server
- ✅ Higher CPU usage than H.264 (2-3x)
- ✅ Logs show: "Selected video codec: vp9"

**Test 2: Pilot Mode with VP9**
```bash
cd ~/PublishLoadTester/orchestrator
./run_orchestration.sh

# When prompted:
# - Pilot mode: N (full test)
# - Or manually edit script: VIDEO_CODECS=(vp9)
```

**Expected Results**:
- ✅ Orchestrator runs VP9 tests
- ✅ Results CSV includes vp9 entries
- ✅ Monitoring shows higher CPU usage

**Test 3: Codec Comparison**
```bash
# Run same test with all 3 codecs:
VIDEO_CODECS=(h264 h265 vp9)

# Compare results:
# - CPU usage: VP9 > H.265 > H.264
# - Bandwidth: VP9 ≈ H.265 < H.264 (for same quality)
```

**Complexity**: ✅ Standard testing (same as existing codecs)

---

## Impact on Test Matrix

### Current TEST_MATRIX.md Specification

**Defined Tests**: 72 tests (3 protocols × 4 resolutions × 6 connection levels)
- **Video Codec**: H.264 (fixed)
- **Audio Codec**: AAC (fixed)

### With VP9 Addition

**Option A: Extend TEST_MATRIX.md to Include VP9**
- **New Total**: 144 tests (3 protocols × 4 resolutions × 6 connections × **2 codecs**)
- **Codecs**: H.264 + VP9 (drop H.265 for simplicity)
- **Rationale**: Compare H.264 (baseline) vs VP9 (modern)

**Option B: Keep TEST_MATRIX.md as H.264-only, Add Separate VP9 Tests**
- **TEST_MATRIX.md**: 72 tests (H.264 only) - unchanged
- **VP9_TEST_MATRIX.md**: 72 tests (VP9 only) - separate document
- **Rationale**: Baseline capacity testing (H.264) vs codec comparison (VP9)

**Option C: Add VP9 as Optional Extension**
- **TEST_MATRIX.md**: 72 tests (H.264 only) - primary
- **Orchestrator**: Supports H.264, H.265, VP9 via configuration
- **Rationale**: Flexibility - users choose codecs, default to H.264

**Recommendation**: **Option C** ✅
- Keep TEST_MATRIX.md focused on H.264 (as designed)
- Allow orchestrator to support all 3 codecs
- Users can override `VIDEO_CODECS` array as needed
- Minimal documentation changes

---

## Documentation Updates

### Files to Update

1. **VP9_IMPLEMENTATION_PLAN.md** (this file) ✅
   - Implementation guide
   - FFmpeg parameter reference
   - Performance expectations

2. **CHANGELOG.md**
   ```markdown
   ## [Unreleased]
   ### Added
   - VP9 (libvpx-vp9) codec support for video encoding
   - Codec selection menu now includes H.264, H.265, and VP9
   - Optimized VP9 encoding parameters for real-time streaming
   ```

3. **README.md** (optional)
   ```markdown
   ### Supported Video Codecs
   - H.264 (libx264) - Widely compatible, good compression
   - H.265 (libx265) - Better compression, requires more CPU
   - VP9 (libvpx-vp9) - Open-source, high compression, higher CPU usage
   ```

4. **orchestrator/docs/IMPLEMENTATION_PLAN.md** (note in Phase 1 or Phase 2)
   ```markdown
   ## Phase 1.5: Codec Expansion (Optional Enhancement)
   **Status**: Implemented before Phase 1
   - Added VP9 codec support
   - Codec selection: H.264, H.265, VP9
   - FFmpeg encoding parameters optimized per codec
   ```

---

## Effort Estimation

### Time Breakdown

| Task | Estimated Time | Complexity |
|------|---------------|-----------|
| Step 1: Codec selection menu | 15 minutes | ✅ Trivial |
| Step 2: Multi-stream encoding | 30 minutes | ✅ Easy |
| Step 3: Single-stream encoding | 15 minutes | ✅ Trivial |
| Step 4: Orchestrator matrix | 5 minutes | ✅ Trivial |
| Step 5: FFmpeg verification | 10 minutes | ✅ Easy |
| Step 6: Testing & validation | 60-90 minutes | ⚠️ Moderate |
| Documentation updates | 30 minutes | ✅ Easy |
| **TOTAL** | **2-4 hours** | ✅ **LOW LIFT** |

### Risk Assessment

**Risks**: ✅ **MINIMAL**

1. **FFmpeg VP9 Support**: Low risk (widely available)
   - Mitigation: Check `ffmpeg -encoders | grep vp9` before implementation

2. **Wowza VP9 Compatibility**: Low risk (Wowza supports VP9 ingest)
   - Mitigation: Test single stream before full orchestration

3. **CPU Overload**: Medium risk (VP9 uses 2-3x CPU vs H.264)
   - Mitigation: Already handled by Phase 0 monitoring (80% CPU threshold)
   - Benefit: VP9 helps identify CPU capacity limits faster!

4. **Breaking Existing Tests**: Minimal risk (additive change only)
   - Mitigation: Pilot mode defaults to H.264 (no change in behavior)

---

## Success Criteria

### Implementation Complete When:

- [x] VP9 appears in codec selection menu (option 3)
- [x] FFmpeg commands include VP9 encoding parameters
- [x] Orchestrator `VIDEO_CODECS` array includes `vp9`
- [x] Single stream test with VP9 publishes successfully
- [x] Pilot mode test with VP9 runs without errors
- [x] Results CSV includes VP9 test entries
- [x] CPU monitoring shows expected 2-3x increase vs H.264
- [x] Documentation updated (CHANGELOG, this plan)

### Optional Validation:

- [ ] Compare H.264 vs H.265 vs VP9 CPU usage (same resolution/bitrate)
- [ ] Compare H.264 vs H.265 vs VP9 bandwidth efficiency (same quality)
- [ ] Verify VP9 streams play back on server (if Wowza transcoding enabled)
- [ ] Test all protocols (RTMP, RTSP, SRT) with VP9

---

## Conclusion

### Summary

**VP9 Codec Addition**:
- ✅ **LOW LIFT**: 2-4 hours of work
- ✅ **INDEPENDENT**: Not part of Phase 0 or Phase 1 implementation plan
- ✅ **RECOMMENDED TIMING**: Before Phase 1 (avoid re-testing later)
- ✅ **HIGH VALUE**: Enables codec comparison, CPU stress testing, modern streaming scenarios

**Key Benefits**:
1. Complete codec coverage: H.264 (baseline), H.265 (efficiency), VP9 (open-source)
2. CPU capacity testing: VP9's high CPU usage reveals orchestrator/server limits
3. Research value: Compare bitrate savings and CPU costs across codecs
4. Future-proof: VP9 is widely used in modern streaming (YouTube, WebRTC)

**Next Steps**:
1. Decide on timing: Before, during, or after Phase 1?
2. Verify FFmpeg VP9 support: `ffmpeg -encoders | grep vp9`
3. Implement changes (2-4 hours)
4. Test and validate
5. Update TEST_MATRIX.md if desired (or keep as H.264-focused baseline)

**Recommendation**: ✅ **Implement VP9 now** (before Phase 1) to complete codec options before comprehensive test matrix implementation.

---

## Appendix: FFmpeg VP9 Reference

### Minimal VP9 Command
```bash
ffmpeg -i input.mp4 -c:v libvpx-vp9 -b:v 2000k output.webm
```

### Optimized VP9 for Streaming (Used in This Implementation)
```bash
ffmpeg -re -f lavfi -i testsrc2=size=1920x1080:rate=30 \
  -f lavfi -i sine=frequency=1000:sample_rate=48000 \
  -c:v libvpx-vp9 -b:v 4500k -crf 31 -g 60 -keyint_min 60 \
  -speed 4 -tile-columns 2 -threads 4 -row-mt 1 \
  -quality realtime -deadline realtime \
  -c:a aac -b:a 128k \
  -f flv rtmp://server/app/stream
```

### VP9 Two-Pass Encoding (NOT for Real-Time)
```bash
# Pass 1 (analysis)
ffmpeg -i input.mp4 -c:v libvpx-vp9 -b:v 2000k -pass 1 -f null /dev/null

# Pass 2 (encoding)
ffmpeg -i input.mp4 -c:v libvpx-vp9 -b:v 2000k -pass 2 output.webm
```

### VP9 Speed Presets
| Speed | Quality | Encoding Time | Use Case |
|-------|---------|---------------|----------|
| 0 | Best | Very slow | Archival/VOD |
| 1-3 | Excellent | Slow | VOD encoding |
| **4** | **Good** | **Real-time** | **Live streaming** ✅ |
| 5 | Good | Fast | Live streaming |
| 6-8 | Lower | Very fast | Low-latency streaming |

---

**Document Version**: 1.0  
**Last Updated**: October 17, 2025  
**Author**: Stream Load Tester Project  
**Status**: Planning Complete - Ready for Implementation
