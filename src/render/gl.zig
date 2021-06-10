const std = @import("std");

const zlm = @import("zlm");

pub const c = @cImport(@cInclude("GLES3/gl3.h"));

// add to this as needed, there's a lot and i'd rather not list them all
pub const Feature = enum(c.GLenum) {
    depth_test = c.GL_DEPTH_TEST,
    cull_face = c.GL_CULL_FACE,
};

pub fn enable(feature: Feature) void {
    c.glEnable(@enumToInt(feature));
}

pub const BufferBit = enum(c.GLenum) {
    color = c.GL_COLOR_BUFFER_BIT,
    depth = c.GL_DEPTH_BUFFER_BIT,
    stencil = c.GL_STENCIL_BUFFER_BIT,
};

pub fn clear(bits: []const BufferBit) void {
    var b: c.GLbitfield = 0;
    for (bits) |bit| b |= @enumToInt(bit);
    c.glClear(b);
}

pub fn clearColor(r: f32, g: f32, b: f32, a: f32) void {
    c.glClearColor(r, g, b, a);
}

pub fn viewport(x: c_int, y: c_int, w: c_int, h: c_int) void {
    c.glViewport(x, y, w, h);
}

fn checkSuccess(
    allocator: *std.mem.Allocator,
    object: c_uint,
    status: c.GLenum,
    getStatus: fn (c_uint, c.GLenum, *c_int) callconv(.C) void,
    getInfoLog: fn (c_uint, c_int, ?*c_int, [*]u8) callconv(.C) void,
) bool {
    var success: c_int = undefined;
    getStatus(object, status, &success);
    if (success == 0) {
        var len: c_int = undefined;
        getStatus(object, c.GL_INFO_LOG_LENGTH, &len);
        const log = allocator.alloc(u8, @intCast(usize, len)) catch {
            std.debug.print("shaders have errors <no memory to allocate error log>", .{});
            return false;
        };
        defer allocator.free(log);
        getInfoLog(object, len, null, log.ptr);
        std.debug.print("shaders have errors\n{s}", .{log});
        return false;
    }
    return true;
}

pub const ShaderType = enum(c_uint) {
    vertex = c.GL_VERTEX_SHADER,
    fragment = c.GL_FRAGMENT_SHADER,
};

pub const Shader = struct {
    handle: c_uint,

    pub fn init(shader_type: ShaderType) !Shader {
        const handle = c.glCreateShader(@enumToInt(shader_type));
        if (handle == 0) {
            return error.InternalGLError;
        }
        return Shader{ .handle = handle };
    }

    pub fn deinit(self: Shader) void {
        c.glDeleteShader(self.handle);
    }

    pub fn source(self: Shader, src: []const u8) void {
        self.sourcesComptime(1, .{src});
    }

    pub fn sourcesComptime(self: Shader, comptime n: comptime_int, srcs: [n][]const u8) void {
        var src_ptrs: [n][*]const u8 = undefined;
        var lengths: [n]c_int = undefined;
        for (srcs) |p, i| {
            src_ptrs[i] = p.ptr;
            lengths[i] = @intCast(c_int, p.len);
        }
        self.sources(&src_ptrs, &lengths);
    }

    pub fn sources(self: Shader, srcs: []const [*]const u8, lengths: []const c_int) void {
        std.debug.assert(srcs.len == lengths.len);
        c.glShaderSource(self.handle, @intCast(c_int, srcs.len), srcs.ptr, lengths.ptr);
    }

    pub fn compile(self: Shader, temp_allocator: *std.mem.Allocator) !void {
        c.glCompileShader(self.handle);
        if (!checkSuccess(temp_allocator, self.handle, c.GL_COMPILE_STATUS, c.glGetShaderiv, c.glGetShaderInfoLog)) {
            return error.CompileError;
        }
    }
};

