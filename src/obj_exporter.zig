const std = @import("std");

const zlm = @import("zlm");

const Page = @import("render/texture_atlas.zig").Page;
const ROM = @import("rom.zig").ROM;
const util = @import("util.zig");

pub fn ObjExporter(comptime Writer: type) type {
    return struct {
        point_count: usize,
        point_start: usize,
        writer: Writer,

        pub fn init(writer: Writer) @This() {
            return .{
                .point_count = 0,
                .point_start = 1,
                .writer = writer,
            };
        }

        pub fn addPoint(self: *@This(), point: zlm.Vec3) !void {
            try self.writer.print("v {} {} {}\n", .{point.x, point.y, point.z});
            self.point_count += 1;
        }

        pub fn drawLine(self: *@This(), points: [2]u8, normal: zlm.Vec3, colors: [10]u8) !void {
            try self.writer.print("l {} {}\n", .{@as(u16, points[0]) + self.point_start, @as(u16, points[1]) + self.point_start});
        }

        pub fn drawTri(self: *@This(), points: [3]u8, normal: zlm.Vec3, colors: [10]u8) !void {
            // TODO normals, colors, etc
            try self.writer.print("f {} {} {}\n", .{@as(u16, points[0]) + self.point_start, @as(u16, points[1]) + self.point_start, @as(u16, points[2]) + self.point_start});
        }

        pub fn drawTexturedTri(self: *@This(), points: [3]u8, normal: zlm.Vec3, start: u8, uv: [3]zlm.Vec2) !void {
            // TODO "
            try self.writer.print("f {} {} {}\n", .{@as(u16, points[0]) + self.point_start, @as(u16, points[1]) + self.point_start, @as(u16, points[2]) + self.point_start});
        }

        pub fn endShape(self: *@This()) void {
            self.point_start += self.point_count;
            self.point_count = 0;
        }

        pub fn getTexture(self: *@This(), rom: ROM, address: u24, page: Page, width: u4, height: u4) !zlm.Vec2 {
            // TODO
            return zlm.Vec2.zero;
        }
    };
}