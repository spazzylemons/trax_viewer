const std = @import("std");

const zlm = @import("zlm");

const gl = @import("gl.zig");

pub const VertexList = struct {
    vao: gl.VertexArray,
    vbo: gl.Buffer,
    data: std.ArrayListUnmanaged(Vertex),

    pub fn init() VertexList {
        const vao = gl.VertexArray.init();
        const vbo = gl.Buffer.init();
        const result = VertexList{
            .vao = vao,
            .vbo = vbo,
            .data = std.ArrayListUnmanaged(Vertex){},
        };
        result.makeActive();
        inline for (@typeInfo(Vertex).Struct.fields) |field, i| {
            gl.VertexArray.attribute(i, Vertex, field.name);
        }
        return result;
    }

    pub fn deinit(self: *VertexList, allocator: *std.mem.Allocator) void {
        self.data.deinit(allocator);
        self.vao.deinit();
        self.vbo.deinit();
    }

    pub fn makeActive(self: VertexList) void {
        self.vao.bind();
        self.vbo.bind(.array);
    }

    pub fn renderAll(self: VertexList, mode: gl.PrimitiveMode) void {
        self.makeActive();
        gl.VertexArray.draw(mode, 0, @intCast(c_int, self.data.items.len));
    }

    pub fn update(self: VertexList) void {
        self.makeActive();
        gl.Buffer.data(.array, self.data.items, .static_draw);
    }
};

pub const Vertex = extern struct {
    pos: zlm.Vec3,
    normal: zlm.Vec3,
    // i think this is the only way around some opengl limitations
    color_sets: [3]u32,
    uv: zlm.Vec2,
    is_textured: bool,

    pub fn init(pos: zlm.Vec3, normal: zlm.Vec3, colors: [10]u8) Vertex {
        return .{
            .pos = pos,
            .normal = normal,
            .color_sets = .{
                @as(u32, colors[0]) | (@as(u32, colors[1]) << 8) | (@as(u32, colors[2]) << 16) | (@as(u32, colors[3]) << 24),
                @as(u32, colors[4]) | (@as(u32, colors[5]) << 8) | (@as(u32, colors[6]) << 16) | (@as(u32, colors[7]) << 24),
                @as(u16, colors[8]) | (@as(u16, colors[9]) << 8),
            },
            .uv = zlm.Vec2.zero,
            .is_textured = false,
        };
    }

    pub fn initUV(pos: zlm.Vec3, color: u8, uv: zlm.Vec2) Vertex {
        return .{
            .pos = pos,
            .normal = zlm.Vec3.zero,
            .color_sets = .{ color, 0, 0 },
            .uv = uv,
            .is_textured = true,
        };
    }
};
