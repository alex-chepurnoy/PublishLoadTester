# Stream Load Tester

A comprehensive Bash-based tool for load testing streaming infrastructure by generating multiple concurrent video streams to various protocols (RTMP, RTSP, SRT). This tool uses FFmpeg to create synthetic test streams and efficiently publish them to streaming servers.

## 🎯 What This Does

Stream Load Tester simulates multiple concurrent video stream publishers to test the capacity and performance of streaming servers. It:

- **Generates synthetic video streams** using FFmpeg with configurable bitrates
- **Publishes to multiple protocols**: RTMP, RTSP, and SRT
- **Creates concurrent connections** simultaneously using single-encode mode
- **Efficiently uses CPU** by employing single-encode mode (one FFmpeg process outputs to all destinations)
- **Monitors stream health** and logs detailed information
- **Handles graceful cleanup** of all spawned processes

### Key Features

- ✅ Multi-protocol support (RTMP, RTSP, SRT)
- ✅ **Multiple resolution options** (4K, 1080p, 720p, 360p)
- ✅ **Video codec selection** (H.264, H.265)
- ✅ **Audio codec selection** (AAC, Opus)
- ✅ **Automatic dependency checking and installation**
- ✅ Configurable bitrate with resolution-specific recommendations
- ✅ CPU-efficient single-encode mode (80-90% CPU reduction)
- ✅ Interactive or command-line modes
- ✅ Comprehensive logging and monitoring
- ✅ Clean process management and cleanup

## 📋 Prerequisites

- **Linux/Unix environment** (Bash shell)
- **FFmpeg** with required codecs:
  - **Required**: H.264 (libx264) and AAC encoders
  - **Optional**: H.265 (libx265) and Opus encoders for better compression
- **Basic system tools**: bash, kill, pkill, ps, grep

The tool includes automatic dependency checking and can install FFmpeg if needed.

## 🚀 Installation

### Quick Start (Automatic Setup)

The Stream Load Tester includes **automatic dependency checking and installation**. You can start using it immediately:

```bash
cd PublishLoadTester
chmod +x stream_load_tester.sh
./stream_load_tester.sh
```

The script will automatically:
- Check if all dependencies are installed
- Run the installation script if dependencies are missing
- Install FFmpeg with required codecs
- Verify the setup before proceeding

### Manual Installation (Optional)

If you prefer to install dependencies manually or want more control:

1. **Run the installation script**:
   ```bash
   cd PublishLoadTester
   chmod +x scripts/install.sh
   ./scripts/install.sh
   ```

   The installation script will:
   - Make all scripts executable
   - Check for required dependencies
   - Offer to install FFmpeg if missing
   - Verify FFmpeg codec support

2. **Check dependencies**:
   ```bash
   chmod +x check_dependencies.sh
   ./check_dependencies.sh
   ```

3. **Install FFmpeg manually** (if needed):
   - Ubuntu/Debian: `sudo apt-get install ffmpeg`
   - CentOS/RHEL: `sudo yum install ffmpeg`
   - macOS: `brew install ffmpeg`

## 📖 How to Use

### Interactive Mode (Recommended for First-Time Users)

Simply run the script without arguments:

```bash
./stream_load_tester.sh
```

**Note:** The script will automatically check and install dependencies on first run if needed.

You'll be prompted to configure:

1. **Protocol** - Choose RTMP, RTSP, or SRT
2. **Resolution** - Choose 4K, 1080p, 720p, or 360p with recommended bitrates
3. **Video Codec** - Choose H.264 or H.265
4. **Audio Codec** - Choose AAC or Opus
5. **Bitrate** - Video bitrate in kbps (recommended range based on resolution)
6. **Server URL** - Your streaming server address
7. **Application name** - The application/path on the server
8. **Number of connections** - How many concurrent streams (default: 5)
9. **Stream name** - Base name for streams (will be numbered: test001, test002, etc.)
10. **Duration** - How long to run the test in minutes (default: 30)

### Command-Line Mode

For automation or repeated tests:

```bash
./stream_load_tester.sh \
  --protocol rtmp \
  --resolution 1080p \
  --video-codec h264 \
  --audio-codec aac \
  --server rtmp://192.168.1.100:1935/live \
  --stream test \
  --connections 10 \
  --bitrate 4000 \
  --duration 60 \
  --force
```

#### Command-Line Options

| Option | Description | Example |
|--------|-------------|---------|
| `-p, --protocol` | Protocol to use (rtmp, rtsp, srt) | `--protocol rtmp` |
| `-r, --resolution` | Resolution (4k, 1080p, 720p, 360p) | `--resolution 1080p` |
| `--video-codec` | Video codec (h264, h265) | `--video-codec h265` |
| `--audio-codec` | Audio codec (aac, opus) | `--audio-codec opus` |
| `-b, --bitrate` | Bitrate in kbps | `--bitrate 4000` |
| `-s, --server` | Server URL | `--server rtmp://192.168.1.100:1935/live` |
| `-n, --stream` | Base stream name | `--stream mytest` |
| `-c, --connections` | Number of concurrent streams | `--connections 10` |
| `-d, --duration` | Test duration in minutes | `--duration 60` |
| `-f, --force` | Skip confirmation prompt | `--force` |
| `-h, --help` | Show help message | `--help` |

