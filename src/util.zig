const std = @import("std");

/// Automatically produce a reader() function for an object given its read() function.
pub fn AutoReader(readFn: anytype) type {
    const read_info = @typeInfo(@TypeOf(readFn)).Fn;
    const ReadContext = read_info.args[0].arg_type.?;
    const ReadError = @typeInfo(read_info.return_type.?).ErrorUnion.error_set;
    return struct {
        pub fn reader(self: ReadContext) std.io.Reader(ReadContext, ReadError, readFn) {
            return .{ .context = self };
        }
    };
}

/// Catch and log an error.
pub fn errorBoundary(value: anytype) void {
    value catch |err| {
        std.log.err("{s}", .{err});
        if (@errorReturnTrace()) |trace| {
            std.debug.dumpStackTrace(trace.*);
        }
    };
}
