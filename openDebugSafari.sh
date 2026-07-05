#!/bin/bash
#
# GPU trace capture for WebGPU pages in Safari Technology Preview.
# Drop this script into any project and point it at a page that renders
# with WebGPU.
#
# Usage:
#   ./openDebugSafari.sh <url> [frames]
#
#   url      Page to open. It must create a WebGPU device - WebGL pages
#            cannot be captured by this hook, no matter how often you
#            trigger it.
#   frames   Frames per capture (default 3). Use more for profiling
#            longer sequences.
#
# Keys while running:
#   Space/Return   trigger a GPU trace capture
#   o              open the last captured trace (Xcode's Metal debugger)
#   q              quit (also closes Safari Technology Preview)
#
# Captured traces are moved into ./gpuTraces/ under the current working
# directory, so run it from the project you are debugging.
#
# How it works: Safari Technology Preview is launched with
# __XPC_METAL_CAPTURE_ENABLED=1 (launchd forwards it to the WebKit GPU
# process as METAL_CAPTURE_ENABLED=1), and WebKit's WebGPU backend starts
# an MTLCaptureManager capture when the com.apple.WebKit.WebGPU.CaptureFrame
# darwin notification fires, with the notification state as frame count.

set -u

APP="/Applications/Safari Technology Preview.app"
APP_NAME="Safari Technology Preview"
NOTIFICATION="com.apple.WebKit.WebGPU.CaptureFrame"
TRACE_DIR="./gpuTraces"

URL="${1:-}"
FRAMES="${2:-3}"

if [[ -z "$URL" ]]; then
    sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
fi

if [[ ! -d "$APP" ]]; then
    echo "error: $APP not found - install Safari Technology Preview:" >&2
    echo "       https://developer.apple.com/safari/technology-preview/" >&2
    exit 1
fi

# Metal capture is enabled by an environment variable, so it only applies to
# a Safari instance launched by this script.
if pgrep -xq "$APP_NAME"; then
    echo "error: $APP_NAME is already running." >&2
    echo "       Quit it first - Metal capture must be enabled at launch." >&2
    exit 1
fi

# File to store the path of the last moved GPU trace
LAST_TRACE_FILE=$(mktemp /tmp/last_trace_path.XXXXXX)

# Function to process a line of Safari's output
process_line() {
    local line="$1"
    echo "$line"  # Print the line to the terminal

    if [[ $line == *"Success starting GPU frame capture at path"* ]]; then
        # Extract the file path and strip the 'file://' prefix
        local filepath
        filepath=$(echo "$line" | sed -E 's/.*path (file:\/\/[^ ]+).*/\1/')
        filepath=${filepath#file://}

        # The .gputrace bundle is written asynchronously while the requested
        # frames render; wait until its size stops changing.
        local prev=-1 size=0 tries=0
        while (( tries < 30 )); do
            size=$(du -sk "$filepath" 2>/dev/null | cut -f1)
            if [[ -n "$size" && "$size" == "$prev" ]]; then
                break
            fi
            prev=$size
            tries=$((tries + 1))
            sleep 1
        done

        if [[ ! -e "$filepath" ]]; then
            echo "Capture reported at $filepath but no trace appeared."
            return
        fi

        local filename
        filename=$(basename "$filepath")
        mkdir -p "$TRACE_DIR"
        if mv "$filepath" "$TRACE_DIR/$filename"; then
            echo "Moved trace to $TRACE_DIR/$filename ('o' opens it)"
            echo "$TRACE_DIR/$filename" > "$LAST_TRACE_FILE"
        else
            echo "Failed to move $filename to $TRACE_DIR/$filename"
        fi
    fi
}

trigger_gpu_trace() {
    echo "Triggering GPU trace capture ($FRAMES frames)..."
    notifyutil -s "$NOTIFICATION" "$FRAMES" && notifyutil -p "$NOTIFICATION"
    echo "If no 'Success starting GPU frame capture' line appears, the page"
    echo "has no live WebGPU device (WebGL pages cannot be captured)."
}

open_last_trace() {
    if [[ -s "$LAST_TRACE_FILE" ]]; then
        local last_trace
        last_trace=$(cat "$LAST_TRACE_FILE")
        echo "Opening last GPU trace: $last_trace"
        open "$last_trace"
    else
        echo "No GPU trace has been captured yet."
    fi
}

# Flag to track if we've started quitting
quitting=false

clean_exit() {
    if ! $quitting; then
        quitting=true
        echo -e "\nQuitting..."
        pkill -TERM -x "$APP_NAME"
        kill "$tail_pid" 2>/dev/null
        rm -f "$TEMP_FILE" "$LAST_TRACE_FILE"
    fi
    exit 0
}

# Temporary file for Safari's output; the GPU process inherits stderr, so
# WebKit's capture confirmations land here.
TEMP_FILE=$(mktemp /tmp/safari_output.XXXXXX)

trap "clean_exit" EXIT INT TERM

__XPC_METAL_CAPTURE_ENABLED=1 "$APP/Contents/MacOS/$APP_NAME" > "$TEMP_FILE" 2>&1 &

# Wait for Safari to start up, then open the target page in it.
sleep 2
open -a "$APP_NAME" "$URL"

# Read Safari's output in real-time
tail -f "$TEMP_FILE" | while IFS= read -r line || [[ -n "$line" ]]; do
    process_line "$line"
done &
tail_pid=$!

echo "$APP_NAME started with Metal capture enabled."
echo "Opened $URL"
echo "Capturing $FRAMES frame(s) per trace into $TRACE_DIR/"
echo "Press 'Space' or 'Return' to trigger a GPU trace capture."
echo "Press 'o' to open the last captured GPU trace."
echo "Press 'q' to quit."

# Main loop for handling user input
while true; do
    IFS= read -r -n1 -s -d '' input
    if [[ $? -eq 0 ]]; then
        case "$input" in
            $' '|$'\n')
                trigger_gpu_trace
                ;;
            o)
                open_last_trace
                ;;
            q)
                clean_exit
                ;;
            *)
                ;;
        esac
    fi
done
