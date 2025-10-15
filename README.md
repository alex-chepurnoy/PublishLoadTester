# Stream Load Tester

A comprehensive Linux-based tool for testing streaming infrastructure by generating multiple concurrent streams to various protocols (RTMP, RTSP, SRT, WebRTC).

## 🚀 Features

- **Multi-Protocol Support**: RTMP, RTSP, SRT, and WebRTC streaming
- **Efficient Single-Encode Mode**: For RTMP/RTSP/SRT, encode once and send to multiple destinations (80-90% CPU reduction)
- **Configurable Load Testing**: Multiple concurrent connections with controlled ramp-up
- **Test Pattern Generation**: Standardized 1080p test video with sine wave audio
- **WebRTC Integration**: Specialized WebRTC support with Wowza Engine signaling
- **Comprehensive Logging**: Detailed logging and monitoring capabilities
- **Dependency Management**: Automatic dependency checking and installation
- **Resource Management**: Intelligent process management and cleanup utilities
- **Interactive Configuration**: User-friendly prompts for server, application, and stream configuration

## 📋 Requirements

### System Requirements
- Linux distribution (Ubuntu 18.04+ recommended)
- 2GB RAM minimum
- 1GB available disk space
- Network connectivity to target streaming servers

### Software Dependencies
- **FFmpeg** with H.264 and AAC support
- **Bash** 4.0+
- **Python 3.6+** (for WebRTC)
- **GStreamer 1.0+** with WebRTC plugins (for WebRTC)

## 🔧 Installation

### Quick Installation (Ubuntu/Debian)

```bash
# Clone or download the project
git clone <repository-url>
cd stream-load-tester

# Run the installation script
chmod +x scripts/install.sh
./scripts/install.sh
```

### Manual Installation

```bash
# Ubuntu/Debian
sudo apt update
sudo apt install ffmpeg gstreamer1.0-tools gstreamer1.0-plugins-good \
                 gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly \
                 python3 python3-pip python3-venv

# Python WebRTC packages (choose one method):

# Method 1: Virtual environment (recommended for newer systems)
python3 -m venv ~/.local/share/stream-load-tester-venv
source ~/.local/share/stream-load-tester-venv/bin/activate
pip install aiortc aiohttp websockets

# Method 2: User installation (older systems)
pip3 install --user aiortc aiohttp websockets

# Method 3: System packages (if available)
sudo apt install python3-aiortc python3-aiohttp python3-websockets

# Make scripts executable
chmod +x stream_load_tester.sh check_dependencies.sh webrtc_publisher.py scripts/*.sh
```

### Other Distributions

<details>
<summary>Fedora/RHEL/CentOS</summary>

```bash
# Enable RPM Fusion for FFmpeg
sudo dnf install https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm

# Install packages
sudo dnf install ffmpeg gstreamer1-tools gstreamer1-plugins-good \
                 gstreamer1-plugins-bad-free python3 python3-pip
pip3 install aiortc aiohttp websockets
```
</details>

<details>
<summary>Arch Linux</summary>

```bash
sudo pacman -S ffmpeg gstreamer gst-plugins-good gst-plugins-bad \
               gst-plugins-ugly python python-pip
pip install aiortc aiohttp websockets
```
</details>

## ✅ Dependency Verification

Check if all dependencies are installed:

```bash
# Check all dependencies
./check_dependencies.sh

# Check basic dependencies only (RTMP/RTSP/SRT)
./check_dependencies.sh basic

# Check WebRTC dependencies only
./check_dependencies.sh webrtc
```

## 🚀 Usage

### Interactive Mode

```bash
./stream_load_tester.sh
```

The script will guide you through:
1. Protocol selection (RTMP, RTSP, SRT, WebRTC)
2. Stream configuration (bitrate)
3. Server configuration:
   - **Server URL**: Base server address (e.g., `rtmp://192.168.1.100:1935`)
   - **Application name**: Application/mount point (e.g., `live`)
   - **Stream name**: Base name for streams (e.g., `test`)
4. Load testing parameters (connections, ramp-up time, duration)
5. Test execution and monitoring

**Note**: For RTMP/RTSP/SRT, the script will automatically use efficient single-encode mode, reducing CPU usage by 80-90% compared to multiple encodes.

### Command Line Mode