#### Resolution and Bitrate Recommendations

| Resolution | Dimensions | Recommended Bitrate Range |
|------------|------------|---------------------------|
| 4K | 3840x2160 | 8000-20000 kbps |
| 1080p | 1920x1080 | 2000-8000 kbps |
| 720p | 1280x720 | 1000-4000 kbps |
| 360p | 640x360 | 400-1500 kbps |

**Note:** H.265 can achieve the same quality as H.264 at approximately 50% lower bitrate.

### Protocol-Specific Examples

#### RTMP Example with 1080p H.264
```bash
./stream_load_tester.sh \
  --protocol rtmp \
  --resolution 1080p \
  --video-codec h264 \
  --audio-codec aac \
  --server rtmp://192.168.1.100:1935/live \
  --stream test \
  --connections 5 \
  --bitrate 4000 \
  --duration 30
```

**Streams will be published to:**
- `rtmp://192.168.1.100:1935/live/test001`
- `rtmp://192.168.1.100:1935/live/test002`
- `rtmp://192.168.1.100:1935/live/test003`
- etc.

#### RTSP Example with 720p H.265
```bash
./stream_load_tester.sh \
  --protocol rtsp \
  --resolution 720p \
  --video-codec h265 \
  --audio-codec opus \
  --server rtsp://192.168.1.100:554/app \
  --stream camera \
  --connections 3 \
  --bitrate 2000 \
  --duration 15
```

**Streams will be published to:**
- `rtsp://192.168.1.100:554/app/camera001`
- `rtsp://192.168.1.100:554/app/camera002`
- `rtsp://192.168.1.100:554/app/camera003`

#### SRT Example with 4K H.265
```bash
./stream_load_tester.sh \
  --protocol srt \
  --resolution 4k \
  --video-codec h265 \
  --audio-codec opus \
  --server srt://192.168.1.100:9999?streamid=publish \
  --stream stream \
  --connections 8 \
  --bitrate 12000 \
  --duration 45
```

**Streams will be published to (Wowza Engine format):**
- `srt://192.168.1.100:9999?streamid=#!::m=publish,r=publish/_definst_/stream001`
- `srt://192.168.1.100:9999?streamid=#!::m=publish,r=publish/_definst_/stream002`
- etc.

## 📊 Understanding the Output

### During Execution

The script provides real-time feedback:

```
[INFO] Starting stream test001 to rtmp://192.168.1.100:1935/live/test001
[INFO] Stream test001 started with PID: 12345
[INFO] Active streams: 1/5, Running: 1m, Remaining: 29m
```

### Logs

All detailed logs are saved to `logs/stream_test_TIMESTAMP.log`:

- Timestamps for all events
- Process IDs for tracking
- Stream health status
- Error messages and warnings
- Summary statistics

View logs:
```bash
# View latest log
ls -t logs/ | head -1 | xargs -I {} cat logs/{}

# Follow log in real-time
tail -f logs/stream_test_*.log
```

## 🛠️ Configuration

### Default Configuration

Edit `config/default.conf` to change default values:

```properties
# Stream Configuration
DEFAULT_BITRATE=2000          # Default bitrate in kbps (varies by resolution)
DEFAULT_DURATION=30           # Default duration in minutes
DEFAULT_CONNECTIONS=5         # Default number of streams
DEFAULT_RESOLUTION=1080p      # Default resolution (4k, 1080p, 720p, 360p)
DEFAULT_VIDEO_CODEC=h264      # Default video codec (h264, h265)
DEFAULT_AUDIO_CODEC=aac       # Default audio codec (aac, opus)

# Limits
MAX_CONNECTIONS=1000         # Maximum allowed connections
MAX_BITRATE=50000           # Maximum bitrate in kbps
MIN_BITRATE=100             # Minimum bitrate in kbps

# FFmpeg Configuration
FFMPEG_PRESET=veryfast      # Encoding speed preset
VIDEO_CODEC=libx264         # Video codec library
VIDEO_SIZE=1920x1080        # Video resolution (set by resolution choice)
VIDEO_FPS=30                # Frames per second
VIDEO_GOP=60                # GOP size (keyframe interval)
VIDEO_KEYINT_MIN=60         # Minimum keyframe interval
AUDIO_CODEC=aac             # Audio codec
AUDIO_RATE=48000            # Audio sample rate
AUDIO_BITRATE=128k          # Audio bitrate
```

### Resource Considerations

**CPU Usage:**
- Each stream at 2000 kbps uses ~5-15% CPU per core (with single-encode mode)
- Without single-encode mode: ~50-80% CPU per stream
- Monitor CPU usage: `top` or `htop`

**Network Bandwidth:**
- Total bandwidth = `(bitrate × connections) × 1.2` (overhead)
- Example: 10 streams at 2000 kbps = ~24 Mbps upload

