# openDebugSafari

Capture Metal GPU traces of WebGPU pages in Safari Technology Preview, straight from the terminal.

Point it at any page that renders with WebGPU, press Space, and get a `.gputrace` bundle you can open in Xcode's Metal debugger for frame debugging and profiling: every draw call, pipeline, buffer, texture, shader, and GPU timing.

## Requirements

- macOS with [Safari Technology Preview](https://developer.apple.com/safari/technology-preview/) installed.
- [Xcode](https://developer.apple.com/xcode/) (the full app, not just the command line tools) to open and inspect the captured traces.
- A page that actually renders with **WebGPU**.
  WebGL pages cannot be captured by this hook, no matter how often you trigger it.

Everything else the script uses (`notifyutil`, `open`, `pgrep`) ships with macOS.

## Install

```sh
curl -O https://raw.githubusercontent.com/<you>/<repo>/main/openDebugSafari.sh
chmod +x openDebugSafari.sh
```

Or just copy `openDebugSafari.sh` into any project.
Traces are collected into `./gpuTraces/` under the directory you run it from, so run it from the project you are debugging.

## Usage

```sh
./openDebugSafari.sh <url> [frames]
```

| Argument | Meaning |
| --- | --- |
| `url` | Page to open in Safari Technology Preview. Must create a WebGPU device. |
| `frames` | Frames per capture (default 3). Use more for profiling longer sequences. |

Example:

```sh
./openDebugSafari.sh "http://localhost:5173/?webgpu"
./openDebugSafari.sh "https://playground.babylonjs.com/#DR9MT2#80" 10
```

Keys while running:

| Key | Action |
| --- | --- |
| `Space` / `Return` | Trigger a GPU trace capture |
| `o` | Open the last captured trace in Xcode's Metal debugger |
| `q` | Quit (also closes Safari Technology Preview) |

A successful capture looks like this:

```
Triggering GPU trace capture (3 frames)...
Success starting GPU frame capture at path file:///var/folders/.../B4798E06.gputrace - frame count = 3
Moved trace to ./gpuTraces/B4798E06.gputrace ('o' opens it)
```

## How it works

Metal supports programmatic GPU captures via `MTLCaptureManager`, but only in processes where capture is explicitly enabled.
The script:

1. Launches Safari Technology Preview with `__XPC_METAL_CAPTURE_ENABLED=1`.
   launchd forwards `__XPC_`-prefixed variables to the app's XPC services with the prefix stripped, so the WebKit GPU process (where all rendering happens) starts with `METAL_CAPTURE_ENABLED=1`.
2. Opens your URL in that instance.
3. On Space/Return, posts the `com.apple.WebKit.WebGPU.CaptureFrame` darwin notification with the frame count as its state.
   WebKit's WebGPU backend listens for this notification and starts an `MTLCaptureManager` capture of the live WebGPU device.
4. Watches Safari's output for the capture confirmation, waits for the `.gputrace` bundle to finish writing, and moves it into `./gpuTraces/`.

## Troubleshooting

**Nothing prints after pressing Space.**
The page has no live WebGPU device.
Most engines (Babylon.js, Three.js, PlayCanvas) default to WebGL and only use WebGPU when explicitly configured, so check the page really booted its WebGPU backend and that any opt-in flag survived the last reload.

**`error: Safari Technology Preview is already running.`**
Capture is enabled by an environment variable, so it only applies to an instance launched by this script.
Quit the running instance and start the script again.

**The captured trace is not the tab you were looking at.**
All tabs share one WebKit GPU process, and the capture can attach to another tab's WebGPU device.
Keep only one WebGPU page open while capturing.

**The trace fails to open.**
Opening `.gputrace` bundles requires the full Xcode app, and the first open after an Xcode update can be slow while it indexes.
You can also open them manually: `open gpuTraces/<name>.gputrace`.

## Caveats

- This relies on a private WebKit debugging hook (`com.apple.WebKit.WebGPU.CaptureFrame`), which may change or disappear in future Safari Technology Preview releases.
- It works with Safari Technology Preview only, not stock Safari.
