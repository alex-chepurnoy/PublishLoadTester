#!/usr/bin/env python3

"""
WebRTC Publisher for Stream Load Tester

Description: Python component for WebRTC streaming with Wowza Engine integration.
             Handles WebRTC signaling, media pipeline setup, and connection management.

Author: Stream Load Tester Project
Version: 1.0
Date: October 15, 2025

Requirements:
    - Python 3.6+
    - aiortc
    - aiohttp
    - websockets
    - GStreamer with WebRTC plugins
"""

import argparse
import asyncio
import json
import logging
import sys
import time
import uuid
from datetime import datetime
from pathlib import Path
from typing import Optional, Dict, Any

try:
    import aiohttp
    from aiortc import RTCPeerConnection, RTCSessionDescription, RTCIceCandidate
    from aiortc.contrib.media import MediaPlayer, MediaRelay
    import websockets
except ImportError as e:
    print(f"Error: Missing required Python package: {e}")
    print("Install with: pip3 install aiortc aiohttp websockets")
    sys.exit(1)

# Configure logging
logger = logging.getLogger(__name__)

class ColoredFormatter(logging.Formatter):
    """Custom colored formatter for console output"""
    
    COLORS = {
        'DEBUG': '\033[0;36m',    # Cyan
        'INFO': '\033[0;32m',     # Green
        'WARNING': '\033[1;33m',  # Yellow
        'ERROR': '\033[0;31m',    # Red
        'CRITICAL': '\033[1;31m', # Bold Red
    }
    RESET = '\033[0m'
    
    def format(self, record):
        color = self.COLORS.get(record.levelname, self.RESET)
        record.levelname = f"{color}{record.levelname}{self.RESET}"
        return super().format(record)

