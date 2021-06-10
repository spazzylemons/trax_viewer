const std = @import("std");

const PieceRenderer = @import("piece_renderer.zig").PieceRenderer;
const Renderer = @import("../render/renderer.zig").Renderer;
const ROM = @import("../rom.zig").ROM;

pub const Piece = struct {
    x: i16,
    y: i16,
    z: i16,
    dir: u8,
    model_id: u16,
    code_pointer: u24,

    pub fn render(self: Piece, allocator: *std.mem.Allocator, rom: ROM, renderer: *Renderer, frame: u8) !void {
        if (self.model_id == 0xA040) {
            // A040 is a hardcoded "nothing" object.
            return;
        }

        var r = try PieceRenderer.init(allocator, self, rom, renderer, frame);
        defer r.deinit();
        try r.go();
    }
};
