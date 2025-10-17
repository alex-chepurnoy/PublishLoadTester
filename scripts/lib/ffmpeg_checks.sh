#!/bin/bash

# Shared FFmpeg capability helpers for PublishLoadTester scripts.
# These helpers centralize how we detect FFmpeg availability and the
# presence of required codecs or lavfi sources.

# Tokens representing required FFmpeg capabilities.
FFMPEG_H264_ENCODERS=(
    "libx264"
    "libx264rgb"
    "h264_nvenc"
    "h264_qsv"
    "h264_vaapi"
    "h264_amf"
    "h264_v4l2m2m"
)

FFMPEG_H265_ENCODERS=(
    "libx265"
    "hevc_nvenc"
    "hevc_qsv"
    "hevc_vaapi"
    "hevc_amf"
    "hevc_v4l2m2m"
)

FFMPEG_VP9_ENCODERS=(
    "libvpx-vp9"
    "vp9_vaapi"
    "vp9_qsv"
)

FFMPEG_AAC_ENCODERS=(
    "aac"
    "aac_fixed"
    "libfdk_aac"
    "libvo_aacenc"
)

FFMPEG_TESTSRC_FILTERS=("testsrc2")
FFMPEG_SINE_FILTERS=("sine")

# Reset cached FFmpeg capability data.
ffmpeg_reset_capability_cache() {
    unset _FFMPEG_ENCODERS_CACHE
    unset _FFMPEG_ENCODERS_EXIT
    unset _FFMPEG_FILTERS_CACHE
    unset _FFMPEG_FILTERS_EXIT
}

# Global ffmpeg binary path (resolved on demand)
FFMPEG_BIN=""

# Return 0 when FFmpeg is available in PATH. Sets FFMPEG_BIN to the discovered binary.
ffmpeg_is_available() {
    if [[ -n "${FFMPEG_BIN}" && -x "${FFMPEG_BIN}" ]]; then
        return 0
    fi

    # Prefer native ffmpeg
    if command -v ffmpeg >/dev/null 2>&1; then
        FFMPEG_BIN=$(command -v ffmpeg)
        return 0
    fi

    # Fall back to Windows ffmpeg.exe (useful under WSL with Windows-installed ffmpeg)
    if command -v ffmpeg.exe >/dev/null 2>&1; then
        FFMPEG_BIN=$(command -v ffmpeg.exe)
        return 0
    fi

    # As a last resort, search PATH entries for ffmpeg or ffmpeg.exe
    IFS=':' read -ra _p <<< "$PATH"
    for _dir in "${_p[@]}"; do
        if [[ -x "${_dir}/ffmpeg" ]]; then
            FFMPEG_BIN="${_dir}/ffmpeg"
            return 0
        fi
        if [[ -x "${_dir}/ffmpeg.exe" ]]; then
            FFMPEG_BIN="${_dir}/ffmpeg.exe"
            return 0
        fi
    done

    return 1
}

# Internal: populate encoder cache when needed.
__ffmpeg_cache_encoders() {
    if [[ -n "${_FFMPEG_ENCODERS_EXIT:+set}" ]]; then
        return 0
    fi

    if ! ffmpeg_is_available; then
        _FFMPEG_ENCODERS_EXIT=127
        _FFMPEG_ENCODERS_CACHE=""
        return 0
    fi

    _FFMPEG_ENCODERS_CACHE=$("${FFMPEG_BIN}" -hide_banner -loglevel error -encoders 2>/dev/null || true)
    _FFMPEG_ENCODERS_EXIT=$?
}

# Internal: populate filter cache when needed.
__ffmpeg_cache_filters() {
    if [[ -n "${_FFMPEG_FILTERS_EXIT:+set}" ]]; then
        return 0
    fi

    if ! ffmpeg_is_available; then
        _FFMPEG_FILTERS_EXIT=127
        _FFMPEG_FILTERS_CACHE=""
        return 0
    fi

    _FFMPEG_FILTERS_CACHE=$("${FFMPEG_BIN}" -hide_banner -loglevel error -filters 2>/dev/null || true)
    _FFMPEG_FILTERS_EXIT=$?
}

# Check if any encoder token in "$@" is available.
# Returns: 0 present, 1 missing, 2 unable to determine.
ffmpeg_has_any_encoder() {
    __ffmpeg_cache_encoders
    local status=${_FFMPEG_ENCODERS_EXIT:-127}

    if (( status != 0 )); then
        return 2
    fi

    local token
    for token in "$@"; do
        if printf '%s\n' "${_FFMPEG_ENCODERS_CACHE}" | grep -Eq "[[:space:]]${token}([[:space:]]|$)"; then
            return 0
        fi
    done

    return 1
}

# Check if any filter token in "$@" is available.
# Returns: 0 present, 1 missing, 2 unable to determine.
ffmpeg_has_any_filter() {
    __ffmpeg_cache_filters
    local status=${_FFMPEG_FILTERS_EXIT:-127}

    if (( status != 0 )); then
        return 2
    fi

    local token
    for token in "$@"; do
        if printf '%s\n' "${_FFMPEG_FILTERS_CACHE}" | grep -Eq "[[:space:]]${token}([[:space:]]|$)"; then
            return 0
        fi
    done

    return 1
}