**Memory:**
- Approximately 50-100 MB per stream
- Example: 10 streams ≈ 500-1000 MB RAM

## 🔧 Troubleshooting

### Check Dependencies
```bash
./check_dependencies.sh
```

### FFmpeg Issues
```bash
# Fix FFmpeg codec issues
./scripts/fix_ffmpeg_codecs.sh

# Check FFmpeg installation
ffmpeg -version
ffmpeg -codecs | grep h264
ffmpeg -codecs | grep aac
```

### Orphaned Processes
If streams don't clean up properly after crashes:
```bash
./scripts/cleanup.sh
```

This will kill all orphaned FFmpeg processes related to streaming.

### Connection Failures

**RTMP/RTSP:**
- Verify server is running and accessible
- Check firewall rules
- Ensure correct port (RTMP: 1935, RTSP: 554)

**SRT:**
- Verify SRT support on both client and server
- Check `streamid` format
- Default port: 9999

### Debug Mode
Enable verbose logging:
```bash
DEBUG=true ./stream_load_tester.sh
```

## 📁 Project Structure

```
PublishLoadTester/
├── stream_load_tester.sh          # Main script
├── check_dependencies.sh          # Dependency checker
├── README.md                      # This file
├── CHANGELOG.md                   # Version history
├── config/
│   └── default.conf              # Default configuration
├── logs/                         # Log files (auto-created)
├── scripts/
│   ├── install.sh               # Installation script
│   ├── cleanup.sh               # Cleanup orphaned processes
│   ├── ensure_ffmpeg_requirements.sh  # Auto-install FFmpeg
│   ├── fix_ffmpeg_codecs.sh     # Fix codec issues
│   └── lib/
│       └── ffmpeg_checks.sh     # FFmpeg helper functions
```

## 🎯 Use Cases

1. **Load Testing**: Simulate multiple clients to test server capacity
2. **Stress Testing**: Push server to limits to find breaking points
3. **Network Testing**: Test network bandwidth and stability
4. **Development**: Test streaming applications during development
5. **Benchmarking**: Compare different streaming server configurations
6. **CI/CD**: Automate streaming infrastructure tests

## ⚙️ Technical Details

### Single-Encode Mode

The tool uses FFmpeg's "tee" muxer to efficiently generate one video stream and output it to multiple destinations simultaneously. This reduces CPU usage by 80-90% compared to running separate FFmpeg processes for each stream.

### Stream Generation

Streams are generated using FFmpeg with the following settings:

**Video Encoding:**
- **Codecs Available**: 
  - H.264 (libx264) - Widely compatible, good compression
  - H.265 (libx265) - Better compression, ~50% lower bitrate for same quality
- **Resolutions Available**:
  - 4K (3840x2160) - Recommended: 8000-20000 kbps
  - 1080p (1920x1080) - Recommended: 2000-8000 kbps
  - 720p (1280x720) - Recommended: 1000-4000 kbps
  - 360p (640x360) - Recommended: 400-1500 kbps
- **Frame Rate**: 30 fps
- **GOP Size**: 60 frames (2 seconds at 30fps)
- **Keyframe Interval**: 60 frames minimum
- **Preset**: veryfast (optimized for CPU efficiency)
- **Source**: testsrc2 pattern (synthetic test pattern)

**Audio Encoding:**
- **Codecs Available**:
  - AAC - Widely compatible, good quality at 128 kbps
  - Opus - Superior quality, better compression
- **Sample Rate**: 48000 Hz
- **Bitrate**: 128 kbps
- **Source**: sine wave tone at 1000 Hz

**Container Format:**
- RTMP: FLV
- RTSP: RTSP
- SRT: MPEGTS

**Codec Comparison:**
| Feature | H.264 | H.265 | AAC | Opus |
|---------|-------|-------|-----|------|
| Compatibility | Excellent | Good | Excellent | Good |
| Compression | Good | Excellent | Good | Excellent |
| CPU Usage | Lower | Higher | Lower | Similar |
| Quality | High | Higher | High | Higher |
| Bitrate Savings | Baseline | ~50% lower | Baseline | ~30% lower |

### Process Management

- All streams start simultaneously using a single FFmpeg process
- The FFmpeg process runs in the background
- Process ID is tracked for proper cleanup
- Signal handlers ensure cleanup on script termination

## 🤝 Contributing

Contributions are welcome! Feel free to:
- Report bugs
- Suggest features
- Submit pull requests

## 📝 Version

Current version: **2.0.0** (October 16, 2025)

See [CHANGELOG.md](CHANGELOG.md) for version history.

## 📄 License

This project is provided as-is for testing and development purposes.

## ⚠️ Disclaimer

This tool is designed for testing your own streaming infrastructure. Ensure you have permission before load testing any servers. Unauthorized load testing may be illegal and unethical.

---

**Questions or Issues?**

Check the logs in the `logs/` directory for detailed information about test runs and any errors encountered.
