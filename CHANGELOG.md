# Changelog

All notable changes to the Stream Load Tester project.

## [2.1.1] - 2025-10-16

### Fixed
- **H.264 encoding compatibility with Wowza Engine**
  - Added explicit H.264 profile (baseline) for universal compatibility
  - Added resolution-appropriate H.264 levels:
    - 4K: Level 5.1 (supports up to 4096x2304 @ 30fps)
    - 1080p: Level 4.0 (supports up to 1920x1080 @ 30fps)
    - 720p: Level 3.1 (supports up to 1280x720 @ 30fps)
    - 360p: Level 3.0 (supports up to 720x576 @ 30fps)
  - Added pixel format specification (yuv420p) for consistent color space
  - Disabled scene detection (`-sc_threshold 0`) to prevent unexpected keyframes
  - Added `no-scenecut` parameter to ensure strict GOP control
  - Fixes "H264Utils.decodeAVCC: ArrayIndexOutOfBoundsException" error in Wowza Engine
  - Ensures proper SPS/PPS header generation for all resolutions

## [2.1.0] - 2025-10-16

### Added
- **Save and reuse test configurations**
  - After successful test completion, option to save configuration for future use
  - Auto-generated configuration names based on test parameters
  - Ability to append custom text to configuration names
  - Saved configurations stored in `previous_runs/` directory
- **Previous runs menu on startup**
  - Lists all saved configurations when script starts
  - View configuration summary before running
  - Option to re-run with existing settings
  - Option to modify server URL, app name, and stream name before running
  - Quick access to frequently used test scenarios

### Changed
- Enhanced user workflow with configuration management
- Improved interactive mode with previous run selection

## [2.0.0] - 2025-10-16

### Removed
- **WebRTC protocol support** - Removed due to unresolvable network compatibility issues
  - Removed webrtc_publisher.py Python script
  - Removed check_webrtc_deps.py dependency checker
  - Removed fix_webrtc_deps.sh and fix_python_packages.sh scripts
  - Removed Python and GStreamer dependencies
  - Removed DTLS documentation and test scripts
  - Removed requirements.txt

### Changed
- **Simplified dependencies** - Now only requires FFmpeg
- **Updated documentation** - Removed all WebRTC references from README
- **Updated check_dependencies.sh** - Removed Python and GStreamer checks
- **Updated config/default.conf** - Removed WebRTC configuration section
- **Updated cleanup scripts** - Removed WebRTC process management
- **Protocol options** - Changed from 4 protocols to 3 (RTMP, RTSP, SRT)

## [1.1.0] - 2025-10-15

### Added
- **Single-encode mode** for RTMP/RTSP/SRT protocols using FFmpeg tee muxer
  - 80-90% CPU reduction for multiple streams
  - Single FFmpeg process outputs to all destinations
  - Automatic activation for all protocols
- **Enhanced interactive configuration**
  - Separate prompts for server, application, and stream name
  - Clear examples for each protocol
  - Improved URL validation
- **Comprehensive debug logging**
  - Detailed monitoring loop diagnostics
  - Process state tracking
  - FFmpeg error capture and reporting
- **Cleanup protection**
  - Guard against multiple cleanup calls
  - Prevention of infinite cleanup loops

### Changed
- **URL format standardization**
  - URLs now exclude stream names
  - Stream names specified separately and auto-numbered
  - Example: `rtmp://server:1935/live` + `test` → `test001`, `test002`, etc.
- **Dependency checker improvements**
  - Removed strict `set -e` mode for graceful error handling
  - Better error reporting and diagnosis
  - Fixed codec detection issues
- **Monitoring improvements**
  - Protocol-specific status messages
  - Better process lifecycle management
  - Enhanced error detection

### Fixed
- FFmpeg process premature termination
- Cleanup infinite loop on script exit
- Dependency checker false negatives
- Stream name URL format confusion
- Monitor test not executing properly
- Arithmetic expansion issues with `set -e`

### Performance
- **RTMP/RTSP/SRT**: 80-90% CPU reduction vs previous version
- **Memory**: 50% reduction for multi-stream scenarios
- **Startup**: Instant for all protocols (no ramping needed)

## [1.0.0] - 2025-10-14

### Initial Release
- Multi-protocol support (RTMP, RTSP, SRT)
- Multiple concurrent stream generation
- Test pattern video and sine wave audio
- Configurable bitrates and durations
- Comprehensive logging
- Dependency checking
- Process cleanup utilities
