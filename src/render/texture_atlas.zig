const std = @import("std");

const zlm = @import("zlm");

const gl = @import("gl.zig");
const ROM = @import("../rom.zig").ROM;

pub const texture_length = 512;
pub const block_length = texture_length / 16;

const empty_block_array = [_][block_length]bool{[_]bool{false} ** block_length} ** block_length;

const TextureBlock = struct {
    address: u24,
    width: u4,
    height: u4,
    page: Page,
};

pub const Page = enum { left, right };

pub const TextureAtlas = struct {
    // opengl texture id
    texture: gl.Texture,
    // map of allocated blocks
    block_map: std.AutoHashMapUnmanaged(TextureBlock, zlm.Vec2),
    // array of which spaces are free
    used_blocks: [block_length][block_length]bool,
    // the actual texture data
    pixels: [texture_length][texture_length]u8,

    pub fn init(allocator: *std.mem.Allocator) !*TextureAtlas {
        const result = try allocator.create(TextureAtlas);
        errdefer allocator.destroy(result);

        result.texture = gl.Texture.init();
        errdefer result.texture.deinit();
        result.texture.bind(.@"2d");
        gl.Texture.minFilter(.@"2d", .nearest);
        gl.Texture.magFilter(.@"2d", .nearest);

        result.block_map = .{};
        errdefer result.block_map.deinit(allocator);

        result.used_blocks = empty_block_array;

        return result;
    }

    pub fn deinit(self: *TextureAtlas, allocator: *std.mem.Allocator) void {
        self.block_map.deinit(allocator);
        self.texture.deinit();
        allocator.destroy(self);
    }

    pub fn clear(self: *TextureAtlas, allocator: *std.mem.Allocator) void {
        self.block_map.clearAndFree(allocator);
        self.used_blocks = empty_block_array;
    }

    fn readTexture(self: *TextureAtlas, rom: ROM, address: u24, dx: u8, dy: u8, page: Page, width: u4, height: u4) !void {
        const pixel_w = @as(u8, width) * 16;
        const pixel_h = @as(u8, height) * 16;
        var view = rom.view(address);

        var y: u16 = 0;
        while (y < pixel_h) : (y += 1) {
            var x: u16 = 0;
            while (x < pixel_w) : (x += 1) {
                const b = try view.reader().readByte();
                self.pixels[y + @as(u16, dy) * 16][x + @as(u16, dx) * 16] = switch (page) {
                    .left => b & 15,
                    .right => b >> 4,
                };
            }
            view.pos += 256 - @as(u16, pixel_w);
        }
    }

    fn isBlockEmpty(self: *const TextureAtlas, x: u8, y: u8, width: u4, height: u4) bool {
        var h: u8 = 0;
        while (h < height) : (h += 1) {
            var w: u8 = 0;
            while (w < width) : (w += 1) {
                if (self.used_blocks[y + h][x + w]) {
                    return false;
                }
            }
        }
        return true;
    }

    fn markBlocks(self: *TextureAtlas, x: u8, y: u8, width: u4, height: u4) void {
        var h: u8 = 0;
        while (h < height) : (h += 1) {
            var w: u8 = 0;
            while (w < width) : (w += 1) {
                self.used_blocks[y + h][x + w] = true;
            }
        }
    }

    pub fn get(self: *TextureAtlas, allocator: *std.mem.Allocator, rom: ROM, address: u24, page: Page, width: u4, height: u4) !zlm.Vec2 {
        const key = TextureBlock{
            .address = address,
            .width = width,
            .height = height,
            .page = page,
        };
        if (self.block_map.get(key)) |uv| {
            // we've already mapped this texture, so return the existing coordinate
            return uv;
        } else {
            var y: u8 = 0;
            while (y + height - 1 < block_length) : (y += 1) {
                var x: u8 = 0;
                while (x + width - 1 < block_length) : (x += 1) {
                    if (self.isBlockEmpty(x, y, width, height)) {
                        // read the texture from ROM
                        try self.readTexture(rom, address, x, y, page, width, height);
                        // create uv coordinate for top-left
                        const value = zlm.vec2(@intToFloat(f32, x) / block_length, @intToFloat(f32, y) / block_length);
                        // put coordinate into map, removing it if following code fails
                        try self.block_map.put(allocator, key, value);
                        errdefer _ = self.block_map.remove(key);
                        // mark blocks as used
                        self.markBlocks(x, y, width, height);
                        // DO NOT PUT FALLIBLE CODE PAST HERE, or else used blocks may be lost
                        return value;
                    }
                }
            }
            return error.OutOfTextureSpace;
        }
    }

    pub fn update(self: *const TextureAtlas) void {
        gl.Texture.image2D(.@"2d", 0, gl.c.GL_R8UI, texture_length, texture_length, gl.c.GL_RED_INTEGER, gl.c.GL_UNSIGNED_BYTE, @ptrCast([*]const u8, &self.pixels));
    }
};
