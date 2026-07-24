#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/lib/config.sh"
source "$SCRIPT_DIR/lib/tmdb.sh"
source "$SCRIPT_DIR/lib/omdb.sh"

###############################################################################
# CHECK CONFIGURATION
###############################################################################

if [[ -z "$MEDIA_DIR" || "$MEDIA_DIR" == "/CHANGE/THIS/PATH" ]]; then
    echo
    echo "ERROR: Please configure MEDIA_DIR in config.sh"
    echo
    exit 1
fi

set -Eeuo pipefail
IFS=$'\n\t'
export LC_NUMERIC=C

###############################################################################
# CONFIGURATION
###############################################################################

# Public/GitHub layout: one MEDIA_DIR tree, one incoming directory and one
# final output directory (LIBRARY). PROCESSING is only temporary workspace.
mkdir -p \
    "$INCOMING" \
    "$PROCESSING" \
    "$LIBRARY" \
    "$COMPLETED" \
    "$FAILED" \
    "$LOGS" \
    "$TEMP"

LOGFILE="${LOGS}/transcoder_$(date +%F_%H-%M-%S).log"

TARGET_TOTAL_BPS=$(awk \
    -v gb="$TARGET_GB" \
    -v min="$TARGET_MIN" \
    'BEGIN{printf "%.0f", (gb*1024*1024*1024*8)/(min*60)}')

OUTPUT_SPACE_MARGIN_GB=${OUTPUT_SPACE_MARGIN_GB:-1}
MIN_FREE_GB=${MIN_FREE_GB:-50}

ESTIMATED_OUTPUT_GB=$(awk \
    -v target="$TARGET_GB" \
    -v margin="$OUTPUT_SPACE_MARGIN_GB" \
    'BEGIN { printf "%.2f", target + margin }')

###############################################################################
# FUNCTIONS
###############################################################################

log()
{
    printf '[%(%F %T)T] %s\n' -1 "$*" | tee -a "$LOGFILE"
}

error()
{
    log "ERROR: $*"
    exit 1
}

require_program()
{
    command -v "$1" >/dev/null 2>&1 || error "Program '$1' not found"
}

output_has_space()
{
    local estimated_gb="${1:-$ESTIMATED_OUTPUT_GB}"
    local minimum_gb="${MIN_FREE_GB:-50}"

    local estimated_kb
    local minimum_kb
    local free_kb
    local remaining_kb

    estimated_kb=$(awk \
        -v gb="$estimated_gb" \
        'BEGIN { printf "%.0f", gb * 1024 * 1024 }')

    minimum_kb=$(awk \
        -v gb="$minimum_gb" \
        'BEGIN { printf "%.0f", gb * 1024 * 1024 }')

    free_kb=$(df -Pk -- "$PROCESSING" 2>/dev/null |
        awk 'END { print $4 }')

    [[ "$free_kb" =~ ^[0-9]+$ ]] || return 1

    remaining_kb=$((free_kb - estimated_kb))
    (( remaining_kb >= minimum_kb ))
}

###############################################################################
# CHECK DEPENDENCIES
###############################################################################

require_program ffprobe
require_program ffmpeg
require_program jq
require_program curl
require_program bc

[[ -d "$INCOMING" ]] || error "Incoming directory not found: $INCOMING"

for DIR in \
    "$INCOMING" \
    "$PROCESSING" \
    "$LIBRARY" \
    "$COMPLETED" \
    "$FAILED" \
    "$LOGS" \
    "$TEMP"
do
    [[ -w "$DIR" ]] || error "Write permission denied: $DIR"
done

###############################################################################
# SEARCH FOR MOVIES
###############################################################################

PROGRESS_FILE="${LOGS}/ffmpeg.progress"
EXTRA_FILE="${LOGS}/ffmpeg.extra"

