const std = @import("std");

const zlm = @import("zlm");

const gl = @import("gl.zig");
const Renderer = @import("renderer.zig").Renderer;
const util = @import("../util.zig");
const glut = @cImport(@cInclude("GL/freeglut.h"));
const glfw = @cImport(@cInclude("GLFW/glfw3.h"));

pub const MouseButton = enum(u3) {
    left = 1,
    middle = 2,
    right = 3,
};

var glfw_users: usize = 0;
var gl_needs_initialization: bool = true;

fn incGLFWRef() !void {
    if (glfw_users == 0) {
        if (glfw.glfwInit() == 0) {
            return error.GLFWError;
        }
    }
    glfw_users += 1;
}

fn setupOpenGL() void {
    if (gl_needs_initialization) {
        // load gl via freeglut
        var fake_argc: c_int = 0;
        var fake_argv: [*c]u8 = undefined;
        glut.glutInit(&fake_argc, &fake_argv);
        gl_needs_initialization = false;
    }
}

fn decGLFWRef() void {
    glfw_users -= 1;
    if (glfw_users == 0) {
        glfw.glfwTerminate();
    }
}

fn logGLFWErrors() void {
    var description: ?[*:0]u8 = null;
    while (true) {
        const err = glfw.glfwGetError(&description);
        if (err == glfw.GLFW_NO_ERROR) {
            break;
        }
        if (description) |desc| {
            std.debug.print("GLFW error code {}: '{s}'\n", .{ err, desc });
        } else {
            std.debug.print("GLFW error code {}\n", .{err});
        }
    }
}

fn getWindow(glfw_win: ?*glfw.GLFWwindow) *Window {
    return @ptrCast(*Window, @alignCast(@alignOf(Window), glfw.glfwGetWindowUserPointer(glfw_win)));
}

fn onScroll(glfw_win: ?*glfw.GLFWwindow, x: f64, y: f64) callconv(.C) void {
    const self = getWindow(glfw_win);
    self.scroll = @floatCast(f32, y);
}

fn onResize(glfw_win: ?*glfw.GLFWwindow, w: c_int, h: c_int) callconv(.C) void {
    const self = getWindow(glfw_win);
    self.width = @intCast(u31, w);
    self.height = @intCast(u31, h);
    util.errorBoundary(self.updateViewport());
}

// TODO make the code *potentially* handle multiple windows, for correctness
pub const Window = struct {
    // handle to GLFW window
    glfw_win: *glfw.GLFWwindow,
    // attached renderer, nullable as Renderer depends on us being ready first, but we want Renderer so we can update the viewport...
    // TODO rework this system due to the entanglement of different structures here?
    renderer: ?*const Renderer,
    // last seen scroll amount
    scroll: f32,
    // width of window
    width: u31,
    // height of window
    height: u31,

    pub fn init(allocator: *std.mem.Allocator, width: u31, height: u31) !*Window {
        // ensure glfw (and opengl) are initialized
        try incGLFWRef();
        errdefer decGLFWRef();
        // request version 3.3 core for OpenGL
        glfw.glfwWindowHint(glfw.GLFW_CONTEXT_VERSION_MAJOR, 3);
        glfw.glfwWindowHint(glfw.GLFW_CONTEXT_VERSION_MINOR, 3);
        glfw.glfwWindowHint(glfw.GLFW_OPENGL_PROFILE, glfw.GLFW_OPENGL_CORE_PROFILE);
        // create a GLFW window
        const glfw_win = glfw.glfwCreateWindow(width, height, "hello world", null, null) orelse return error.GLFWError;
        errdefer glfw.glfwDestroyWindow(glfw_win);
        // set the context
        glfw.glfwMakeContextCurrent(glfw_win);
        // we must run this *after* the context is created
        setupOpenGL();
        // set a scroll wheel callback because we can't query scroll wheel state whenever we want
        _ = glfw.glfwSetScrollCallback(glfw_win, onScroll);
        // set a window resize callback to keep window size up-to-date
        _ = glfw.glfwSetFramebufferSizeCallback(glfw_win, onResize);
        // allocate ourselves on the heap, to set ourselves as the user pointer
        const self = try allocator.create(Window);
        errdefer allocator.destroy(self);
        self.* = .{
            .glfw_win = glfw_win,
            .renderer = null,
            .scroll = 0,
            .width = width,
            .height = height,
        };
        // put us in the user pointer
        glfw.glfwSetWindowUserPointer(glfw_win, self);
        return self;
    }

    pub fn deinit(self: *Window, allocator: *std.mem.Allocator) void {
        glfw.glfwDestroyWindow(self.glfw_win);
        decGLFWRef();
        allocator.destroy(self);
    }

    pub fn updateViewport(self: Window) !void {
        gl.viewport(0, 0, self.width, self.height);
        if (self.renderer) |r| {
            try r.updateProjection(@intToFloat(f32, self.width) / @intToFloat(f32, self.height));
        }
    }

    pub fn swapBuffers(self: Window) void {
        glfw.glfwSwapBuffers(self.glfw_win);
    }

    pub fn shouldClose(self: Window) bool {
        return glfw.glfwWindowShouldClose(self.glfw_win) != 0;
    }

    pub fn pollEvents() void {
        glfw.glfwPollEvents();
    }

    pub fn getCursor(self: Window) zlm.Vec2 {
        var x: f64 = undefined;
        var y: f64 = undefined;
        glfw.glfwGetCursorPos(self.glfw_win, &x, &y);
        return zlm.vec2(@floatCast(f32, x), @floatCast(f32, y));
    }

    pub fn isMouseDown(self: Window, button: MouseButton) bool {
        return glfw.glfwGetMouseButton(self.glfw_win, @enumToInt(button)) == glfw.GLFW_PRESS;
    }

    pub fn isKeyDown(self: Window, key: anytype) bool {
        // just so i don't have to make an enum for *all* of them, we'll use a metaprogramming trick (hack?)
        // i'd autogenerate an enum but there's todos in the stage 1 compiler that prevent that
        const int_key = switch (@typeInfo(@TypeOf(key))) {
            .EnumLiteral => blk: {
                comptime var name = [_]u8{0} ** @tagName(key).len;
                inline for (@tagName(key)) |c, i| {
                    name[i] = comptime std.ascii.toUpper(c);
                }
                break :blk @field(glfw, "GLFW_KEY_" ++ name);
            },
            else => key,
        };
        return glfw.glfwGetKey(self.glfw_win, int_key) == glfw.GLFW_PRESS;
    }
};