```bash
./stream_load_tester.sh \
    --protocol rtmp \
    --bitrate 2000 \
    --url "rtmp://192.168.1.100:1935/live" \
    --connections 10 \
    --ramp-time 5 \
    --stream-name "test" \
    --duration 30
```

**Important**: URL format must include the application name but NOT the stream name:
- ✅ Correct: `rtmp://server:1935/live`
- ❌ Wrong: `rtmp://server:1935/live/stream001`

The stream name is specified separately with `--stream-name`, and the script will append numbers (e.g., `test001`, `test002`, etc.)

### Command Line Options

| Option | Description | Example |
|--------|-------------|---------|
| `--protocol` | Streaming protocol | `rtmp`, `rtsp`, `srt`, `webrtc` |
| `--bitrate` | Video bitrate in kbps | `2000` |
| `--url` | Server URL with application (no stream name) | `rtmp://server:1935/live` |
| `--connections` | Number of concurrent streams | `10` |
| `--ramp-time` | Ramp-up time in minutes (WebRTC only) | `5` |
| `--stream-name` | Base stream name (numbers appended) | `test` |
| `--duration` | Test duration in minutes | `30` |
| `--debug` | Enable debug output | |
| `--help` | Show help message | |

## 🌐 Protocol-Specific Configuration

### RTMP
```bash
# URL Format (application only, no stream name)
rtmp://server:port/application

# Example Configuration
Server URL: rtmp://192.168.1.100:1935/live
Stream Name: test
# Results in streams: test001, test002, test003, etc.
```

**Encoding Mode**: Single encode, multiple outputs (efficient)

### RTSP
```bash
# URL Format (application only, no stream name)
rtsp://server:port/application

# Example Configuration
Server URL: rtsp://192.168.1.100:554/live
Stream Name: test
# Results in streams: test001, test002, test003, etc.
```

**Encoding Mode**: Single encode, multiple outputs (efficient)

### SRT (Wowza Format)
```bash
# URL Format (streamid with application only)
srt://server:port?streamid=application

# Example Configuration
Server URL: srt://192.168.1.100:9999?streamid=live
Stream Name: test

# Actual Wowza publish URLs generated (automatic):
# srt://192.168.1.100:9999?streamid=#!::m=publish,r=live/_definst_/test001
# srt://192.168.1.100:9999?streamid=#!::m=publish,r=live/_definst_/test002
# srt://192.168.1.100:9999?streamid=#!::m=publish,r=live/_definst_/test003
```

**Note**: The script automatically converts your simple `streamid=application` format into Wowza's required publish format: `streamid=#!::m=publish,r=application/_definst_/stream-name`

**Encoding Mode**: Single encode, multiple outputs (efficient)

### WebRTC (Wowza Format)
```bash
# URL Format (WebSocket URL with application)
wss://domain:port/application

# Example Configuration
Server: wss://wowza.example.com:443
Application: webrtc
Result URL: wss://wowza.example.com:443/webrtc
Stream Name: test

# Signaling endpoint used (automatic):
# wss://wowza.example.com:443/webrtc/webrtc-session.json

# Streams published:
# Application: webrtc, Stream names: test001, test002, test003, etc.
```

