const std = @import("std");

const zlm = @import("zlm");

const ObjExporter = @import("obj_exporter.zig").ObjExporter;
const ROM = @import("rom.zig").ROM;
const Track = @import("track/track.zig").Track;
const util = @import("util.zig");
const Viewer = @import("render/viewer.zig").Viewer;

inline fn strEq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

// TODO is this written anywhere in the ROM?
const track_count = 28;

fn decodeChar(in: u8) u8 {
    return switch (in) {
        0...9 => in + '0',
        10...35 => in + ('a' - 10),
        36 => '-',
        37 => '.',
        38 => '\'',
        39 => '"',
        255 => ' ',
        else => '?',
    };
}

fn processPalette(code: u16) zlm.Vec3 {
    const r = code & 31;
    const g = (code >> 5) & 31;
    const b = (code >> 10) & 31;
    return zlm.vec3(
        @intToFloat(f32, r) / 31,
        @intToFloat(f32, g) / 31,
        @intToFloat(f32, b) / 31,
    );
}

const Names = struct {
    // the single buffer used to store all the names
    buffer: []u8,
    // slices for each name
    names: [track_count][]u8,

    fn deinit(self: Names, allocator: *std.mem.Allocator) void {
        allocator.free(self.buffer);
    }
};

fn loadNames(allocator: *std.mem.Allocator, rom: ROM) !Names {
    // buffer to store names in
    const name_buffer = try allocator.alloc(u8, 255 * track_count);
    errdefer allocator.free(name_buffer);

    // allocator to help allocate names in the buffer
    var name_allocator = std.heap.FixedBufferAllocator.init(name_buffer);

    // read names from memory
    var name_pointers = rom.view(0x78000);
    var names: [track_count][]u8 = undefined;
    var hashes: [track_count][]u8 = undefined;
    for (names) |*name| {
        const name_location = 0x70000 + @as(u24, try name_pointers.reader().readIntLittle(u16));
        var name_view = rom.view(name_location);
        // we don't need to deallocate this on failure because the backing buffer is deallocated on failure
        var name_slice = try name_allocator.allocator.alloc(u8, try name_view.reader().readByte());
        for (name_slice) |*char| {
            char.* = decodeChar(try name_view.reader().readByte());
        }
        // put name in array
        name.* = name_slice;
    }

    // return names struct
    return Names{
        .buffer = name_buffer,
        .names = names,
    };
}

