const std = @import("std");
const Self = @This();

pub const Kind = enum(u2) { field, static, argument, local };

const VarAttr = struct {
    type: []const u8,
    kind: Kind,
    index: usize,
};

allocator: std.mem.Allocator,
indexes: [4]usize = [_]usize{0} ** 4,
classTable: std.StringHashMap(VarAttr),
subroutineTable: std.StringHashMap(VarAttr),

pub fn init(allocator: std.mem.Allocator) Self {
    return Self{
        .allocator = allocator,
        .classTable = std.StringHashMap(VarAttr).init(allocator),
        .subroutineTable = std.StringHashMap(VarAttr).init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.classTable.deinit();
    self.subroutineTable.deinit();
}

pub fn reset(self: *Self) void {
    self.subroutineTable.deinit();
    self.indexes[@enumToInt(Kind.argument)] = 0;
    self.indexes[@enumToInt(Kind.local)] = 0;
    self.subroutineTable = std.StringHashMap(VarAttr).init(self.allocator);
}

pub fn define(self: *Self, name: []const u8, @"type": []const u8, kind: Kind) !void {
    const kindIndex = @enumToInt(kind);
    var table = if (kindIndex <= @enumToInt(Kind.static)) &self.classTable else &self.subroutineTable;

    try table.put(name, .{ .type = @"type", .kind = kind, .index = self.indexes[kindIndex] });
    self.indexes[kindIndex] += 1;
}

pub fn varCount(self: Self, kind: Kind) usize {
    return self.indexes[@enumToInt(kind)];
}

pub fn kindOf(self: Self, name: []const u8) Kind {
    return if (self.subroutineTable.get(name)) |variable| variable.kind else self.classTable.get(name).?.kind;
}

pub fn typeOf(self: Self, name: []const u8) []const u8 {
    return if (self.subroutineTable.get(name)) |variable| variable.type else self.classTable.get(name).?.type;
}

pub fn indexOf(self: Self, name: []const u8) usize {
    return if (self.subroutineTable.get(name)) |variable| variable.index else self.classTable.get(name).?.index;
}
