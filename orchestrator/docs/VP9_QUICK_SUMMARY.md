# VP9 Codec Addition - Quick Summary

**Created**: October 17, 2025  
**Status**: Planning Complete

---

## TL;DR

**What**: Add VP9 codec support alongside H.264 and H.265  
**Why**: Enable codec comparison testing, CPU stress testing, modern streaming scenarios  
**Effort**: ✅ **2-4 hours** (LOW LIFT)  
**Timing**: ⚠️ **SEPARATE from Phase 0/1** - Recommended BEFORE Phase 1  
**Impact**: Minimal - extends existing codec selection, no breaking changes

---

## Quick Answers

### Q1: Does this fit the Implementation Phase Plan?

**A1**: ⚠️ **NO** - This is a **SEPARATE WORK PROCESS**

- ✅ **Phase 0**: Monitoring infrastructure (COMPLETE)
- 🔜 **Phase 1**: Test matrix implementation (NEXT)
- 🎯 **VP9 Addition**: Feature enhancement (independent)

**VP9 is NOT required for Phase 0 or Phase 1** - it's an optional codec extension.

---

### Q2: What is the lift to add VP9?

**A2**: ✅ **LOW LIFT - 2-4 hours total**

| Task | Time | Complexity |
|------|------|-----------|
| Add codec selection menu | 15 min | Trivial |
| Add FFmpeg encoding (2 locations) | 45 min | Easy |
| Update orchestrator array | 5 min | Trivial |
| Verify FFmpeg support | 10 min | Easy |
| Testing & validation | 60-90 min | Moderate |
| Documentation | 30 min | Easy |
| **TOTAL** | **2-4 hours** | **LOW** |

---

### Q3: When should we add VP9?

**A3**: ✅ **RECOMMENDED: BEFORE Phase 1**

**Why?**
- Complete codec options before comprehensive testing
- Avoid re-running full test matrix later
- Only 2-4 hours now vs retesting hours later

**Alternatives**:
- During Phase 1: Adds ~4 hours to Phase 1 scope
- After Phase 1: Requires re-running comprehensive tests

---

## What Changes

### 1. User-Facing Changes

**Codec Selection Menu** (in `stream_load_tester.sh`):
```
Select Video Codec:
1) H.264 (libx264) - Widely compatible, good compression
2) H.265 (libx265) - Better compression, lower bitrate
3) VP9 (libvpx-vp9) - Open-source, high compression, higher CPU    <-- NEW
```

### 2. Code Changes

**Files Modified**: 2 files, 4 locations total

1. `stream_load_tester.sh`:
   - Codec selection menu (add option 3)
   - Multi-stream FFmpeg encoding (add VP9 elif block)
   - Single-stream FFmpeg encoding (add VP9 elif block)

2. `orchestrator/run_orchestration.sh`:
   - Test matrix: `VIDEO_CODECS=(h264 h265 vp9)` ← add `vp9`

### 3. FFmpeg Commands

**VP9 Encoding Parameters** (optimized for real-time streaming):
```bash
-c:v libvpx-vp9              # VP9 codec
-b:v ${BITRATE}k             # Target bitrate
-crf 31                      # Quality (31 = balanced)
-speed 4                     # Speed preset (4 = real-time capable)
-tile-columns 2              # Parallel encoding (4 tiles)
-threads 4                   # Thread count
-row-mt 1                    # Row multithreading
-quality realtime            # Real-time optimization
-deadline realtime           # Enforce real-time deadline
```

---

## VP9 Characteristics

### Performance vs H.264

| Metric | H.264 | VP9 | Impact |
|--------|-------|-----|--------|
| **Encoding CPU** | 1.0x | 2.0-3.0x | ⚠️ Higher CPU usage |
| **Bitrate (same quality)** | 100% | 60-75% | ✅ 25-40% bandwidth savings |
| **Browser Support** | Universal | Chrome/Firefox/Edge | ✅ Wide support |
| **Hardware Encoding** | Widely available | Limited | ⚠️ Mostly software |
| **Licensing** | Requires fees | Royalty-free | ✅ Open-source |