class WebRTCPublisher:
    """WebRTC publisher with Wowza Engine signaling support"""
    
    def __init__(self, url: str, stream_name: str, bitrate: int, duration: int, log_file: Optional[str] = None):
        self.url = url
        self.stream_name = stream_name
        self.bitrate = bitrate
        self.duration = duration
        self.log_file = log_file
        
        # WebRTC components
        self.pc: Optional[RTCPeerConnection] = None
        
        # Media components
        self.media_player: Optional[MediaPlayer] = None
        self.relay = MediaRelay()
        
        # State tracking
        self.connected = False
        self.start_time = None
        self.session_id = str(uuid.uuid4())
        
        # Setup logging
        self.setup_logging()
    
    def setup_logging(self):
        """Configure logging for the WebRTC publisher"""
        
        # Create logger
        self.logger = logging.getLogger(f"webrtc-{self.stream_name}")
        self.logger.setLevel(logging.DEBUG)
        
        # Console handler
        console_handler = logging.StreamHandler()
        console_handler.setLevel(logging.INFO)
        console_formatter = ColoredFormatter(
            '[%(asctime)s] [%(levelname)s] [%(name)s] %(message)s',
            datefmt='%Y-%m-%d %H:%M:%S'
        )
        console_handler.setFormatter(console_formatter)
        self.logger.addHandler(console_handler)
        
        # File handler (if log file specified)
        if self.log_file:
            file_handler = logging.FileHandler(self.log_file)
            file_handler.setLevel(logging.DEBUG)
            file_formatter = logging.Formatter(
                '[%(asctime)s] [%(levelname)s] [%(name)s] %(message)s',
                datefmt='%Y-%m-%d %H:%M:%S'
            )
            file_handler.setFormatter(file_formatter)
            self.logger.addHandler(file_handler)
    
    def create_media_player(self) -> MediaPlayer:
        """Create GStreamer media player with test pattern and audio"""
        
        # GStreamer pipeline for test pattern and sine wave
        pipeline = (
            f"videotestsrc pattern=smpte100 ! "
            f"video/x-raw,width=1920,height=1080,framerate=30/1 ! "
            f"videoconvert ! "
            f"x264enc bitrate={self.bitrate} speed-preset=ultrafast tune=zerolatency ! "
            f"h264parse ! "
            f"avdec_h264 ! "
            f"videoconvert ! "
            f"queue ! "
            f"audiotestsrc wave=sine freq=1000 ! "
            f"audio/x-raw,rate=48000,channels=2 ! "
            f"audioconvert ! "
            f"audioresample ! "
            f"avenc_aac bitrate=128000 ! "
            f"aacparse ! "
            f"avdec_aac ! "
            f"audioconvert ! "
            f"queue"
        )
        
        self.logger.debug(f"GStreamer pipeline: {pipeline}")
        
        try:
            player = MediaPlayer(pipeline, format="gstreamer")
            self.logger.info("Created GStreamer media player")
            return player
        except Exception as e:
            self.logger.error(f"Failed to create media player: {e}")
            # Fallback to simple pattern if GStreamer fails
            self.logger.info("Attempting fallback media source...")
            return MediaPlayer("videotestsrc", format="gstreamer")
    
    async def create_peer_connection(self) -> RTCPeerConnection:
        """Create and configure WebRTC peer connection"""
        
        pc = RTCPeerConnection()
        
        # Add event handlers
        @pc.on("connectionstatechange")
        async def on_connectionstatechange():
            self.logger.info(f"Connection state changed: {pc.connectionState}")
            if pc.connectionState == "connected":
                self.connected = True
                self.logger.info(f"WebRTC connection established for stream: {self.stream_name}")
            elif pc.connectionState in ["failed", "closed"]:
                self.connected = False
                self.logger.warning(f"WebRTC connection lost for stream: {self.stream_name}")
        
        @pc.on("icegatheringstatechange")
        async def on_icegatheringstatechange():
            self.logger.debug(f"ICE gathering state: {pc.iceGatheringState}")
        
        @pc.on("iceconnectionstatechange")
        async def on_iceconnectionstatechange():
            self.logger.debug(f"ICE connection state: {pc.iceConnectionState}")
        
        return pc
    
    async def setup_media_tracks(self):
        """Setup media tracks for streaming"""
        
        try:
            # Create media player
            self.media_player = self.create_media_player()
            
            # Add video track
            if self.media_player.video:
                video_track = self.relay.subscribe(self.media_player.video)
                self.pc.addTrack(video_track)
                self.logger.info("Added video track to peer connection")
            
            # Add audio track
            if self.media_player.audio:
                audio_track = self.relay.subscribe(self.media_player.audio)
                self.pc.addTrack(audio_track)
                self.logger.info("Added audio track to peer connection")
                
        except Exception as e:
            self.logger.error(f"Failed to setup media tracks: {e}")
            raise
    
    async def connect_wowza_signaling(self) -> Dict[str, Any]:
        """Connect to Wowza Engine WebRTC signaling via WebSocket"""
        
        # Parse application name from URL
        # URL format: wss://domain:port/application
        application_name = self.url.rstrip('/').split('/')[-1]
        
        # Build signaling URL
        # User provides wss:// directly, just append endpoint
        signaling_url = f"{self.url.rstrip('/')}/webrtc-session.json"
        
        self.logger.info(f"Connecting to Wowza signaling: {signaling_url}")
        self.logger.info(f"Application: {application_name}, Stream: {self.stream_name}")
        
        # Prepare signaling request
        signaling_request = {
            "direction": "publish",
            "command": "sendOffer",
            "streamInfo": {
                "applicationName": application_name,
                "streamName": self.stream_name,
                "sessionId": self.session_id
            }
        }
        
        try:
            # Create offer
            offer = await self.pc.createOffer()
            await self.pc.setLocalDescription(offer)
            
            # Add SDP to signaling request
            signaling_request["sdp"] = {
                "type": offer.type,
                "sdp": offer.sdp
            }
            
            self.logger.debug(f"Sending offer to Wowza: {json.dumps(signaling_request, indent=2)}")
            
            # Connect via WebSocket
            async with websockets.connect(signaling_url, ssl=True) as ws:
                # Send signaling request
                await ws.send(json.dumps(signaling_request))
                self.logger.debug("Offer sent, waiting for response...")
                
                # Receive signaling response
                response_text = await ws.recv()
                signaling_response = json.loads(response_text)
                
                self.logger.info("Received signaling response from Wowza")
                self.logger.debug(f"Signaling response: {json.dumps(signaling_response, indent=2)}")
                return signaling_response
                    
        except Exception as e:
            self.logger.error(f"Wowza signaling failed: {e}")
            raise
    
    async def handle_signaling_response(self, response: Dict[str, Any]):
        """Handle signaling response from Wowza Engine"""
        
        try:
            # Check for successful response
            if response.get("status") != 200:
                error_msg = response.get("statusDescription", "Unknown error")
                raise Exception(f"Wowza signaling error: {error_msg}")
            
            # Extract SDP answer
            sdp_data = response.get("sdp")
            if not sdp_data:
                raise Exception("No SDP data in signaling response")
            
            # Create and set remote description
            answer = RTCSessionDescription(
                sdp=sdp_data["sdp"],
                type=sdp_data["type"]
            )
            
            await self.pc.setRemoteDescription(answer)
            self.logger.info("Set remote description from Wowza answer")
            
            # Handle ICE candidates if present
            ice_candidates = response.get("iceCandidates", [])
            for candidate_data in ice_candidates:
                candidate = RTCIceCandidate(
                    candidate=candidate_data["candidate"],
                    sdpMid=candidate_data.get("sdpMid"),
                    sdpMLineIndex=candidate_data.get("sdpMLineIndex")
                )
                await self.pc.addIceCandidate(candidate)
                self.logger.debug("Added ICE candidate")
            
        except Exception as e:
            self.logger.error(f"Failed to handle signaling response: {e}")
            raise
    
    async def monitor_connection(self):
        """Monitor the WebRTC connection during streaming"""
        
        self.start_time = time.time()
        duration_seconds = self.duration * 60
        
        self.logger.info(f"Starting connection monitoring for {self.duration} minutes")
        
        while time.time() - self.start_time < duration_seconds:
            if not self.connected and self.pc.connectionState in ["failed", "closed"]:
                self.logger.error("Connection lost, attempting to reconnect...")
                # In a production system, you might implement reconnection logic here
                break
            
            # Log status every 30 seconds
            elapsed = time.time() - self.start_time
            remaining = duration_seconds - elapsed
            
            if int(elapsed) % 30 == 0:
                self.logger.info(
                    f"Stream status - Connected: {self.connected}, "
                    f"State: {self.pc.connectionState}, "
                    f"Remaining: {int(remaining)}s"
                )
            
            await asyncio.sleep(1)
        
        self.logger.info("Monitoring period completed")
    
    async def cleanup(self):
        """Clean up resources"""
        
        self.logger.info("Cleaning up WebRTC publisher resources")
        
        try:
            # Close peer connection
            if self.pc:
                await self.pc.close()
                self.logger.debug("Closed peer connection")
            
            # Close media player
            if self.media_player:
                # Note: MediaPlayer doesn't have an async close method
                self.logger.debug("Stopped media player")
                
        except Exception as e:
            self.logger.error(f"Error during cleanup: {e}")
    
    async def start_streaming(self):
        """Main streaming function"""
        
        try:
            self.logger.info(f"Starting WebRTC stream: {self.stream_name}")
            self.logger.info(f"Target URL: {self.url}")
            self.logger.info(f"Bitrate: {self.bitrate}k")
            self.logger.info(f"Duration: {self.duration}m")
            
            # Create peer connection
            self.pc = await self.create_peer_connection()
            
            # Setup media tracks
            await self.setup_media_tracks()
            
            # Connect to Wowza signaling
            signaling_response = await self.connect_wowza_signaling()
            
            # Handle signaling response
            await self.handle_signaling_response(signaling_response)
            
            # Wait for connection to establish
            connection_timeout = 30  # seconds
            start_wait = time.time()
            
            while not self.connected and time.time() - start_wait < connection_timeout:
                if self.pc.connectionState == "failed":
                    raise Exception("WebRTC connection failed")
                await asyncio.sleep(0.5)
            
            if not self.connected:
                raise Exception("Connection timeout - WebRTC connection not established")
            
            # Monitor the connection
            await self.monitor_connection()
            
        except Exception as e:
            self.logger.error(f"Streaming failed: {e}")
            raise
        finally:
            await self.cleanup()

