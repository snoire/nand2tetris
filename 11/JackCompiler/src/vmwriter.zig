const std = @import("std");
const Self = @This();

const Segment = enum {
    argument,
    local,
    static,
    constant,
    this,
    that,
    pointer,
    temp,
};

const Command = enum {
    add,
    sub,
    neg,
    eq,
    gt,
    lt,
    @"and",
    @"or",
    not,
};

writer: std.fs.File.Writer,

fn print(self: *Self, comptime format: []const u8, args: anytype) void {
    std.fmt.format(self.writer, format, args) catch unreachable;
}

pub fn push(self: *Self, segment: Segment, index: usize) void {
    self.print("{s} {s} {d}\n", .{ @src().fn_name, @tagName(segment), index });
}

pub fn pop(self: *Self, comptime segment: Segment, index: usize) void {
    comptime std.debug.assert(segment != .constant);
    self.print("{s} {s} {d}\n", .{ @src().fn_name, @tagName(segment), index });
}

pub fn arithmetic(self: *Self, cmd: Command) void {
    self.print("{s}\n", .{@tagName(cmd)});
}

pub fn label(self: *Self, lbl: []const u8) void {
    self.print("{s} {s}\n", .{ @src().fn_name, lbl });
}

pub fn goto(self: *Self, lbl: []const u8) void {
    self.print("{s} {s}\n", .{ @src().fn_name, lbl });
}

pub fn @"if-goto"(self: *Self, lbl: []const u8) void {
    self.print("{s} {s}\n", .{ @src().fn_name, lbl });
}

pub fn call(self: *Self, name: []const u8, nArgs: usize) void {
    self.print("{s} {s} {d}", .{ @src().fn_name, name, nArgs });
}

pub fn function(self: *Self, name: []const u8, nVars: usize) void {
    self.print("{s} {s} {d}", .{ @src().fn_name, name, nVars });
}

pub fn @"return"(self: *Self) void {
    self.print("{s}", .{@src().fn_name});
}
