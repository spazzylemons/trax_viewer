const std = @import("std");

const zlm = @import("zlm");

const block_length = @import("../render/texture_atlas.zig").block_length;
const Page = @import("../render/texture_atlas.zig").Page;
const Piece = @import("piece.zig").Piece;
const ROM = @import("../rom.zig").ROM;
const ROMView = @import("../rom.zig").ROMView;
const Vertex = @import("../render/vertex.zig").Vertex;

/// The uv coordinates and color set of a textured face.
const TextureData = struct {
    uv: [4]zlm.Vec2,
    start: u8,
};

/// The material (color/texture) of a shape.
const Material = struct {
    param: u8,
    cmd: u8,
};

/// The data common to all shapes.
const ShapeData = struct {
    material: Material,
    normal: zlm.Vec3,
};

/// The data concerning a sign's texture.
const SignTexture = struct {
    page: Page,
    address: u24,
    reversed: bool,
};

const TextureType = struct {
    page: Page,
    width: u4,
    height: u4,
    reversed: bool,

    fn l(width: u4, height: u4) TextureType {
        return .{ .page = .left, .width = width, .height = height, .reversed = false };
    }

    fn lFlip(width: u4, height: u4) TextureType {
        return .{ .page = .left, .width = width, .height = height, .reversed = true };
    }

    fn r(width: u4, height: u4) TextureType {
        return .{ .page = .right, .width = width, .height = height, .reversed = false };
    }

    fn rFlip(width: u4, height: u4) TextureType {
        return .{ .page = .right, .width = width, .height = height, .reversed = true };
    }
};

const sine_table = blk: {
    var result: [256]i16 = undefined;
    for (result) |*p, i| {
        p.* = @floatToInt(i16, @sin((@intToFloat(f32, i) / 256) * 2.0 * std.math.pi) * 16384);
    }
    break :blk result;
};

fn convertPoint(x: i16, y: i16, z: i16) zlm.Vec3 {
    return zlm.vec3(
        @intToFloat(f32, x) / 256,
        @intToFloat(f32, y) / -256,
        @intToFloat(f32, z) / 256,
    );
}

