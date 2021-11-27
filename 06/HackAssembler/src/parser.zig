const std = @import("std");
const builtin = @import("builtin");
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const File = std.fs.File;

fn nextLine(allocator: *Allocator, asmfile: File) !?[]const u8 {
    const buffer = try allocator.alloc(u8, 1024);
    const reader = asmfile.reader();

    // 显示指定变量类型为 []const u8，把 []u8 赋值给它
    // 因为下面的 trimRight 返回 []const u8，不能把 []const u8 赋值给 []u8
    var line: []const u8 = (try reader.readUntilDelimiterOrEof(buffer, '\n')) orelse return null;

    // trim annoying windows-only carriage return character
    if (builtin.os.tag == .windows) {
        line = std.mem.trimRight(u8, line, "\r");
    }

    return line;
}

fn trimLine(symtable: *std.StringHashMap(usize), line: []const u8, pc: *usize) !?[]const u8 {
    var trimline = std.mem.trimLeft(u8, line, " \t");
    if (trimline.len == 0) return null;

    return switch (trimline[0]) {
        '/' => null,
        '(' => blk: {
            var sym = trimline[1 .. std.mem.indexOfScalar(u8, trimline, ')').?];
            try symtable.put(sym, pc.*);
            break :blk null;
        },
        else => blk: {
            pc.* += 1;
            break :blk trimline;
        },
    };
}

pub const Parser = struct {
    const Self = @This();

    arena: std.heap.ArenaAllocator,
    statements: std.ArrayList([]const u8),
    symtable: std.StringHashMap(usize),

    pub fn init(allocator: *Allocator, asmfile: File) !Self {
        var symtable = std.StringHashMap(usize).init(allocator);
        var list = std.ArrayList([]const u8).init(allocator);
        var arena = std.heap.ArenaAllocator.init(allocator);

        var pc: usize = 0;
        while (try nextLine(&arena.allocator, asmfile)) |line| {
            var ins = try trimLine(&symtable, line, &pc);
            if (ins != null) {
                try list.append(ins.?);
            }
        }

        return Self{
            .arena = arena,
            .statements = list,
            .symtable = symtable,
        };
    }

    pub fn deinit(self: *Self) void {
        self.arena.deinit();
        self.statements.deinit();
        self.symtable.deinit();
    }
};
