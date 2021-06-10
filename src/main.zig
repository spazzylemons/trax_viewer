const std = @import("std");

const REPL = @import("repl.zig").REPL;
const ROM = @import("rom.zig").ROM;
const Viewer = @import("render/viewer.zig").Viewer;

// TODO proper arguments
pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = &gpa.allocator;

    const stderr = std.io.getStdErr().writer();

    var iter = std.process.ArgIterator.init();
    _ = iter.skip();

    const filename = try (iter.next(allocator) orelse return 1);
    defer allocator.free(filename);

    const rom = try ROM.init(allocator, filename);
    defer rom.deinit(allocator);

    var viewer = try Viewer.init(allocator);
    defer viewer.deinit(allocator);

    var repl = try REPL.init(allocator, &viewer, rom);
    defer repl.deinit();

    // launch console event loop
    _ = async repl.run();
    // run viewer on main thread
    try viewer.run(allocator, rom);

    return 0;
}