async def main():
    """Main function for command line usage"""
    
    parser = argparse.ArgumentParser(description="WebRTC Publisher for Stream Load Tester")
    parser.add_argument("--url", required=True, help="Wowza WebRTC signaling URL")
    parser.add_argument("--stream-name", required=True, help="Stream name")
    parser.add_argument("--bitrate", type=int, default=2000, help="Bitrate in kbps")
    parser.add_argument("--duration", type=int, default=30, help="Duration in minutes")
    parser.add_argument("--log-file", help="Log file path")
    parser.add_argument("--verbose", "-v", action="store_true", help="Verbose logging")
    
    args = parser.parse_args()
    
    # Configure root logging level
    if args.verbose:
        logging.basicConfig(level=logging.DEBUG)
    else:
        logging.basicConfig(level=logging.INFO)
    
    # Create and run publisher
    publisher = WebRTCPublisher(
        url=args.url,
        stream_name=args.stream_name,
        bitrate=args.bitrate,
        duration=args.duration,
        log_file=args.log_file
    )
    
    try:
        await publisher.start_streaming()
        print(f"WebRTC streaming completed successfully for {args.stream_name}")
        return 0
    except Exception as e:
        print(f"WebRTC streaming failed: {e}")
        return 1

if __name__ == "__main__":
    # Check for basic requirements
    try:
        import aiortc
        import aiohttp
        import websockets
    except ImportError as e:
        print(f"Error: Missing required dependencies: {e}")
        print("Install with: pip3 install aiortc aiohttp websockets")
        sys.exit(1)
    
    # Run the async main function
    try:
        exit_code = asyncio.run(main())
        sys.exit(exit_code)
    except KeyboardInterrupt:
        print("\nWebRTC publisher interrupted by user")
        sys.exit(130)
    except Exception as e:
        print(f"Unexpected error: {e}")
        sys.exit(1)