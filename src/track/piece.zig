const std = @import("std");

const PieceRenderer = @import("piece_renderer.zig").PieceRenderer;
const PieceWriter = @import("piece_writer.zig").PieceWriter;
const ROM = @import("../rom.zig").ROM;

pub const Piece = struct {
    x: i16,
    y: i16,
    z: i16,
    dir: u8,
    model_id: u16,
    code_pointer: u24,

    pub fn render(self: Piece, rom: ROM, writer: anytype, frame: u8) !void {
        if (self.model_id == 0xA040) {
            // A040 is a hardcoded "nothing" object.
            return;
        }
        defer writer.endShape();
        var r = try PieceRenderer(@TypeOf(writer)).init(self, rom, writer, frame);
        try r.go();
    }
};