/// A utility struct to render pieces.
pub fn PieceRenderer(comptime Writer: type) type {
    return struct {
        /// The piece to render.
        piece: Piece,
        /// The ROM to read from.
        rom: ROM,
        /// The view we're currently reading data from.
        view: ROMView,
        /// The scale of the piece's model.
        scale: u4,
        /// The pointer to the palette of this piece's model.
        palette_ptr: u16,
        /// The frame to select vertices from, if animated.
        frame: u8,
        /// The writer to render to, used by drawShapes.
        writer: Writer,

        pub fn init(piece: Piece, rom: ROM, writer: Writer, frame: u8) !@This() {
            var model_view = rom.view(piece.model_id);
            const model_ptr = try model_view.reader().readIntLittle(u24);
            model_view.pos += 4;
            const scale = try std.math.cast(u4, try model_view.reader().readByte());
            model_view.pos += 10;
            const palette_ptr = try model_view.reader().readIntLittle(u16);
            return @This(){
                .piece = piece,
                .rom = rom,
                .view = rom.view(model_ptr),
                .scale = scale,
                .palette_ptr = palette_ptr,
                .writer = writer,
                .frame = frame,
            };
        }

        pub fn go(self: *@This()) !void {
            try self.loadPoints();
            try self.drawShapes();
        }

        fn createMaterial(self: *@This()) !Material {
            const id = try self.view.reader().readByte();
            var view = self.rom.view((0x30000 | @as(u24, self.palette_ptr)) + @as(u24, id) * 2);
            return Material{
                .param = try view.reader().readByte(),
                .cmd = try view.reader().readByte(),
            };
        }

        fn getColorIds(self: @This(), mat: Material) ![10]u8 {
            // TODO figure out how many light-sourced colors there are... highest one in-game is $15 but maybe there's some unused...
            // TODO look for these pointers
            if (mat.cmd < 0x3E) {
                // shaded color
                return try self.rom.view(0x3A765 + 10 * @as(u24, mat.param)).reader().readBytesNoEof(10);
            } else if (mat.cmd == 0x3E) {
                // solid color
                const color = try self.rom.view(0x3A325 + @as(u24, mat.param)).reader().readByte();
                return [_]u8{ color, color, color, color, color, color, color, color, color, color };
            } else {
                // not a color, likely a broken model
                return error.NotAColor;
            }
        }

        fn calcTextureFrom(self: @This(), address: u24, start: u8, meta: TextureType) !TextureData {
            const top_left = try self.writer.getTexture(self.rom, address, meta.page, meta.width, meta.height);
            const w = @intToFloat(f32, meta.width) / block_length;
            const h = @intToFloat(f32, meta.height) / block_length;
            const uv = if (meta.reversed) [_]zlm.Vec2{
                top_left.add(zlm.vec2(w, 0)),
                top_left,
                top_left.add(zlm.vec2(0, h)),
                top_left.add(zlm.vec2(w, h)),
            } else [_]zlm.Vec2{
                top_left,
                top_left.add(zlm.vec2(w, 0)),
                top_left.add(zlm.vec2(w, h)),
                top_left.add(zlm.vec2(0, h)),
            };
            return TextureData{
                .uv = uv,
                .start = start,
            };
        }

        fn calcTexture(self: @This(), id: u8, meta: TextureType) !TextureData {
            // TODO are these addresses anywhere in the rom?
            const address = try self.rom.view(0x39D59 + @as(u24, id) * 3).reader().readIntLittle(u24);
            const start = try self.rom.view(0x39FB1 + @as(u24, id)).reader().readByte();
            return try self.calcTextureFrom(address, start, meta);
        }

        fn getTextureCoords(self: @This(), mat: Material) !TextureData {
            return switch (mat.cmd) {
                0x40 => try self.calcTexture(mat.param, TextureType.l(2, 2)),
                0x48 => try self.calcTexture(mat.param, TextureType.lFlip(2, 2)),
                0x4A => try self.calcTexture(mat.param, TextureType.l(4, 2)),
                0x60 => try self.calcTexture(mat.param, TextureType.r(2, 2)),
                0x68 => try self.calcTexture(mat.param, TextureType.rFlip(2, 2)),
                0x70 => try self.calcTexture(mat.param, TextureType.rFlip(8, 1)),
                // This texture is a special one designed to reverse on each render, only used by
                // the audience. It appears that the parameter is unused. TODO test that in the debugger
                // TODO when we add animations and stuff like that make it actually flip like in-game
                0x99 => try self.calcTextureFrom(0x13E020, 0x10, TextureType.l(4, 2)),
                0x9b => {
                    // TODO more looking into this hell
                    const data = try self.getSignTextureFromCodePointer();
                    return try self.calcTextureFrom(data.address, 0x10, .{
                        .page = data.page,
                        .width = 2,
                        .height = 2,
                        .reversed = data.reversed,
                    });
                },
                else => error.NotATexture,
            };
        }

        // to reduce the number of models, road signs with different decals share the same model, and their
        // texture pointer is determined based on a subroutine.
        fn getSignTextureFromCodePointer(self: @This()) !SignTexture {
            // TODO i'll un-hardcode this when i figure out the deeper workings of this code
            return switch (self.piece.code_pointer) {
                // u-turn left
                0x9C5B6 => SignTexture{ .page = .right, .address = 0x12C0A0, .reversed = false },
                // u-turn right
                0x9C5BF => SignTexture{ .page = .right, .address = 0x12C0A0, .reversed = true },
                // 90-degree turn left
                0x9C5C8 => SignTexture{ .page = .right, .address = 0x12C0E0, .reversed = false },
                // 90-degree turn right
                0x9C5D1 => SignTexture{ .page = .right, .address = 0x12C0E0, .reversed = true },
                // zig-zag right
                0x9C5DA => SignTexture{ .page = .right, .address = 0x12C0C0, .reversed = false },
                // zig-zag left
                0x9C5E3 => SignTexture{ .page = .right, .address = 0x12C0C0, .reversed = true },
                // rock slide
                0x9C5EC => SignTexture{ .page = .left, .address = 0x13A0C0, .reversed = false },
                // mule crossing
                0x9C5F5 => SignTexture{ .page = .left, .address = 0x13A0E0, .reversed = false },
                // no clue
                else => error.UnknownSignTexture,
            };
        }

        fn readPoint(self: *@This()) !zlm.Vec3 {
            return convertPoint(
                try self.view.reader().readByteSigned(),
                try self.view.reader().readByteSigned(),
                try self.view.reader().readByteSigned(),
            );
        }

        fn rotatePoint(self: @This(), point: zlm.Vec3) zlm.Vec3 {
            // find angle of rotation
            const s = @intToFloat(f32, sine_table[self.piece.dir]) / 16384;
            const c = @intToFloat(f32, sine_table[self.piece.dir +% 0x40]) / 16384;
            // rotate point
            return zlm.vec3(point.x * c - point.z * s, point.y, point.x * s + point.z * c);
        }

        fn transformPoint(self: @This(), point: zlm.Vec3) zlm.Vec3 {
            const scaled_point = point.scale(@intToFloat(f32, @as(u32, 1) << self.scale));
            const rotated_point = self.rotatePoint(scaled_point);
            return rotated_point.add(convertPoint(
                self.piece.x,
                self.piece.y,
                self.piece.z,
            ));
        }

        fn jump(self: *@This()) !void {
            const amt = try self.view.reader().readIntLittle(u16);
            self.view.pos += amt;
            self.view.pos -= 1;
        }

        fn loadPoints(self: *@This()) !void {
            const reader = self.view.reader();
            while (true) {
                switch (try reader.readByte()) {
                    // standard list
                    0x04 => {
                        const count = try reader.readByte();
                        var i: u8 = 0;
                        while (i < count) : (i += 1) {
                            try self.writer.addPoint(self.transformPoint(try self.readPoint()));
                        }
                    },
                    // mirrored list
                    0x38 => {
                        const count = try reader.readByte();
                        var i: u8 = 0;
                        while (i < count) : (i += 1) {
                            var p = try self.readPoint();
                            try self.writer.addPoint(self.transformPoint(p));
                            p.x = -p.x;
                            try self.writer.addPoint(self.transformPoint(p));
                        }
                    },
                    // keyframe table
                    0x1C => {
                        if (self.frame >= try reader.readByte()) {
                            return error.FrameOutOfBounds;
                        }
                        self.view.pos += 2 * @as(u16, self.frame);
                        try self.jump();
                    },
                    // keyframe break
                    0x20 => try self.jump(),
                    // end of vertex list
                    0x0C => break,
                    // that should be it
                    else => return error.UnrecognizedVertexCommand,
                }
            }
        }

        fn getNormal(self: *@This()) !zlm.Vec3 {
            return (try self.readPoint()).normalize();
        }

        fn getShapeData(self: *@This()) !ShapeData {
            // skip bytes we don't understand yet/don't use
            self.view.pos += 2;
            const material = try self.createMaterial();
            const normal = try self.getNormal();
            return ShapeData{
                .material = material,
                .normal = normal,
            };
        }

        fn addLine(self: *@This(), points: [2]u8, shape_data: ShapeData) !void {
            const colors = try self.getColorIds(shape_data.material);
            try self.writer.drawLine(points, shape_data.normal, colors);
        }

        fn addTri(self: *@This(), points: [3]u8, shape_data: ShapeData, texture_allowed: bool) !void {
            // some tris are textured (see: the water road in harbor city)
            if (texture_allowed) {
                if (self.getTextureCoords(shape_data.material)) |texture_data| {
                    try self.writer.drawTexturedTri(points, shape_data.normal, texture_data.start, texture_data.uv[0..3].*);
                    return;
                } else |err| {
                    if (err != error.NotATexture) return err;
                }
            }
            const colors = try self.getColorIds(shape_data.material);
            try self.writer.drawTri(points, shape_data.normal, colors);
        }

        fn addQuad(self: *@This(), points: [4]u8, shape_data: ShapeData) !void {
            var vertices: [6]usize = undefined;
            if (self.getTextureCoords(shape_data.material)) |texture_data| {
                try self.writer.drawTexturedTri(points[0..3].*, shape_data.normal, texture_data.start, texture_data.uv[0..3].*);
                try self.writer.drawTexturedTri(.{points[0], points[2], points[3]}, shape_data.normal, texture_data.start, .{texture_data.uv[0], texture_data.uv[2], texture_data.uv[3]});
            } else |err| switch (err) {
                error.NotATexture => {
                    const colors = try self.getColorIds(shape_data.material);
                    try self.writer.drawTri(points[0..3].*, shape_data.normal, colors);
                    try self.writer.drawTri(.{points[0], points[2], points[3]}, shape_data.normal, colors);
                },
                else => return err,
            }
        }

        fn drawShapes(self: *@This()) !void {
            const reader = self.view.reader();

            while (true) {
                switch (try reader.readByte()) {
                    // end of list
                    0 => break,
                    // line
                    2 => {
                        const shape_data = try self.getShapeData();
                        const points = try reader.readBytesNoEof(2);
                        try self.addLine(points, shape_data);
                    },
                    // tri
                    3 => {
                        const shape_data = try self.getShapeData();
                        const points = try reader.readBytesNoEof(3);
                        try self.addTri(points, shape_data, true);
                    },
                    // quad
                    4 => {
                        const shape_data = try self.getShapeData();
                        const points = try reader.readBytesNoEof(4);
                        try self.addQuad(points, shape_data);
                    },
                    // n-gon
                    5...8 => |count| {
                        const shape_data = try self.getShapeData();
                        // render an n-gon using a triangle fan
                        // first point in each triangle is the first point of the polygon
                        // second and third are shifted along among the rest
                        var points: [3]u8 = undefined;
                        points[0] = try reader.readByte();
                        points[2] = try reader.readByte();
                        var i: u8 = 0;
                        while (i < count - 2) : (i += 1) {
                            points[1] = points[2];
                            points[2] = try reader.readByte();
                            // TODO experiment with textured n-gons, see how the game reacts?
                            try self.addTri(points, shape_data, false);
                        }
                    },
                    // misc. data we either don't use or don't understand
                    // TODO maybe structure this code more
                    0x14, 0x3C, 0x40, 0x58, 0x64, 0xFE, 0xFF => {},
                    0x44, 0x60 => self.view.pos += 2,
                    0x28 => self.view.pos += 4,
                    0x5C => self.view.pos += 5,
                    0x30 => {
                        const amt = 3 * @as(u16, try reader.readByte());
                        self.view.pos += amt;
                    },
                    // that should be it
                    else => return error.UnrecognizedShapeCommand,
                }
            }
        }
    };
}