pub const REPL = struct {
    allocator: *std.mem.Allocator,
    track_names: Names,
    rom: ROM,
    viewer: *Viewer,

    pub fn init(allocator: *std.mem.Allocator, viewer: *Viewer, rom: ROM) !REPL {
        const track_names = try loadNames(allocator, rom);
        errdefer track_names.deinit(allocator);

        return REPL{
            .allocator = allocator,
            .track_names = track_names,
            .rom = rom,
            .viewer = viewer,
        };
    }

    pub fn deinit(self: *REPL) void {
        self.track_names.deinit(self.allocator);
    }

    fn yield(self: *REPL) void {
        suspend self.viewer.resumer = @frame();
    }

    fn readLine(self: *REPL, stdin_file: std.fs.File, line_buf: []u8) !?[]u8 {
        // TODO multi-platform support... no doubt a lot of people are going to want to use this on windows
        // i is our index into the line buffer
        var i: usize = 0;
        // this pollfd structure tells the kernel we're looking for data from stdin
        var pollfd = std.os.pollfd{
            .fd = stdin_file.handle,
            .events = std.os.POLLIN,
            .revents = undefined,
        };
        while (true) {
            // ask the kernel if we can get data right now
            const n = try std.os.poll(@ptrCast(*[1]std.os.pollfd, &pollfd), 0);
            if (n == 1 and pollfd.revents & std.os.POLLIN != 0) {
                // add the byte, and increment i
                const byte = stdin_file.reader().readByte() catch |err| switch (err) {
                    error.EndOfStream => return null,
                    else => return err,
                };
                // if that's the delimiter, return
                if (byte == '\n') {
                    return line_buf[0..i];
                }
                // add the byte to the buffer, and incrment the index
                line_buf[i] = byte;
                i += 1;
                // if we're out of space, signal that the stream is too long
                if (i == line_buf.len) {
                    return error.StreamTooLong;
                }
            } else {
                // if we're not supposed to be running, quit now
                if (!self.viewer.running) {
                    return null;
                }
                // suspend so the graphics can run
                self.yield();
            }
        }
    }

    fn loadPalette(self: *REPL, id: u8) !void {
        // TODO battle tracks run in 4bpp mode unlike the rest of the tracks, figure out how the
        // colors are mapped there, because our current method gets strange results for these tracks

        // noticed that by forcing the game to load a battle track in another mode, the colors
        // appear in-game as they do in this editor

        // palette entries for 3d stuff are here
        var palette_view = self.rom.view(try self.rom.view(0x3F649 + @as(u24, id) * 3).reader().readIntLittle(u24));
        for (self.viewer.renderer.palette) |*color| {
            color.* = processPalette(try palette_view.reader().readIntLittle(u16));
        }
        // entries for bg palette (may be used by 3d, see: sky ramp)
        palette_view.pos = try self.rom.view(0x3F6F1 + @as(u24, id) * 3).reader().readIntLittle(u24);
        for (self.viewer.renderer.palette[0..16]) |*color| {
            color.* = processPalette(try palette_view.reader().readIntLittle(u16));
        }
    }

    fn modelTest(self: *REPL) !void {
        self.viewer.track.clear(self.allocator);
        var model_id: u16 = 0xA040 + 0x1C;
        var x: u8 = 0;
        var y: u8 = 0;
        var z: u8 = 0;
        while (model_id < 0xFE88) : (model_id += 0x1C) {
            try self.viewer.track.append(self.allocator, .{
                .x = (@as(i16, x) - 5) * 6000,
                .y = (@as(i16, y) - 5) * 6000,
                .z = (@as(i16, z) - 5) * 6000,
                .dir = 0,
                .model_id = model_id,
                .code_pointer = 0x9C5B6, // dummy code pointer so something renders
            });
            x += 1;
            if (x == 10) {
                x = 0;
                y += 1;
                if (y == 10) {
                    y = 0;
                    z += 1;
                }
            }
        }
        // load easy ride's palette
        try self.loadPalette(0);
        // yield so we don't print "> " until it's done loading
        self.yield();
    }

    fn showOne(self: *REPL, model_id: u16) !void {
        self.viewer.track.clear(self.allocator);
        try self.viewer.track.append(self.allocator, .{
            .x = 1000,
            .y = 0,
            .z = 0,
            .dir = 0,
            .model_id = model_id,
            .code_pointer = 0x9C5B6, // hardcoded code pointer so something renders
        });
        // load easy ride's palette
        try self.loadPalette(0);
        // yield so we don't print "> " until it's done loading
        self.yield();
    }

    fn loadTrack(self: *REPL, id: u8) !void {
        var view = self.rom.view(try self.rom.view(0x3F4A5 + @as(u24, id) * 3).reader().readIntLittle(u24));
        const reader = view.reader();

        // http://acmlm.kafuka.org/board/thread.php?id=5441
        var dir: u8 = 0;
        self.viewer.track.clear(self.allocator);
        while (true) {
            switch (try reader.readByte()) {
                0x02, 0x0C => {
                    const x = try reader.readIntLittle(i16);
                    const y = try reader.readIntLittle(i16);
                    const z = try reader.readIntLittle(i16);
                    const model_id = try reader.readIntLittle(u16);
                    view.pos += 2;
                    const code_pointer = try reader.readIntLittle(u24);
                    view.pos += 8;
                    try self.viewer.track.append(self.allocator, .{
                        .x = x,
                        .y = y,
                        .z = z,
                        .dir = dir,
                        .model_id = model_id,
                        .code_pointer = code_pointer,
                    });
                },
                0x08 => {
                    dir = try reader.readByte();
                },
                0x04 => break,
                0x06 => {},
                0x14, 0x1A => view.pos += 2,
                0x16, 0x18 => view.pos += 3,
                0x12 => view.pos += 8,
                0x0A => view.pos += 24,
                0x0E => view.pos += 25,
                else => return error.UnrecognizedTag,
            }
        }
        try self.loadPalette(id);
        // yield so we don't print "> " until it's done loading
        self.yield();
    }

    fn parseTrackNumberOrName(self: REPL, arg: []const u8) u8 {
        const parsed_index = std.fmt.parseUnsigned(u8, arg, 10) catch 0;
        if (parsed_index > 0 and parsed_index <= track_count) {
            return parsed_index;
        } else for (self.track_names.names) |name, i| {
            if (strEq(arg, name)) {
                return @intCast(u8, i) + 1;
            }
        } else {
            return 0;
        }
    }

    fn tryRun(self: *REPL) !void {
        // get i/o
        const stdin_file = std.io.getStdIn();
        const stdout_file = std.io.getStdOut();
        const stdin = stdin_file.reader();
        const stdout = stdout_file.writer();
        // display a welcoming message
        try stdout.writeAll("welcome to trax viewer\ntype help for help\n");
        // allocate an input buffer
        const line_buf = try self.allocator.alloc(u8, 4096);
        defer self.allocator.free(line_buf);
        // read-eval-print-loop
        while (self.viewer.running) {
            // get a line from stdin
            try stdout.writeAll("> ");
            // break on EOF
            const input = (try self.readLine(stdin_file, line_buf)) orelse break;
            // process it
            // TODO clean up, including catching errors per-command
            if (strEq(input, "h") or strEq(input, "help")) {
                try stdout.writeAll(
                    \\h, help            | display this help
                    \\q, quit            | quit trax viewer
                    \\tracks             | print track names
                    \\load <number/name> | view a track
                    \\show <model_id>    | view a single model, id is 4 hex digits
                    \\debug              | test of viewing all models
                    \\export <filename>  | export track to a .obj file (work in progress)
                    \\
                );
            } else if (strEq(input, "q") or strEq(input, "quit")) {
                self.viewer.running = false;
                break;
            } else if (strEq(input, "tracks")) {
                for (self.track_names.names) |name, i| {
                    try stdout.print("{: >2} {s}\n", .{ i, name });
                }
            } else if (strEq(input, "debug")) {
                try self.modelTest();
            } else if (std.mem.startsWith(u8, input, "export ")) {
                const filename = input[7..];
                const file = try std.fs.cwd().createFile(filename, .{});
                defer file.close();
                var obj_exporter = ObjExporter(std.fs.File.Writer).init(file.writer());
                self.viewer.track.writeTo(self.rom, 0, &obj_exporter);
            } else if (std.mem.startsWith(u8, input, "load ")) {
                const i = self.parseTrackNumberOrName(input[5..]);
                if (i == 0) {
                    try stdout.writeAll("track not found\n");
                } else {
                    try stdout.print("loading {s}\n", .{self.track_names.names[i - 1]});
                    self.loadTrack(i - 1) catch |err| {
                        try stdout.print("error while loading track: {}\n", .{err});
                        if (@errorReturnTrace()) |trace| {
                            std.debug.dumpStackTrace(trace.*);
                        }
                        self.viewer.track.clear(self.allocator);
                    };
                }
            } else if (std.mem.startsWith(u8, input, "show ")) {
                const id = if (input.len == 9) std.fmt.parseUnsigned(u16, input[5..], 16) catch null else null;
                if (id) |i| {
                    try self.showOne(i);
                } else {
                    try stdout.writeAll("expected a 4-digit hex id\n");
                }
            } else {
                try stdout.writeAll("unknown command\n");
            }
        }
    }

    pub fn run(self: *REPL) void {
        util.errorBoundary(self.tryRun());
        self.viewer.running = false;
    }
};