pub const Program = struct {
    handle: c_uint,

    pub fn init() !Program {
        const handle = c.glCreateProgram();
        if (handle == 0) {
            return error.InternalGLError;
        }
        return Program{ .handle = handle };
    }

    pub fn deinit(self: Program) void {
        c.glDeleteProgram(self.handle);
    }

    pub fn attach(self: Program, shader: Shader) void {
        c.glAttachShader(self.handle, shader.handle);
    }

    pub fn link(self: Program, temp_allocator: *std.mem.Allocator) !void {
        c.glLinkProgram(self.handle);
        if (!checkSuccess(temp_allocator, self.handle, c.GL_LINK_STATUS, c.glGetProgramiv, c.glGetProgramInfoLog)) {
            return error.LinkError;
        }
    }

    pub fn use(self: Program) void {
        c.glUseProgram(self.handle);
    }

    pub fn getUniformLocation(self: Program, name: [*:0]const u8) !c_int {
        const location = c.glGetUniformLocation(self.handle, name);
        if (location == -1) {
            return error.NoSuchLocation;
        }
        return location;
    }

    pub fn uniform(location: c_int, value: anytype) void {
        switch (@typeInfo(@TypeOf(value))) {
            .Float => |ti| if (ti.bits <= 32) {
                c.glUniform1f(location, value);
                return;
            },
            .ComptimeFloat => {
                c.glUniform1f(location, value);
                return;
            },
            .Int => |ti| if ((ti.signedness == .unsigned and ti.bits <= 31) or ti.bits <= 32) {
                c.glUniform1i(location, value);
                return;
            },
            .ComptimeInt => {
                c.glUniform1i(location, value);
                return;
            },
            .Pointer, .Array => {
                const ti = @typeInfo(@TypeOf(value));
                if ((ti == .Pointer and ti.Pointer.size != .One and ti.Pointer.size != .Slice) or ti == .Array) {
                    @compileError("convert this to a slice before passing");
                }
                // TODO add slices of ints or floats, luckily we don't need those rn
            },
            else => {},
        }
        inline for (.{ "2", "3", "4" }) |t| {
            const Vec = @field(zlm, "Vec" ++ t);
            const vecFunc = @field(c, "glUniform" ++ t ++ "fv");
            if (@TypeOf(value) == Vec) {
                vecFunc(location, 1, @ptrCast([*]const f32, &value));
                return;
            } else if (@TypeOf(value) == []const Vec) {
                vecFunc(location, @intCast(c_int, value.len), @ptrCast([*]const f32, value.ptr));
                return;
            }
            const Mat = @field(zlm, "Mat" ++ t);
            const matFunc = @field(c, "glUniformMatrix" ++ t ++ "fv");
            if (@TypeOf(value) == Mat) {
                matFunc(location, 1, 0, @ptrCast([*]const f32, &value));
                return;
            } else if (@TypeOf(value) == []const Mat) {
                matFunc(location, @intCast(c_int, value.len), 0, @ptrCast([*]const f32, value.ptr));
                return;
            }
        }
        @compileError("unsupported type");
    }
};

pub const PrimitiveMode = enum(c.GLenum) {
    points = c.GL_POINTS,
    line_strip = c.GL_LINE_STRIP,
    line_loop = c.GL_LINE_LOOP,
    lines = c.GL_LINES,
    triangle_strip = c.GL_TRIANGLE_STRIP,
    triangle_fan = c.GL_TRIANGLE_FAN,
    triangles = c.GL_TRIANGLES,
};

fn BatchManagement(comptime T: type, comptime ctor: anytype, comptime dtor: anytype) type {
    if (@sizeOf(T) != @sizeOf(c_uint)) {
        @compileError("cannot use this mixin due to size mismatch");
    }
    return struct {
        pub fn init() T {
            return initComptime(1)[0];
        }

        pub fn initSlice(slice: []T) void {
            ctor(@intCast(c_int, slice.len), @ptrCast([*]c_uint, slice.ptr));
        }

        pub fn initComptime(comptime count: comptime_int) [count]T {
            var arr: [count]T = undefined;
            initSlice(&arr);
            return arr;
        }

        pub fn deinit(self: T) void {
            deinitSlice(&.{self});
        }

        pub fn deinitSlice(slice: []const T) void {
            dtor(@intCast(c_int, slice.len), @ptrCast([*]const c_uint, slice.ptr));
        }
    };
}

pub const VertexArray = struct {
    handle: c_uint,

    pub usingnamespace BatchManagement(VertexArray, c.glGenVertexArrays, c.glDeleteVertexArrays);

    pub fn bind(self: VertexArray) void {
        c.glBindVertexArray(self.handle);
    }

    pub fn draw(mode: PrimitiveMode, first: c_int, count: c_int) void {
        c.glDrawArrays(@enumToInt(mode), first, count);
    }

    fn toGLType(comptime T: type) c.GLenum {
        return switch (T) {
            bool => c.GL_UNSIGNED_BYTE,
            f16 => c.GL_HALF_FLOAT,
            f32 => c.GL_FLOAT,
            else => {
                comptime var bits = 1;
                inline while (bits <= 8) : (bits += 1) {
                    if (T == std.meta.Int(.unsigned, bits)) return c.GL_UNSIGNED_BYTE;
                    if (T == std.meta.Int(.signed, bits)) return c.GL_BYTE;
                }
                inline while (bits <= 16) : (bits += 1) {
                    if (T == std.meta.Int(.unsigned, bits)) return c.GL_UNSIGNED_SHORT;
                    if (T == std.meta.Int(.signed, bits)) return c.GL_SHORT;
                }
                inline while (bits <= 32) : (bits += 1) {
                    if (T == std.meta.Int(.unsigned, bits)) return c.GL_UNSIGNED_INT;
                    if (T == std.meta.Int(.signed, bits)) return c.GL_INT;
                }
                @compileError("cannot get GL type for this type");
            },
        };
    }

    fn attributeScalar(index: c_uint, amt: u3, stride: c_int, comptime F: type, pointer: ?*const c_void) void {
        const gl_type = toGLType(F);
        switch (gl_type) {
            c.GL_HALF_FLOAT, c.GL_FLOAT => {
                c.glVertexAttribPointer(index, amt, gl_type, 0, stride, pointer);
            },
            else => {
                c.glVertexAttribIPointer(index, amt, gl_type, stride, pointer);
            },
        }
    }

    pub fn attribute(index: c_uint, comptime T: type, comptime field: []const u8) void {
        const F = @TypeOf(@field(@as(T, undefined), field));
        const stride = @sizeOf(T);
        const pointer = @intToPtr(?*const c_void, @byteOffsetOf(T, field));
        defer c.glEnableVertexAttribArray(index);
        inline for (.{ "2", "3", "4" }) |t| {
            const Vec = @field(zlm, "Vec" ++ t);
            if (F == Vec) {
                c.glVertexAttribPointer(index, t[0] - '0', c.GL_FLOAT, 0, stride, pointer);
                return;
            }
        }
        if (@typeInfo(F) == .Array) {
            const ti = @typeInfo(F).Array;
            if (ti.len >= 1 and ti.len <= 4) {
                attributeScalar(index, @intCast(u3, ti.len), stride, ti.child, pointer);
                return;
            }
        }
        attributeScalar(index, 1, stride, F, pointer);
    }
};

