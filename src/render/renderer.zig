const std = @import("std");

const zlm = @import("zlm");

const gl = @import("gl.zig");
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
};
