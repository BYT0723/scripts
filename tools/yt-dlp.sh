#!/usr/bin/env bash

yt_download() {
    local url="$1" mode="$2" fmt="$3"

    command -v yt-dlp >/dev/null || {
        echo "yt-dlp missing" >&2
        return 1
    }

    command -v ffmpeg >/dev/null || {
        echo "ffmpeg missing" >&2
        return 1
    }

    mkdir -p "$YT_DL_DIR"

    local ytdlp_opts=(
        --cookies-from-browser "${BROWSER:-firefox}"
        -o "$YT_DL_DIR/%(title)s.%(ext)s"
    )

    case "$mode" in
    audio)
        ytdlp_opts+=(-f bestaudio)
        ;;
    video)
        local height="${fmt:-1080}"
        ytdlp_opts+=(
            -f "bestvideo[height<=${height}]+bestaudio"
        )
        ;;
    raw)
        ytdlp_opts+=(-f "$fmt")
        ;;
    *)
        echo "Unknown mode: $mode" >&2
        return 1
        ;;
    esac

    yt-dlp "${ytdlp_opts[@]}" "$url" || return 1

    if [[ "$mode" == "audio" ]]; then
        extract_opus "$YT_DL_DIR" || return 1
    fi
}

extract_opus() {
    local target="${1:-.}"

    # 依赖检查
    for cmd in ffmpeg ffprobe; do
        command -v "$cmd" >/dev/null 2>&1 || {
            echo "Missing dependency: $cmd" >&2
            return 1
        }
    done

    local files=()

    if [[ -d "$target" ]]; then
        shopt -s nullglob
        files=("$target"/*.webm)
        shopt -u nullglob
    elif [[ -f "$target" ]]; then
        files=("$target")
    else
        echo "Invalid path: $target"
        return 1
    fi

    for file in "${files[@]}"; do
        local base="${file%.webm}"
        local output="${base}.opus"

        if [[ -f "$output" ]]; then
            echo "Skip (exists): $output"
            continue
        fi

        echo "Processing: $file"

        # metadata
        local title artist
        title=$(ffprobe -v quiet \
            -show_entries format_tags=title \
            -of default=noprint_wrappers=1:nokey=1 "$file")

        artist=$(ffprobe -v quiet \
            -show_entries format_tags=artist \
            -of default=noprint_wrappers=1:nokey=1 "$file")

        title=${title:-$(basename "$base")}
        artist=${artist:-Unknown}

        # debug info
        ffprobe -v error -select_streams a:0 \
            -show_entries stream=codec_name,bit_rate \
            -of default=noprint_wrappers=1 "$file"

        # extract
        if ffmpeg -loglevel error \
            -i "$file" \
            -vn \
            -map_metadata 0 \
            -metadata title="$title" \
            -metadata artist="$artist" \
            -c:a copy \
            "$output"; then

            rm "$file"
            echo "✔ Done -> $output"
        else
            echo "✘ Failed: $file"
        fi
    done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    [[ -z "${YT_DL_DIR:-}" ]] && {
        echo "YT_DL_DIR not set" >&2
        exit 1
    }

    case "$1" in
    audio)
        shift
        yt_download "$1" audio
        ;;
    video)
        shift
        yt_download "$1" video "$2"
        ;;
    raw)
        shift
        yt_download "$1" raw "$2"
        ;;
    extra)
        shift
        extract_opus "$@"
        ;;
    esac
fi