pub const BufferType = enum(c.GLenum) {
    array = c.GL_ARRAY_BUFFER,
    read = c.GL_COPY_READ_BUFFER,
    write = c.GL_COPY_WRITE_BUFFER,
    element_array = c.GL_ELEMENT_ARRAY_BUFFER,
    pixel_pack = c.GL_PIXEL_PACK_BUFFER,
    pixel_unpack = c.GL_PIXEL_UNPACK_BUFFER,
    transform_feedback = c.GL_TRANSFORM_FEEDBACK_BUFFER,
    uniform = c.GL_UNIFORM_BUFFER,
};

pub const BufferUsage = enum(c.GLenum) {
    stream_draw = c.GL_STREAM_DRAW,
    stream_read = c.GL_STREAM_READ,
    stream_copy = c.GL_STREAM_COPY,
    static_draw = c.GL_STATIC_DRAW,
    static_read = c.GL_STATIC_READ,
    static_copy = c.GL_STATIC_COPY,
    dynamic_draw = c.GL_DYNAMIC_DRAW,
    dynamic_read = c.GL_DYNAMIC_READ,
    dynamic_copy = c.GL_DYNAMIC_COPY,
};

pub const Buffer = struct {
    handle: c_uint,

    pub usingnamespace BatchManagement(Buffer, c.glGenBuffers, c.glDeleteBuffers);

    pub fn bind(self: Buffer, buffer_type: BufferType) void {
        c.glBindBuffer(@enumToInt(buffer_type), self.handle);
    }

    pub fn data(buffer_type: BufferType, slice: anytype, usage: BufferUsage) void {
        c.glBufferData(@enumToInt(buffer_type), @intCast(c_long, @sizeOf(@typeInfo(@TypeOf(slice)).Pointer.child) * slice.len), slice.ptr, @enumToInt(usage));
    }
};

pub const TextureTarget = enum(c.GLenum) {
    @"2d" = c.GL_TEXTURE_2D,
    @"3d" = c.GL_TEXTURE_3D,
    @"2d_array" = c.GL_TEXTURE_2D_ARRAY,
    cube_map = c.GL_TEXTURE_CUBE_MAP,
};

pub const TextureMinFilter = enum(c_int) {
    nearest = c.GL_NEAREST,
    linear = c.GL_LINEAR,
    nearest_mipmap_nearest = c.GL_NEAREST_MIPMAP_NEAREST,
    linear_mipmap_nearest = c.GL_LINEAR_MIPMAP_NEAREST,
    nearest_mipmap_linear = c.GL_NEAREST_MIPMAP_LINEAR,
    linear_mipmap_linear = c.GL_LINEAR_MIPMAP_LINEAR,
};

pub const TextureMagFilter = enum(c_int) {
    nearest = c.GL_NEAREST,
    linear = c.GL_LINEAR,
};

pub const Texture = struct {
    handle: c_uint,

    pub usingnamespace BatchManagement(Texture, c.glGenTextures, c.glDeleteTextures);

    pub fn bind(self: Texture, target: TextureTarget) void {
        c.glBindTexture(@enumToInt(target), self.handle);
    }

    pub fn minFilter(target: TextureTarget, f: TextureMinFilter) void {
        c.glTexParameteri(@enumToInt(target), c.GL_TEXTURE_MIN_FILTER, @enumToInt(f));
    }

    pub fn magFilter(target: TextureTarget, f: TextureMagFilter) void {
        c.glTexParameteri(@enumToInt(target), c.GL_TEXTURE_MAG_FILTER, @enumToInt(f));
    }

    // TODO better abstraction
    pub fn image2D(
        target: TextureTarget,
        lod: c_int,
        internal_format: c_int,
        width: c_int,
        height: c_int,
        format: c.GLenum,
        pixel_type: c.GLenum,
        data: [*]const u8,
    ) void {
        c.glTexImage2D(@enumToInt(target), lod, internal_format, width, height, 0, format, pixel_type, data);
    }
};
