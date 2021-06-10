const std = @import("std");

const zlm = @import("zlm");

const Renderer = @import("renderer.zig").Renderer;
const ROM = @import("../rom.zig").ROM;
const Track = @import("../track/track.zig").Track;
const Window = @import("window.zig").Window;

const CameraMoveMode = enum {
    None,
    Pan,
    Rotate,
};

const PAN_FACTOR = 0.4;
const ZOOM_FACTOR = 5;
const ROTATE_FACTOR = 0.01;

pub const Viewer = struct {
    // window for doing window things
    window: *Window,
    // renderer to render stuff on
    renderer: *Renderer,
    // track to display
    track: Track,
    // previous mouse position, undefined if not needed
    prev_mouse_pos: zlm.Vec2,
    // mode of moving camera
    move_mode: CameraMoveMode,
    // frame to resume after each frame, to allow concurrent execution
    resumer: ?anyframe,
    // set to false when the viewer should be closed
    running: bool,

    pub fn init(allocator: *std.mem.Allocator) !Viewer {
        const window = try Window.init(allocator, 1024, 768);
        errdefer window.deinit(allocator);
        const renderer = try allocator.create(Renderer);
        errdefer allocator.destroy(renderer);
        renderer.* = try Renderer.init(allocator);
        errdefer renderer.deinit(allocator);
        window.renderer = renderer;
        try window.updateViewport();

        return Viewer{
            .window = window,
            .renderer = renderer,
            .track = Track.init(),
            .prev_mouse_pos = undefined,
            .move_mode = .None,
            .resumer = null,
            .running = true,
        };
    }

    pub fn deinit(self: *Viewer, allocator: *std.mem.Allocator) void {
        self.renderer.deinit(allocator);
        allocator.destroy(self.renderer);
        self.window.deinit(allocator);
        self.track.deinit(allocator);
    }

    fn camMatrix(self: Viewer) zlm.Mat4 {
        return zlm.Mat4.createAngleAxis(zlm.Vec3.unitX, self.renderer.camera_rot.x)
            .mul(zlm.Mat4.createAngleAxis(zlm.Vec3.unitY, self.renderer.camera_rot.y))
            .mul(zlm.Mat4.createTranslation(self.renderer.camera_pos));
    }

    pub fn update(self: *Viewer) void {
        Window.pollEvents();
        const mouse_pos = self.window.getCursor();
        defer self.prev_mouse_pos = mouse_pos;

        // mouse delta is flipped, feels better imo
        const dx = self.prev_mouse_pos.x - mouse_pos.x;
        const dy = self.prev_mouse_pos.y - mouse_pos.y;

        const is_mouse_down = self.window.isMouseDown(.middle);

        if (self.move_mode != .None and !is_mouse_down) {
            self.move_mode = .None;
            return;
        }

        switch (self.move_mode) {
            .None => {
                if (is_mouse_down) {
                    if (self.window.isKeyDown(.left_shift)) {
                        self.move_mode = .Pan;
                    } else {
                        self.move_mode = .Rotate;
                    }
                } else {
                    const scroll = @atomicRmw(f32, &self.window.scroll, .Xchg, 0, .SeqCst);
                    if (scroll != 0) {
                        self.renderer.camera_pos = zlm.Vec3.unitZ.scale(scroll * ZOOM_FACTOR)
                            .transformPosition(self.camMatrix());
                    }
                }
            },
            .Pan => {
                self.renderer.camera_pos = zlm.Vec3.unitX.scale(dx * PAN_FACTOR)
                    .sub(zlm.Vec3.unitY.scale(dy * PAN_FACTOR))
                    .transformPosition(self.camMatrix());
            },
            .Rotate => {
                self.renderer.camera_rot.x = @rem(self.renderer.camera_rot.x + dy * ROTATE_FACTOR, 2 * std.math.pi);
                self.renderer.camera_rot.y = @rem(self.renderer.camera_rot.y + dx * ROTATE_FACTOR, 2 * std.math.pi);
            },
        }
    }

    pub fn run(self: *Viewer, allocator: *std.mem.Allocator, rom: ROM) !void {
        defer while (self.resumer) |r| {
            // this loop makes sure the resumer returns before we do, so resources are cleaned up gracefully
            self.resumer = null;
            resume r;
        };
        // we expect that this is running on the main thread
        while (self.running) {
            self.update();

            // TODO animation
            self.track.renderIfNeeded(allocator, rom, self.renderer, 0);

            try self.renderer.draw();
            self.window.swapBuffers();

            if (self.window.shouldClose()) {
                self.running = false;
                break;
            }

            if (self.resumer) |r| {
                self.resumer = null;
                resume r;
            }
        }
    }
};
