# Trax Viewer

A track and model viewer for Wild Trax/Stunt Race FX.

## Building

Trax Viewer has only been run on Linux. I plan to add multi-platform support.

Compiling requires [zigmod](https://github.com/nektro/zigmod) and a
[Zig](https://ziglang.org/) compiler. As Zig is a growing language, Trax
Viewer is designed to compile on the latest development versions of Zig. You
will also need OpenGL 3.3, GLFW 3, and freeglut.

```sh
zigmod fetch # fetches dependencies and creates a deps.zig
zig build    # builds Trax Viewer at zig-out/bin/trax_viewer
# alternatively, run `zig build -Drelease-fast` for an optimized build with
# less safety checks
```

## Usage

Currently, Trax Viewer requires use of both the command line and a graphical
interface. Run Trax Viewer with the path to the ROM, and a window should appear
as well as a CLI. The available commands can be seen with `help`.

### Camera Controls

- Middle mouse button: Rotate camera
- Middle mouse button + left shift: Move camera up-down and left-right
- Scroll wheel: Move camera forward and backward

## License

Trax Viewer is available under the MIT License.
