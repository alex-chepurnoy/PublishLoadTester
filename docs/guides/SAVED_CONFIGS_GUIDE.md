# Save and Reuse Test Configurations - Quick Guide

## Overview

Version 2.1.0 adds the ability to save successful test configurations and reuse them in future sessions. This makes it easy to run repetitive tests or maintain a library of common test scenarios.

## How It Works

### 1. Saving a Configuration

After a test completes successfully, you'll see:

```
==============================================================
                 SAVE TEST CONFIGURATION
==============================================================

Would you like to save this test configuration for future use? (y/N)
```

If you choose **Yes**:

1. **Auto-generated name** is created:
   - Format: `PROTOCOL_RESOLUTION_VIDEOCODEC_AUDIOCODEC_BITRATE_CONNECTIONS`
   - Example: `RTMP_1080P_H264_AAC_4000k_5conn`

2. **Optional custom suffix**:
   - You can append descriptive text
   - Example: `RTMP_1080P_H264_AAC_4000k_5conn_ProductionTest`
   - Special characters are automatically converted to underscores

3. **Saved location**: `previous_runs/CONFIG_NAME.conf`

### 2. Loading a Previous Configuration

Next time you run the tool (without command-line args), you'll see:

```
==============================================================
                  PREVIOUS TEST RUNS
==============================================================

Found 3 previous test configuration(s):

  1. RTMP_1080P_H264_AAC_4000k_5conn_ProductionTest
  2. SRT_4K_H265_OPUS_8000k_10conn
  3. RTSP_720P_H264_AAC_2500k_3conn_LabTest

  0. Start new test

Select a configuration (0-3):
```

### 3. Configuration Preview

After selecting a configuration, you'll see a summary:

```
==============================================================
              CONFIGURATION PREVIEW
==============================================================
Protocol:           rtmp
Resolution:         1080p (1920x1080)
Video Codec:        h264
Audio Codec:        aac
Bitrate:            4000k
Connections:        5
Duration:           30m

Server URL:         rtmp://192.168.1.100:1935/live
Stream Name:        test
==============================================================

Options:
  1. Run with these settings
  2. Change server URL, app name, and stream name
  0. Cancel

Select option (0-2):
```

### 4. Modification Options

**Option 1**: Run as-is
- Starts test immediately with saved settings

**Option 2**: Update server details
- Change server URL (IP address, port, application)
- Change stream name
- Keep all other settings (resolution, codec, bitrate, connections, duration)
- Perfect for running the same test against different servers

## Configuration File Format

Configuration files are simple shell scripts:

```bash
# Stream Load Tester Configuration
# Saved: 2025-10-16 18:44:23

PROTOCOL="rtmp"
RESOLUTION="1080p"
VIDEO_CODEC="h264"
AUDIO_CODEC="aac"
BITRATE="4000"
SERVER_URL="rtmp://192.168.1.100:1935/live"
NUM_CONNECTIONS="5"
STREAM_NAME="test"
DURATION="30"
```

You can manually create or edit these files if needed.

## Use Cases

1. **Production Testing**
   - Save configurations for different production environments
   - Example: `RTMP_1080P_H264_AAC_4000k_10conn_Production`

2. **Lab Testing**
   - Maintain different test scenarios for development
   - Example: `RTSP_720P_H265_OPUS_2500k_5conn_LabTest`

3. **Performance Benchmarking**
   - Save configurations at different quality levels
   - Example: `SRT_4K_H265_AAC_15000k_20conn_HighLoad`

4. **Customer Configurations**
   - Save specific customer test requirements
   - Example: `RTMP_1080P_H264_AAC_5000k_10conn_CustomerA`

5. **Quick Server Switching**
   - Same test configuration, different target servers
   - Use "Change server URL" option to update IP/hostname

## Tips

- **Naming Convention**: Use descriptive suffixes to identify test purpose
- **Organization**: Group related tests with common prefixes
- **Version Control**: The `previous_runs/` directory can be committed to git to share configs with team
- **Documentation**: Add comments to config files for complex test scenarios
- **Cleanup**: Delete unused configurations by removing `.conf` files from `previous_runs/`

## Example Workflow

```bash
# First run - create and save configuration
./stream_load_tester.sh
# ... complete interactive setup ...
# ... test runs successfully ...
# Save as: RTMP_1080P_H264_AAC_4000k_5conn_WeeklyLoadTest

# Future runs - reuse configuration
./stream_load_tester.sh
# Select: 1. RTMP_1080P_H264_AAC_4000k_5conn_WeeklyLoadTest
# Option: 1. Run with these settings
# Test starts immediately!

# Or modify server for different environment
./stream_load_tester.sh
# Select: 1. RTMP_1080P_H264_AAC_4000k_5conn_WeeklyLoadTest
# Option: 2. Change server URL, app name, and stream name
# Update: rtmp://192.168.2.200:1935/live (staging server)
# Test runs against new server with same quality settings
```

## Command-Line Mode

**Note**: The previous runs menu is only shown in interactive mode (when running without command-line arguments). If you use command-line mode with `--protocol`, `--server`, etc., the script will not prompt for previous configurations.

## Files

- **Configuration Storage**: `previous_runs/`
- **Example Config**: `previous_runs/EXAMPLE_RTMP_1080P_H264_AAC_4000k_5conn.conf.example`
- **Keep File**: `previous_runs/.gitkeep` (ensures directory is tracked in git)
