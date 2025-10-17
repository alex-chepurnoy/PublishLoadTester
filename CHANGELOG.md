# Changelog

All notable changes to the Stream Load Tester project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- VP9 (libvpx-vp9) codec support for video encoding
- H.265 (libx265) and VP9 encoder detection in FFmpeg checks library
- Codec selection menu now includes H.264, H.265, and VP9 options
- Optimized VP9 encoding parameters for real-time streaming (-speed 4, tile-columns, row-mt)
- VP9 support in orchestrator test matrix (h264, h265, vp9)
- Comprehensive VP9 implementation documentation (IMPLEMENTATION_PLAN, QUICK_SUMMARY, IMPLEMENTATION_COMPLETE)
- Hardware-accelerated encoder support detection (NVENC, QSV, VAAPI for H.264/H.265/VP9)

### Changed
- `check_dependencies.sh` now uses `FFMPEG_H265_ENCODERS` array instead of inline list
- Orchestrator `VIDEO_CODECS` array expanded from `(h264 h265)` to `(h264 h265 vp9)`
- Codec selection input range changed from [1-2] to [1-3]

### Technical Details
- **Files Modified**: 4
  - `scripts/lib/ffmpeg_checks.sh` - Added VP9 and H.265 encoder arrays
  - `scripts/check_dependencies.sh` - Added VP9 check with FFMPEG_VP9_ENCODERS array
  - `stream_load_tester.sh` - Added VP9 to menu, multi-stream, and single-stream functions
  - `orchestrator/run_orchestration.sh` - Added vp9 to VIDEO_CODECS array
- **Implementation Time**: ~30 minutes
- **Backward Compatibility**: ✅ Fully backward compatible (additive changes only)
- **Pilot Mode**: Still defaults to h264 for quick validation

## [2.0.0] - 2025-10-16

### Added (Phase 0 - Monitoring Infrastructure)
- Real-time server monitoring infrastructure for adaptive load testing
- `get_server_heap()` - Java heap monitoring via jcmd with multi-GC support
- `get_server_cpu()` - System CPU monitoring via mpstat/sar
- `get_server_memory()` - RAM monitoring via free command
- `get_server_network()` - Network throughput monitoring via sar
- `check_server_status()` - Unified health check function
- `remote_monitor.sh` - Server-side continuous monitoring (5-second CSV logging)
- `validate_server.sh` - Pre-flight validation script (6 validation checks)
- `diagnose_jcmd.sh` - Heap monitoring troubleshooting tool
- Adaptive stopping at 80% CPU or 80% heap thresholds
- Multi-GC support: Parallel GC, G1GC, ZGC, Shenandoah
- Passwordless sudo configuration for Java monitoring tools
- ZGC MB format parsing (handles "194M" format, not just KB)
- Local AWK processing pattern for reliable remote data parsing

### Fixed (Phase 0 - 10 Major Fixes)
1. Java tools dual-location detection (PATH + Wowza bundled JDK)
2. SSH warning suppression (-q -o LogLevel=ERROR)
3. Log function stderr redirect (>&2 to prevent stdout pollution)
4. Passwordless sudo via /etc/sudoers.d/java-monitoring
5. Multi-GC support for heap monitoring
6. Correct PID detection (Bootstrap Engine vs Manager process)
7. Heap MB logging in CSV (not just percentage)
8. ZGC MB format parsing (194M vs 198656K)
9. AWK BEGIN block variable initialization
10. Local AWK processing (SSH data fetch + local parse, not remote AWK)

### Changed (Phase 0)
- Monitoring functions now return accurate percentages (0.00-100.00)
- CSV logs now include HEAP_USED_MB and HEAP_CAPACITY_MB columns
- `parse_run.py` updated to parse monitor CSVs and convert to MB
- Health checks integrated into main orchestration loop
- Results CSV includes heap_used_mb and heap_capacity_mb (was heap_used_kb)

### Documentation (Phase 0)
- Created 20+ documentation files in organized structure
- `phase0/` - Phase 0 implementation guides (8 files)
- `troubleshooting/` - Issue resolution guides (4 files)
- `fixes/` - Detailed fix documentation (8 files)
- `PHASE_0_FINAL_SUMMARY.md` - Comprehensive Phase 0 summary
- `IMPLEMENTATION_PLAN.md` - Multi-phase project roadmap

### Testing (Phase 0)
- Production validated on EC2 t3.xlarge with Wowza Streaming Engine
- ZGC (Generational mode) with 5.4 GB max heap
- All 10 monitoring functions tested and validated
- Pilot mode successfully runs with real-time health checks

## [1.0.0] - 2025-10-15

### Added
- Initial release of Stream Load Tester
- Multi-protocol support: RTMP, RTSP, SRT
- Multiple resolution support: 360p, 720p, 1080p, 4K
- H.264 and H.265 video codec support
- AAC and Opus audio codec support
- Multi-stream concurrent publishing via FFmpeg tee muxer
- Orchestration system for automated testing
- Python result parsing and CSV generation
- Dependency checking and installation scripts
- Graceful cleanup and interrupt handling
- Pilot mode for quick validation

### Features
- Protocol-specific URL construction
- Bitrate configuration per resolution
- Configurable test duration and connection count
- Progress tracking with connection status
- Log file management and rotation
- Previous runs archival
- FFmpeg encoding optimization per protocol

## Project Information

**Repository**: https://github.com/alex-chepurnoy/PublishLoadTester  
**Author**: alex-chepurnoy  
**License**: [Add License]  
**Documentation**: See `orchestrator/docs/` for comprehensive guides

### Key Capabilities

**Video Codecs**:
- H.264 (libx264) - Widely compatible, good compression, baseline CPU usage
- H.265 (libx265) - Better compression (~30% bitrate savings), higher CPU usage  
- VP9 (libvpx-vp9) - Open-source, high compression (~30% bitrate savings), highest CPU usage (2-3x H.264)

**Monitoring**:
- Real-time CPU, Heap, Memory, Network monitoring
- Adaptive stopping at resource thresholds (80% CPU or Heap)
- Multi-GC support for Java heap monitoring
- CSV logging every 5 seconds

**Testing**:
- Comprehensive test matrix: 3 protocols × 4 resolutions × 3 codecs × 6 connection levels
- Pilot mode for quick validation
- Automated capacity measurement
- Safe testing with adaptive stopping

---

**Note**: This CHANGELOG was created on 2025-10-17 and captures recent development history. Earlier changes may not be fully documented.
