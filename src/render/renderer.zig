const std = @import("std");

const zlm = @import("zlm");

const gl = @import("gl.zig");
const Page = @import("texture_atlas.zig").Page;
const ROM = @import("../rom.zig").ROM;
const TextureAtlas = @import("texture_atlas.zig").TextureAtlas;
const Vertex = @import("vertex.zig").Vertex;
const VertexList = @import("vertex.zig").VertexList;

fn createProgram(allocator: *std.mem.Allocator) !gl.Program {
    const vertex_shader = try gl.Shader.init(.vertex);
    defer vertex_shader.deinit();
    vertex_shader.source(@embedFile("glsl/vertex_shader.glsl"));
    try vertex_shader.compile(allocator);

    const fragment_shader = try gl.Shader.init(.fragment);
    defer fragment_shader.deinit();
    fragment_shader.source(@embedFile("glsl/fragment_shader.glsl"));
    try fragment_shader.compile(allocator);

    const program = try gl.Program.init();
    errdefer program.deinit();

    program.attach(vertex_shader);
    program.attach(fragment_shader);
    try program.link(allocator);

    return program;
}

pub const Renderer = struct {
    // GL shader program
    program: gl.Program,
    // triangle vertex objects
    tris: VertexList,
    // line vertex objects
    lines: VertexList,
    // camera position
    camera_pos: zlm.Vec3,
    // camera rotation
    camera_rot: zlm.Vec2,
    // palette we've selected
    palette: *[256]zlm.Vec3,
    // pointer to texture atlas
    texture_atlas: *TextureAtlas,

    pub fn init(allocator: *std.mem.Allocator) !Renderer {
        const program = try createProgram(allocator);
        errdefer program.deinit();
        const texture_atlas = try TextureAtlas.init(allocator);
        errdefer texture_atlas.deinit(allocator);
        const palette = try allocator.create([256]zlm.Vec3);
        errdefer allocator.destroy(palette);
        const tris = VertexList.init();
        errdefer tris.deinit(allocator);
        const lines = VertexList.init();
        errdefer lines.deinit(allocator);
        // for depth buffer
        gl.enable(.depth_test);
        // for backface culling
        gl.enable(.cull_face);

        return Renderer{
            .program = program,
            .tris = tris,
            .lines = lines,
            .camera_pos = zlm.Vec3.zero,
            .camera_rot = zlm.Vec2.zero,
            .palette = palette,
            .texture_atlas = texture_atlas,
        };
    }

    pub fn deinit(self: *Renderer, allocator: *std.mem.Allocator) void {
        self.tris.deinit(allocator);
        self.lines.deinit(allocator);
        self.texture_atlas.deinit(allocator);
        self.program.deinit();
        allocator.destroy(self.palette);
    }

    pub fn updateProjection(self: Renderer, ratio: f32) !void {
        self.program.use();
        const projection = zlm.Mat4.createPerspective(45 * (std.math.pi / 180.0), ratio, 0.1, 1000);
        gl.Program.uniform(try self.program.getUniformLocation("projection"), projection);
    }

    pub fn draw(self: Renderer) !void {
        gl.clear(&.{ .color, .depth });
        gl.clearColor(0.5, 0.5, 0.5, 1.0);
        self.program.use();
        // set view matrix
        gl.Program.uniform(try self.program.getUniformLocation("view"), self.getViewMatrix());
        // set palette and texture
        gl.Program.uniform(try self.program.getUniformLocation("palette"), @as([]const zlm.Vec3, self.palette));
        gl.Program.uniform(try self.program.getUniformLocation("tex"), @as(i32, 0));
        // calculate forward vector for lighting
        gl.Program.uniform(try self.program.getUniformLocation("cameraForward"), self.getCameraForward());
        self.tris.renderAll(.triangles);
        self.lines.renderAll(.lines);
    }

    fn getViewMatrix(self: Renderer) zlm.Mat4 {
        return zlm.Mat4.createTranslation(self.camera_pos.scale(-1))
            .mul(zlm.Mat4.createAngleAxis(zlm.Vec3.unitY, -self.camera_rot.y))
            .mul(zlm.Mat4.createAngleAxis(zlm.Vec3.unitX, -self.camera_rot.x));
    }

    fn getCameraForward(self: Renderer) zlm.Vec3 {
        return zlm.Vec3.unitZ.transformPosition(zlm.Mat4.createAngleAxis(zlm.Vec3.unitX, self.camera_rot.x)
            .mul(zlm.Mat4.createAngleAxis(zlm.Vec3.unitY, self.camera_rot.y)));
    }

    pub fn newWriter(self: *Renderer, allocator: *std.mem.Allocator) RendererPieceWriter {
        return .{
            .allocator = allocator,
            .points = .{},
            .renderer = self,
        };
    }
};

pub const RendererPieceWriter = struct {
    allocator: *std.mem.Allocator,
    points: std.ArrayListUnmanaged(zlm.Vec3),
    renderer: *Renderer,

    pub fn deinit(self: *RendererPieceWriter) void {
        self.points.deinit(self.allocator);
    }

    pub fn getVertices(self: *RendererPieceWriter, comptime n: comptime_int, points: [n]u8) ![n]zlm.Vec3 {
        var result: [n]zlm.Vec3 = undefined;
        for (result) |*p, i| {
            const j = points[i];
            if (j >= self.points.items.len) {
                return error.VertexOutOfRange;
            }
            p.* = self.points.items[j];
        }
        return result;
    }

    pub fn addPoint(self: *RendererPieceWriter, point: zlm.Vec3) !void {
        try self.points.append(self.allocator, point);
    }

    pub fn drawLine(self: *RendererPieceWriter, points: [2]u8, normal: zlm.Vec3, colors: [10]u8) !void {
        const vertices = try self.getVertices(2, points);
        try self.renderer.lines.data.appendSlice(self.allocator, &.{
            Vertex.init(vertices[0], normal, colors),
            Vertex.init(vertices[1], normal, colors),
        });
    }

    pub fn drawTri(self: *RendererPieceWriter, points: [3]u8, normal: zlm.Vec3, colors: [10]u8) !void {
        const vertices = try self.getVertices(3, points);
        try self.renderer.tris.data.appendSlice(self.allocator, &.{
            Vertex.init(vertices[0], normal, colors),
            Vertex.init(vertices[1], normal, colors),
            Vertex.init(vertices[2], normal, colors),
        });
    }

    pub fn drawTexturedTri(self: *RendererPieceWriter, points: [3]u8, normal: zlm.Vec3, start: u8, uv: [3]zlm.Vec2) !void {
        const vertices = try self.getVertices(3, points);
        try self.renderer.tris.data.appendSlice(self.allocator, &.{
            Vertex.initUV(vertices[0], normal, start, uv[0]),
            Vertex.initUV(vertices[1], normal, start, uv[1]),
            Vertex.initUV(vertices[2], normal, start, uv[2]),
        });
    }

    pub fn endShape(self: *RendererPieceWriter) void {
        self.points.clearAndFree(self.allocator);
    }

    pub fn getTexture(self: *RendererPieceWriter, rom: ROM, address: u24, page: Page, width: u4, height: u4) !zlm.Vec2 {
        return try self.renderer.texture_atlas.get(self.allocator, rom, address, page, width, height);
    }
};