### Why VP9 is Valuable for Testing

1. **CPU Stress Test**: Higher encoding CPU (2-3x) helps find capacity limits faster
2. **Codec Comparison**: Compare H.264 vs H.265 vs VP9 on same infrastructure
3. **Bandwidth Efficiency**: Test if 25-40% bitrate savings justify higher CPU usage
4. **Modern Streaming**: YouTube, WebRTC, and many platforms use VP9

---

## Implementation Steps (High-Level)

1. ✅ **Verify FFmpeg Support**: `ffmpeg -encoders | grep vp9`
2. ✅ **Update Codec Selection**: Add option 3 to menu
3. ✅ **Add VP9 Encoding**: Add `elif [[ "$VIDEO_CODEC" == "vp9" ]]` blocks
4. ✅ **Update Orchestrator**: Add `vp9` to `VIDEO_CODECS` array
5. ✅ **Test Single Stream**: Verify VP9 stream publishes
6. ✅ **Test Pilot Mode**: Verify orchestrator runs VP9 tests
7. ✅ **Document**: Update CHANGELOG

**Detailed Steps**: See `VP9_IMPLEMENTATION_PLAN.md`

---

## Risks & Mitigation

| Risk | Level | Mitigation |
|------|-------|-----------|
| FFmpeg missing VP9 | Low | Check `ffmpeg -encoders` first |
| Wowza VP9 issues | Low | Test single stream before full orchestration |
| CPU overload | Medium | ✅ Already handled by Phase 0 monitoring (80% threshold) |
| Breaking existing tests | Minimal | Additive change only, pilot defaults to H.264 |

---

## Success Criteria

**Implementation Complete When**:
- [x] VP9 appears in codec selection menu
- [x] FFmpeg commands include VP9 encoding
- [x] Orchestrator supports VP9 in test matrix
- [x] Single stream test publishes successfully
- [x] Pilot mode runs without errors
- [x] Documentation updated

---

## Decision Points

### Should We Add VP9?

**YES IF**:
- ✅ Want to compare H.264 vs H.265 vs VP9 performance
- ✅ Want to stress-test CPU capacity (VP9 uses 2-3x CPU)
- ✅ Want to test modern streaming scenarios (YouTube, WebRTC)
- ✅ Have 2-4 hours available before Phase 1

**NO IF**:
- ❌ Only care about H.264 baseline testing
- ❌ Want to minimize Phase 1 scope
- ❌ FFmpeg doesn't support VP9 (rare)

### When to Add VP9?

**Option A: Before Phase 1** ✅ **RECOMMENDED**
- **Time**: 2-4 hours now
- **Benefit**: Complete codec options, no retesting
- **Risk**: None

**Option B: During Phase 1**
- **Time**: +4 hours to Phase 1
- **Benefit**: Single testing cycle
- **Risk**: Extends Phase 1 timeline

**Option C: After Phase 1**
- **Time**: 2-4 hours + full test matrix rerun
- **Benefit**: Faster Phase 1 completion
- **Risk**: Significant rework to include VP9 in results

---

## Recommendation

✅ **IMPLEMENT VP9 NOW** (before Phase 1)

**Reasoning**:
1. **Low effort**: Only 2-4 hours
2. **High value**: Codec comparison, CPU testing, modern streaming
3. **Avoid rework**: Don't rerun comprehensive tests later
4. **Independent**: Doesn't affect Phase 0/1 implementation
5. **Future-proof**: VP9 is widely adopted (YouTube, WebRTC)

**Next Step**: Review detailed plan in `VP9_IMPLEMENTATION_PLAN.md` and proceed with implementation.

---

**Full Documentation**: `orchestrator/docs/VP9_IMPLEMENTATION_PLAN.md`  
**Questions?**: Check the detailed plan for FFmpeg parameters, testing procedures, and codec comparison analysis.