**Note**: 
- WebRTC requires secure WebSocket connection (wss://)
- SSL/TLS certificate must be properly configured on Wowza server
- The script automatically extracts the application name from the URL
- Signaling uses WebSocket to `/webrtc-session.json` endpoint
- Each stream maintains its own WebRTC peer connection

**Encoding Mode**: Multiple processes (one per stream) - required for WebRTC

## ⚡ Performance Optimization

### Single-Encode Mode (RTMP/RTSP/SRT)
For RTMP, RTSP, and SRT protocols, the tool automatically uses FFmpeg's **tee muxer** to encode video once and send to multiple destinations simultaneously.

**Benefits**:
- 🚀 **80-90% CPU reduction** for 10+ streams
- 💾 **Lower memory usage** (single encode buffer)
- ⚡ **Faster startup** (no ramping needed)
- 🎯 **Perfect synchronization** (all streams from same encode)

**Example CPU Usage**:
- Old method: 10 streams @ 2000kbps = ~20% CPU × 10 = 200% CPU
- New method: 10 streams @ 2000kbps = ~25% CPU total

### Multi-Process Mode (WebRTC)
WebRTC requires separate encoding contexts per connection, so each stream runs as an independent process with ramping support.

## 📊 Output and Logging

### Console Output
The tool provides real-time status updates including:
- Connection establishment progress
- Active stream count
- Error notifications
- Performance metrics

### Log Files
Detailed logs are saved to `logs/stream_test_YYYYMMDD_HHMMSS.log` containing:
- Timestamped events
- Connection status changes
- Error details
- Performance data

### Example Log Format
```
[2025-10-15 10:30:15] [INFO] [MAIN] Starting load test: 10 RTMP streams (single encode, multiple outputs)
[2025-10-15 10:30:15] [INFO] [MAIN] Using efficient single-process mode to reduce CPU usage
[2025-10-15 10:30:15] [INFO] [MAIN] Multi-output FFmpeg started with PID: 12345
[2025-10-15 10:30:16] [INFO] [STREAM-001] Stream configured: test001
[2025-10-15 10:30:16] [INFO] [STREAM-002] Stream configured: test002
[2025-10-15 10:30:26] [INFO] [MONITOR] FFmpeg process running, 10 streams active, Time remaining: 1794s
[2025-10-15 10:35:15] [INFO] [MONITOR] FFmpeg process running, 10 streams active, Time remaining: 1200s
```

## 🛠 Utility Scripts

### Cleanup Tool
Remove all running processes and clean up logs:

```bash
# Interactive cleanup
./scripts/cleanup.sh

# Force cleanup without confirmation
./scripts/cleanup.sh --force

# Clean logs only
./scripts/cleanup.sh --logs-only

# Kill processes only
./scripts/cleanup.sh --processes-only
```

### Installation Script
Automated dependency installation:

```bash
# Full installation with confirmation
./scripts/install.sh

# Automatic installation
./scripts/install.sh --yes

# Skip WebRTC packages
./scripts/install.sh --no-webrtc
```

## 📁 Project Structure

```
stream-load-tester/
├── stream_load_tester.sh          # Main application script
├── check_dependencies.sh          # Dependency verification
├── webrtc_publisher.py            # WebRTC streaming component
├── PRD_Stream_Load_Tester.md      # Product Requirements Document
├── README.md                      # This file
├── config/
│   └── default.conf               # Default configuration settings
├── logs/                          # Log file directory
└── scripts/
    ├── cleanup.sh                 # Process and file cleanup
    └── install.sh                 # Automated installation
```

## ⚙ Configuration

### Environment Variables
- `LOG_LEVEL`: Set logging verbosity (`DEBUG`, `INFO`, `WARN`, `ERROR`)
- `MAX_CONNECTIONS`: Override maximum connection limit
- `DEFAULT_BITRATE`: Set default bitrate value
- `DEBUG`: Enable debug output (`true`/`false`)

### Configuration File
Modify `config/default.conf` to change default settings:
- Stream parameters (bitrate, resolution, codecs)
- Protocol-specific settings
- Resource limits and timeouts
- Logging configuration

## 🔍 Troubleshooting

### Common Issues

**FFmpeg not found**
```bash
# Ubuntu/Debian
sudo apt install ffmpeg

# Check installation
ffmpeg -version
```

**FFmpeg missing codecs (H.264, AAC, test sources)**
This is common on Ubuntu/Debian where FFmpeg lacks certain codecs:

```bash
# Quick Fix: Use the dedicated fix script
chmod +x scripts/fix_ffmpeg_codecs.sh
./scripts/fix_ffmpeg_codecs.sh

# Manual fixes (choose one method):

# Method 1: Install codec packages
sudo apt install libavcodec-extra ubuntu-restricted-extras

# Method 2: Install from snap (includes all codecs)
sudo snap install ffmpeg
sudo ln -sf /snap/bin/ffmpeg /usr/local/bin/ffmpeg

# Method 3: Install static build (always works)
wget https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz
tar -xf ffmpeg-release-amd64-static.tar.xz
sudo cp ffmpeg-*-static/ffmpeg /usr/local/bin/

# Verify codecs are available
ffmpeg -encoders | grep libx264  # Should show H.264 encoder
ffmpeg -encoders | grep aac      # Should show AAC encoder
```

**WebRTC dependencies missing**
```bash
# Install Python packages
pip3 install aiortc aiohttp websockets

# If you get "externally-managed-environment" error:
# Option 1: Use virtual environment (recommended)
python3 -m venv ~/.local/share/stream-load-tester-venv
source ~/.local/share/stream-load-tester-venv/bin/activate
pip install aiortc aiohttp websockets

# Option 2: Use --break-system-packages (if allowed)
pip3 install --break-system-packages --user aiortc aiohttp websockets

# Option 3: Use pipx (if available)
pipx install aiortc
pipx install aiohttp
pipx install websockets

# Install GStreamer WebRTC plugins
sudo apt install gstreamer1.0-plugins-bad
```

**Connection failures**
- Verify server URL and credentials
- Check firewall settings
- Test with a single connection first
- Review server logs for errors

**Python "externally-managed-environment" error**
This is a common issue with newer Linux distributions that protect the system Python environment:

```bash
# Quick Fix: Use the dedicated fix script
chmod +x scripts/fix_python_packages.sh
./scripts/fix_python_packages.sh

# Or let the install script handle it automatically:
./scripts/install.sh

# Manual virtual environment setup:
sudo apt install python3-full python3-venv  # Ubuntu/Debian
python3 -m venv ~/.local/share/stream-load-tester-venv
source ~/.local/share/stream-load-tester-venv/bin/activate
pip install aiortc aiohttp websockets

# System packages method (if available):
sudo apt install python3-aiortc python3-aiohttp python3-websockets

# Last resort (not recommended):
pip3 install --break-system-packages --user aiortc aiohttp websockets
```

**Performance issues**
- Reduce number of concurrent connections
- Lower bitrate settings
- Check system resources (CPU, memory, network)
- Monitor system load during testing

### Debug Mode
Enable verbose logging for troubleshooting:

```bash
DEBUG=true ./stream_load_tester.sh --verbose
```

### Log Analysis
Check logs for detailed error information:

```bash
# View latest log
tail -f logs/stream_test_*.log

# Search for errors
grep ERROR logs/stream_test_*.log

# Monitor specific stream
grep "STREAM-001" logs/stream_test_*.log
```

## 📈 Performance Guidelines

### Recommended Limits
- **Connections**: Start with 5-10, can scale to 50+ with single-encode mode
- **Bitrate**: 500-5000 kbps per stream for testing
- **Ramp-up time**: Only applies to WebRTC (1-5 minutes recommended)
- **Duration**: 5-60 minutes for typical tests

### System Resources

**Single-Encode Mode (RTMP/RTSP/SRT)**:
- **CPU**: ~1-3% total (regardless of stream count)
- **Memory**: ~100-200MB total
- **Network**: Bitrate × connections

**Multi-Process Mode (WebRTC)**:
- **CPU**: ~1-2% per stream
- **Memory**: ~50-100MB per stream
- **Network**: Bitrate × connections

### Optimization Tips
- Use single-encode mode for RTMP/RTSP/SRT (automatic)
- Use lower bitrates for connection testing
- For WebRTC, implement gradual ramp-up for large-scale tests
- Monitor system resources during testing
- Use cleanup scripts to manage resources

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/new-feature`)
3. Commit your changes (`git commit -am 'Add new feature'`)
4. Push to the branch (`git push origin feature/new-feature`)
5. Create a Pull Request

## 📝 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🆘 Support

### Getting Help
- Check the troubleshooting section above
- Run dependency checker: `./check_dependencies.sh`
- Review log files for detailed error information
- Use verbose mode for additional debugging output

### Reporting Issues
When reporting issues, please include:
- Linux distribution and version
- Output of `./check_dependencies.sh`
- Command line used
- Relevant log file excerpts
- Expected vs actual behavior

### Feature Requests
We welcome feature requests! Please describe:
- Use case and requirements
- Proposed implementation approach
- Any relevant technical considerations

## 📚 Additional Resources

- [FFmpeg Documentation](https://ffmpeg.org/documentation.html)
- [GStreamer Documentation](https://gstreamer.freedesktop.org/documentation/)
- [WebRTC Specification](https://webrtc.org/)
- [Wowza Engine Documentation](https://www.wowza.com/docs/wowza-streaming-engine)

---

**Note**: This tool is designed for testing purposes. Ensure you have permission to test against target streaming servers and comply with their usage policies.