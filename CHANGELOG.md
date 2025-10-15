# Changelog

All notable changes to the Stream Load Tester project.

## [1.1.0] - 2025-10-15

### Added
- **Single-encode mode** for RTMP/RTSP/SRT protocols using FFmpeg tee muxer
  - 80-90% CPU reduction for multiple streams
  - Single FFmpeg process outputs to all destinations
  - Automatic activation for non-WebRTC protocols
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
- **Startup**: Instant for RTMP/RTSP/SRT (no ramping needed)

## [1.0.0] - 2025-10-14

### Initial Release
- Multi-protocol support (RTMP, RTSP, SRT, WebRTC)
- Multiple concurrent stream generation
- Test pattern video and sine wave audio
- Configurable bitrates and durations
- Ramp-up support for gradual load
- Comprehensive logging
- Dependency checking
- Process cleanup utilities
