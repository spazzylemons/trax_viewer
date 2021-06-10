const std = @import("std");

const util = @import("util.zig");

/// A game ROM, with memory mapping based on LoROM.
pub const ROM = struct {
    bytes: []const u8,

    /// Load the ROM from a file, allocating memory with a given allocator.
    pub fn init(allocator: *std.mem.Allocator, filename: []const u8) !ROM {
        const file = try std.fs.cwd().openFile(filename, .{});
        defer file.close();
        const size = (try file.stat()).size;
        // account for SMC header
        const offset = @intCast(u10, size & 0x3FF);
        if (offset != 0 and offset != 512) {
            return error.InvalidHeader;
        }
        const rom_size = size - offset;
        if (rom_size < 0x1000) {
            return error.ROMTooSmall;
        } else if (rom_size > 0x3FFFFF) {
            return error.ROMTooLarge;
        }
        const bytes = try allocator.alloc(u8, @intCast(u22, rom_size));
        errdefer allocator.free(bytes);
        // do some header validation so we have at least some belief that this is correct data
        const expected_size = std.math.log2_int(u12, @intCast(u12, @intCast(u22, rom_size) >> 10));
        // we're only checking the LoROM area
        try file.seekTo(@as(u16, offset) + 0x7FD7);
        if (expected_size != try file.reader().readByte()) {
            return error.InvalidHeader;
        }
        // lgtm, read the file
        try file.seekTo(offset);
        try file.reader().readNoEof(bytes);

        return ROM{ .bytes = bytes };
    }

    /// Release this ROM's memory, using the same allocator it was created with.
    pub fn deinit(self: ROM, allocator: *std.mem.Allocator) void {
        allocator.free(self.bytes);
    }

    /// Create a readable stream view into a ROM.
    pub fn view(self: ROM, pos: u24) ROMView {
        return ROMView{ .data = self.bytes, .pos = pos };
    }
};

/// A view of a ROM mapped to a 24-bit address space via LoROM. Access of memory not mapped to ROM is not allowed.
pub const ROMView = struct {
    data: []const u8,
    pos: u24,

    fn mapAddress(self: ROMView) !u24 {
        const offset = @truncate(u16, self.pos);
        // ROM is never mapped to the lower half of a bank, afaik
        if (offset < 0x8000) {
            return error.NotMappedToROM;
        }

        const bank = switch (@intCast(u8, self.pos >> 16)) {
            0x00...0x3F => |b| b,
            0x40...0x5F => |b| b ^ 0x40,
            0x80...0xBF => |b| b ^ 0x80,
            else => return error.NotMappedToROM,
        };

        // based on similar bsnes and snes9x code
        var size = @intCast(u24, self.data.len);
        std.debug.assert(size != 0);

        var addr = (offset & 0x7FFF) | (@as(u24, bank) << 15);
        var base: u24 = 0;
        var mask: u24 = 1 << 23;

        while (addr >= size) {
            while ((addr & mask) == 0) {
                mask >>= 1;
            }
            addr &= ~mask;
            if (size > mask) {
                size &= ~mask;
                base |= mask;
            }
        }

        return base | addr;
    }

    /// Read bytes from the ROM.
    fn read(self: *ROMView, buf: []u8) !usize {
        // TODO calculate only the start address and ensure the read will not enter unmapped areas
        for (buf) |*b| {
            b.* = self.data[try self.mapAddress()];
            self.pos +%= 1;
        }
        return buf.len;
    }

    pub usingnamespace util.AutoReader(read);
};
