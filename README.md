# safari-webgpu-trace
Capture Metal GPU traces of WebGPU pages in Safari Technology Preview, straight from the terminal.  Point it at any page that renders with WebGPU, press Space, and get a `.gputrace` bundle you can open in Xcode's Metal debugger for frame debugging and profiling: every draw call, pipeline, buffer, texture, shader, and GPU timing.