while true
do
    mapfile -d '' MOVIES < <(
        find "$INCOMING" -type f \( \
            -iname "*.mkv" -o \
            -iname "*.mp4" -o \
            -iname "*.avi" -o \
            -iname "*.m2ts" -o \
            -iname "*.ts" \
        \) -print0 | sort -z
    )

    if (( ${#MOVIES[@]} == 0 )); then

        cat > "$EXTRA_FILE" <<EOF
STATUS=waiting
EOF

        : > "$PROGRESS_FILE"

        sleep 5
        continue
    fi

###############################################################################
# PROCESS MOVIES
###############################################################################

OUTPUT_BLOCKED=false

for FILE in "${MOVIES[@]}"
do
    [[ -f "$FILE" ]] || continue

    BASENAME=$(basename "$FILE")
    NAME="${BASENAME%.*}"

    # Query external APIs safely
    TITLE="Unknown"
    YEAR=""
    VOTE="0"
    ID="0"
    IMDB_ID=""
    MEDIA_TYPE="movie"
    SEASON_NUMBER=""
    EPISODE_NUMBER=""

    # Keep normalized fallback metadata in the current shell. tmdb_search is
    # executed inside command substitution, so variables changed there do not
    # propagate back to this process.
    normalize_filename "$FILE"
    FALLBACK_TITLE="${TITLE:-$NAME}"
    FALLBACK_YEAR="${YEAR:-}"

    if ! output_has_space "$ESTIMATED_OUTPUT_GB"; then

        log "The output directory cannot preserve ${MIN_FREE_GB} GB of free space."
        log "The file remains in incoming: $BASENAME"

        cat > "$EXTRA_FILE" <<EOF
STATUS=waiting
STATUS_TEXT=waiting
CURRENT_FILE="Waiting for output directory space"
EOF

        OUTPUT_BLOCKED=true
        break

    fi

    DESTINATION_DIR="$LIBRARY"

    if [[ "$MEDIA_TYPE" == "episode" ]]; then
        MEDIA_LABEL="Episode"
    else
        MEDIA_LABEL="Movie"
    fi

    OUTFILE="$PROCESSING/$NAME.mkv"
    FINAL_FILE="$LIBRARY/$NAME.mkv"

    if [[ -e "$FINAL_FILE" ]]; then

        log "ERROR: Destination file already exists:"
        log "$FINAL_FILE"
        log "The source file will be moved to failed."

        mv -- "$FILE" "$FAILED/"
        continue

    fi

    log "==============================================================="
    log "File: $BASENAME"
    log "Media type: $MEDIA_TYPE"
    log "Destination: $DESTINATION_DIR"
    log "==============================================================="

    if command -v tmdb_search >/dev/null 2>&1; then

        TMDB_RESPONSE=$(tmdb_search "$FILE" || echo "{}")

        if ! jq empty >/dev/null 2>&1 <<<"$TMDB_RESPONSE"; then
            log "ERROR: TMDb returned an invalid JSON response"
            log "$TMDB_RESPONSE"
            TMDB_RESPONSE='{}'
        fi

        if jq -e '.success == false or (.status_code? != null)' >/dev/null 2>&1 <<<"$TMDB_RESPONSE"; then
            log "WARNING: TMDb API error: $(jq -r '.status_message // "Unknown error"' <<<"$TMDB_RESPONSE")"
            TMDB_RESPONSE='{}'
        fi

        TITLE=$(jq -r \
            --arg fallback "$FALLBACK_TITLE" \
            '.results[0].title // $fallback' <<<"$TMDB_RESPONSE")

        YEAR=$(jq -r '.results[0].release_date // ""' <<<"$TMDB_RESPONSE" | cut -d- -f1)
        [[ -n "$YEAR" ]] || YEAR="$FALLBACK_YEAR"

        VOTE=$(jq -r '.results[0].vote_average // 0' <<<"$TMDB_RESPONSE")
        ID=$(jq -r '.results[0].id // 0' <<<"$TMDB_RESPONSE")

        if jq -e '(.results // []) | length == 0' >/dev/null 2>&1 <<<"$TMDB_RESPONSE"; then
            log "WARNING: TMDb found no match. Using filename metadata: $FALLBACK_TITLE"
        fi

        if [[ "$ID" =~ ^[1-9][0-9]*$ ]] &&
           command -v tmdb_imdb_id >/dev/null 2>&1
        then

            EXTERNAL_IDS=$(tmdb_imdb_id "$ID" || echo "{}")

            if ! jq empty >/dev/null 2>&1 <<<"$EXTERNAL_IDS"; then
                log "ERROR: TMDb external_ids returned an invalid JSON response"
                log "$EXTERNAL_IDS"
                EXTERNAL_IDS='{}'
            fi

            IMDB_ID=$(jq -r '.imdb_id // ""' <<<"$EXTERNAL_IDS")
        fi
    fi

    echo -e "\nTMDb\n------------------------------------------------"
    printf "%-20s %s\n" "Title:" "$TITLE"
    printf "%-20s %s\n" "Year:" "$YEAR"
    printf "%-20s %s\n" "Rating:" "$VOTE"
    printf "%-20s %s\n" "ID:" "$ID"

    IMDB="-"
    IMDB_RATING="-"
    METASCORE="-"
    DIRECTOR="-"

    if [[ -n "$IMDB_ID" ]] && command -v omdb_search >/dev/null 2>&1; then

        OMDB_RESPONSE=$(omdb_search "$IMDB_ID" || echo "{}")

        if ! jq empty >/dev/null 2>&1 <<<"$OMDB_RESPONSE"; then
            log "ERROR: OMDb returned an invalid JSON response"
            log "$OMDB_RESPONSE"
            OMDB_RESPONSE='{}'
        elif jq -e '.Response == "False"' >/dev/null 2>&1 <<<"$OMDB_RESPONSE"; then
            log "WARNING: OMDb: $(jq -r '.Error // "Unknown error"' <<<"$OMDB_RESPONSE")"
            OMDB_RESPONSE='{}'
        fi

        IMDB=$(jq -r '.imdbID // "-"' <<<"$OMDB_RESPONSE")
        IMDB_RATING=$(jq -r '.imdbRating // "-"' <<<"$OMDB_RESPONSE")
        METASCORE=$(jq -r '.Metascore // "-"' <<<"$OMDB_RESPONSE")
        DIRECTOR=$(jq -r '.Director // "-"' <<<"$OMDB_RESPONSE")
    fi

    echo -e "\nOMDb\n------------------------------------------------"
    printf "%-20s %s\n" "IMDb:" "$IMDB"
    printf "%-20s %s\n" "Rating:" "$IMDB_RATING"
    printf "%-20s %s\n" "Metascore:" "$METASCORE"
    printf "%-20s %s\n" "Director:" "$DIRECTOR"
    printf "%-20s %s\n" "IMDb ID:" "$IMDB_ID"

    # Read ffprobe output and verify it completed successfully
    MEDIA_INFO=$(ffprobe -v quiet -print_format json -show_format -show_streams "$FILE" || echo "")

    if [[ -z "$MEDIA_INFO" ]]; then
        log "ERROR: ffprobe could not read $BASENAME. Skipping..."
        mv "$FILE" "$FAILED/"
        continue
    fi

    # Extract the primary video stream, ignoring embedded cover images
    VIDEO_STREAM=$(jq '[.streams[] | select(.codec_type=="video" and (.disposition.attached_pic != 1))] | .[0] // empty' <<<"$MEDIA_INFO" 2>/dev/null || echo "")

    if [[ -z "$VIDEO_STREAM" ]]; then
        log "ERROR: No video stream found in $BASENAME. Skipping..."
        mv "$FILE" "$FAILED/"
        continue
    fi

    WIDTH=$(jq -r '.width // 0' <<<"$VIDEO_STREAM")
    HEIGHT=$(jq -r '.height // 0' <<<"$VIDEO_STREAM")
    [[ "$WIDTH" =~ ^[0-9]+$ ]] || WIDTH=0
    [[ "$HEIGHT" =~ ^[0-9]+$ ]] || HEIGHT=0

    CODEC=$(jq -r '.codec_name // "unknown"' <<<"$VIDEO_STREAM")
    PIXFMT=$(jq -r '.pix_fmt // "yuv420p"' <<<"$VIDEO_STREAM")
    FPS=$(jq -r '.avg_frame_rate // "0/0"' <<<"$VIDEO_STREAM")

    FPS_REAL=$(awk -F/ '{if($2==0) print 0; else printf "%.3f",$1/$2}' <<<"$FPS")

    COLOR_TRANSFER=$(jq -r '.color_transfer // ""' <<<"$VIDEO_STREAM")
    COLOR_PRIMARIES=$(jq -r '.color_primaries // ""' <<<"$VIDEO_STREAM")

    HDR="NO"
    if [[ "$COLOR_TRANSFER" == "smpte2084" || "$COLOR_TRANSFER" == "arib-std-b67" || "$COLOR_PRIMARIES" == "bt2020" ]]; then
        HDR="YES"
    fi

    DV="NO"
    if jq -e '.side_data_list[]? | tostring | test("DOVI";"i")' <<<"$VIDEO_STREAM" >/dev/null 2>&1; then
        DV="YES"
    fi

    DURATION=$(jq -r '.format.duration // 0' <<<"$MEDIA_INFO")
    [[ "$DURATION" =~ ^[0-9.]+$ ]] || DURATION=0

    DURATION_INT=$(awk -v d="$DURATION" 'BEGIN{printf "%.0f", d}')

    SIZE=$(jq -r '.format.size // 0' <<<"$MEDIA_INFO")
    [[ "$SIZE" =~ ^[0-9]+$ ]] || SIZE=0

    BITRATE=$(jq -r '.format.bit_rate // 0' <<<"$MEDIA_INFO")
    [[ "$BITRATE" =~ ^[0-9]+$ ]] || BITRATE=0

    if [[ "$BITRATE" == "0" && "$DURATION_INT" -gt 0 ]]; then
        BITRATE=$(awk -v s="$SIZE" -v d="$DURATION_INT" 'BEGIN{printf "%.0f",(s*8)/d}')
    fi

    DURATION_HMS=$(printf "%02d:%02d:%02d" \
        $((DURATION_INT/3600)) \
        $(((DURATION_INT%3600)/60)) \
        $((DURATION_INT%60)))

    if (( WIDTH >= 3800 )); then
        RESOLUTION="4K"
    elif (( WIDTH >= 2500 )); then
        RESOLUTION="1440p"
    elif (( WIDTH >= 1900 )); then
        RESOLUTION="1080p"
    elif (( WIDTH >= 1200 )); then
        RESOLUTION="720p"
    else
        RESOLUTION="SD"
    fi

    echo -e "\nVideo\n------------------------------------------------"
    printf "%-20s %s\n" "Codec:" "$CODEC"
    printf "%-20s %s\n" "Resolution:" "${WIDTH}x${HEIGHT} (${RESOLUTION})"
    printf "%-20s %s\n" "Pixel Format:" "$PIXFMT"
    printf "%-20s %s\n" "FPS:" "$FPS_REAL"
    printf "%-20s %s\n" "HDR:" "$HDR"
    printf "%-20s %s\n" "Dolby Vision:" "$DV"
    printf "%-20s %s\n" "Duration:" "$DURATION_HMS"
    printf "%-20s %.2f GB\n" "Size:" "$(awk -v s="$SIZE" 'BEGIN{print s/1024/1024/1024}')"
    printf "%-20s %.2f Mbps\n" "Bitrate:" "$(awk -v b="$BITRATE" 'BEGIN{print b/1000000}')"

    echo -e "\nAudio\n------------------------------------------------"

    jq -r '.streams[] | select(.codec_type=="audio") | "\(.index)|\(.tags.language // "und")|\(.codec_name)|\(.channels)"' <<<"$MEDIA_INFO" |
    while IFS="|" read -r IDX LANG ACODEC CH; do
        printf "Track %-3s %-8s %-12s %s channels\n" "$IDX" "$LANG" "$ACODEC" "$CH"
    done

    echo -e "\nSubtitles\n------------------------------------------------"

    jq -r '.streams[] | select(.codec_type=="subtitle") | "\(.index)|\(.tags.language // "und")|\(.codec_name)"' <<<"$MEDIA_INFO" |
    while IFS="|" read -r IDX LANG SCODEC; do
        printf "Track %-3s %-8s %s\n" "$IDX" "$LANG" "$SCODEC"
    done

    echo

###############################################################################
# FFMPEG CONFIGURATION
###############################################################################

log "Calculating dynamic target bitrate..."

# Calculate target bitrate based on the actual video duration
if (( DURATION_INT > 0 )); then
    CALC_VIDEO_BPS=$(awk \
        -v total="$TARGET_TOTAL_BPS" \
        -v dest_t="$TARGET_MIN" \
        -v real_t="$DURATION_INT" \
        'BEGIN{printf "%.0f", (total * (dest_t * 60)) / real_t}')
else
    CALC_VIDEO_BPS=$MIN_VIDEO_BPS
fi

# Never go below the minimum bitrate allowed for 4K content
if (( CALC_VIDEO_BPS < MIN_VIDEO_BPS )); then
    CALC_VIDEO_BPS=$MIN_VIDEO_BPS
fi

log "Target video bitrate: $(awk -v b="$CALC_VIDEO_BPS" 'BEGIN{printf "%.2f", b/1000000}') Mbps"

# Configure HDR color metadata for NVENC output
FFMPEG_EXTRA_FLAGS=()

if [[ "$HDR" == "YES" || "$PIXFMT" == *"10"* ]]; then
    if [[ "$COLOR_TRANSFER" == "smpte2084" ]]; then
        FFMPEG_EXTRA_FLAGS+=(
            -color_primaries bt2020
            -color_trc smpte2084
            -colorspace bt2020nc
        )
    fi
fi

START_EPOCH=$(date +%s)

log "Starting GPU transcoding..."

###############################################################################
# PROGRESS MONITORING
###############################################################################

launch_ffmpeg()
{
    ffmpeg -y -v error \
        -hwaccel cuda \
        -hwaccel_output_format cuda \
        -i "$FILE" \
        -progress "$PROGRESS_FILE" \
        -vf "$FILTER" \
        -c:v hevc_nvenc \
        -preset p4 \
        -tune hq \
        -rc vbr \
        -b:v "$CALC_VIDEO_BPS" \
        -maxrate:v $((CALC_VIDEO_BPS * 2)) \
        -bufsize:v $((CALC_VIDEO_BPS * 4)) \
        "${FFMPEG_EXTRA_FLAGS[@]}" \
        -c:a copy \
        -c:s copy \
        "$OUTFILE" < /dev/null &

    FFMPEG_PID=$!
}

###############################################################################
# PROGRESS MONITORING
###############################################################################

TIMEOUT_LIMIT=300          # 5 minutes without progress
LAST_FRAME=0
LAST_ACTIVITY=$SECONDS

CANCEL_FLAG="${LOGS}/ffmpeg_cancelled_${NAME}.tmp"
rm -f "$CANCEL_FLAG"

# Reset progress file
PROGRESS_FILE="${LOGS}/ffmpeg.progress"
rm -f "$PROGRESS_FILE"
: > "$PROGRESS_FILE"

# Auxiliary status file used by monitor.sh
EXTRA_FILE="${LOGS}/ffmpeg.extra"
: > "$EXTRA_FILE"

GPU_FILTER="scale_cuda=w=${TARGET_W}:h=${TARGET_H}:force_original_aspect_ratio=decrease:interp_algo=lanczos"

CPU_FILTER="scale=w=${TARGET_W}:h=${TARGET_H}:force_original_aspect_ratio=decrease:flags=lanczos,pad=w=${TARGET_W}:h=${TARGET_H}:x=(ow-iw)/2:y=(oh-ih)/2"

FILTER="$GPU_FILTER"

for ATTEMPT in 1 2; do

    if (( ATTEMPT == 1 )); then
        FILTER="$GPU_FILTER"
        log "Trying GPU filters..."
    else
        FILTER="$CPU_FILTER"
        log "GPU filter failed. Retrying with CPU padding..."
        rm -f "$OUTFILE"
        echo "progress=continue" > "$PROGRESS_FILE"
    fi

    launch_ffmpeg

    # Monitor FFmpeg progress while the encoder is running
    while kill -0 "$FFMPEG_PID" 2>/dev/null; do

        sleep 2

        if [[ -f "$PROGRESS_FILE" ]]; then

            encoder_usage=$(
                nvidia-smi \
                    --query-gpu=utilization.encoder \
                    --format=csv,noheader,nounits \
                    -i 0 2>/dev/null |
                tr -d '[:space:]' || echo "0"
            )

            # Read current FPS
            fps_line=$(grep "^fps=" "$PROGRESS_FILE" | tail -1 || true)

            # Read current encoder quality
            quality_line=$(grep "^stream_0_0_q=" "$PROGRESS_FILE" | tail -1 || true)

            [[ "$fps_line" =~ fps=([0-9.]+) ]] \
                && current_fps="${BASH_REMATCH[1]}" \
                || current_fps="0"

            [[ "$quality_line" =~ stream_0_0_q=([0-9.-]+) ]] \
                && current_q="${BASH_REMATCH[1]}" \
                || current_q="0.0"

            # Update monitor status file
            cat > "$EXTRA_FILE" <<EOF
encoder_usage=${encoder_usage}
current_q=${current_q}
START_EPOCH=${START_EPOCH}
CURRENT_FILE="${BASENAME}"
TITLE="${TITLE}"
RAW_DUR=${DURATION_INT}
PID=${FFMPEG_PID}
STATUS_TEXT=encoding
EOF

            # Check whether FFmpeg is still making progress
            frame_line=$(grep "^frame=" "$PROGRESS_FILE" | tail -1 || true)

            if [[ "$frame_line" =~ frame=([0-9]+) ]]; then
                current_frame="${BASH_REMATCH[1]}"

                if (( current_frame > LAST_FRAME )); then
                    LAST_FRAME=$current_frame
                    LAST_ACTIVITY=$SECONDS
                fi
            fi

            # Abort if encoding makes no progress for 5 minutes
            if (( SECONDS - LAST_ACTIVITY >= TIMEOUT_LIMIT )); then
                echo "==============================================================="
                echo "WARNING: FFmpeg has made no progress for 5 minutes."
                echo "Stopping encoder..."
                echo "==============================================================="

                touch "$CANCEL_FLAG"
                kill -9 "$FFMPEG_PID" 2>/dev/null || true
                break
            fi
        fi
    done

    if wait "$FFMPEG_PID"; then
        FFMPEG_EXIT=0
    else
        FFMPEG_EXIT=$?
    fi

    (( FFMPEG_EXIT == 0 )) && break

done

###############################################################################
# HANDLE ENCODING RESULT
###############################################################################

if [[ -f "$CANCEL_FLAG" ]]; then

    log "TIMEOUT: FFmpeg stalled while processing $BASENAME"

    rm -f "$CANCEL_FLAG"
    rm -f "$OUTFILE" "$PROGRESS_FILE" "$EXTRA_FILE"

    mv "$FILE" "$FAILED/"
    continue

elif (( FFMPEG_EXIT != 0 )); then

    log "ERROR: Both transcoding attempts failed."

    rm -f "$OUTFILE" "$PROGRESS_FILE" "$EXTRA_FILE"

    mv "$FILE" "$FAILED/"
    continue

elif [[ ! -s "$OUTFILE" ]]; then

    log "ERROR: Output file is missing or empty."

    rm -f "$OUTFILE" "$PROGRESS_FILE" "$EXTRA_FILE"

    mv "$FILE" "$FAILED/"
    continue

else

    log "Transcoding completed successfully."

    rm -f "$PROGRESS_FILE" "$EXTRA_FILE"

    # Never overwrite an existing library file.
    if [[ -e "$FINAL_FILE" ]]; then

        log "ERROR: Destination file already exists:"
        log "$FINAL_FILE"

        rm -f -- "$OUTFILE"
        mv -- "$FILE" "$FAILED/"

    elif mv -- "$OUTFILE" "$FINAL_FILE"; then

        log "$MEDIA_LABEL moved to library: $FINAL_FILE"
        mv -- "$FILE" "$COMPLETED/"

    else

        log "ERROR: Failed to move $MEDIA_LABEL into the library."

        rm -f -- "$OUTFILE"
        mv -- "$FILE" "$FAILED/"

    fi

fi

done

if $OUTPUT_BLOCKED; then

    log "Waiting 60 seconds before checking output disks again..."

    sleep 60
    continue

fi

log "Batch completed. Waiting for new files..."

sleep 5

done
