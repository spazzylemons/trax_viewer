const std = @import("std");

const Piece = @import("piece.zig").Piece;
const Renderer = @import("../render/renderer.zig").Renderer;
const ROM = @import("../rom.zig").ROM;

pub const Track = struct {
    pieces: std.ArrayListUnmanaged(Piece),
    recompile_needed: bool,

    pub fn init() Track {
        return .{
            .pieces = std.ArrayListUnmanaged(Piece){},
            .recompile_needed = false,
        };
    }

    pub fn deinit(self: *Track, allocator: *std.mem.Allocator) void {
        self.pieces.deinit(allocator);
    }

    pub fn clear(self: *Track, allocator: *std.mem.Allocator) void {
        self.pieces.clearAndFree(allocator);
        self.recompile_needed = true;
    }

    pub fn append(self: *Track, allocator: *std.mem.Allocator, piece: Piece) !void {
        try self.pieces.append(allocator, piece);
        self.recompile_needed = true;
    }

    pub fn renderIfNeeded(self: *Track, allocator: *std.mem.Allocator, rom: ROM, renderer: *Renderer, frame: u8) void {
        if (self.recompile_needed) {
            renderer.texture_atlas.clear(allocator);
            renderer.tris.data.clearAndFree(allocator);
            renderer.lines.data.clearAndFree(allocator);
            for (self.pieces.items) |piece| {
                // always using animation frame 0 for now
                piece.render(allocator, rom, renderer, 0) catch |err| {
                    std.io.getStdErr().writer().print("object was skipped due to the error: {}\n", .{err}) catch {};
                };
            }
            renderer.tris.update();
            renderer.lines.update();
            renderer.texture_atlas.update();
            self.recompile_needed = false;
        }
    }
};
