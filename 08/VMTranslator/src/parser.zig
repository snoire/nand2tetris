const std = @import("std");
const Reader = std.fs.File.Reader;

inline fn atoi(string: []const u8) usize {
    var num: usize = 0;
    for (string) |char| {
        num = 10 * num + (char - '0');
    }
    return num;
}

pub const CommandType = enum {
    C_ARITHMETIC,
    C_PUSH,
    C_POP,
    C_LABEL,
    C_GOTO,
    C_IF,
    C_FUNCTION,
    C_RETURN,
    C_CALL,
};

pub const Command = struct {
    type: CommandType,
    arg1: []const u8,
    arg2: ?usize,

    pub fn create(typ: CommandType, arg1: []const u8, arg2: ?usize) Command {
        return Command{
            .type = typ,
            .arg1 = arg1,
            .arg2 = arg2,
        };
    }
};

pub fn nextLine(reader: Reader, buffer: []u8) !?[]const u8 {
    // 显式指定变量类型为 []const u8，把 []u8 赋值给它
    // 因为下面的 trimRight 返回 []const u8，不能把 []const u8 赋值给 []u8
    var line: []const u8 = (try reader.readUntilDelimiterOrEof(buffer, '\n')) orelse return null;

    // trim annoying windows-only carriage return character
    line = std.mem.trimRight(u8, line, "\r");
    return line;
}

pub fn parseCMD(preline: []const u8) !?Command {
    var line = std.mem.trimLeft(u8, preline, " \t");
    if (line.len == 0) return null;

    return switch (line[0]) {
        '/' => null,
        'p' => blk: {
            var cmd: ?Command = undefined;
            var it = std.mem.tokenize(u8, line[std.mem.indexOfScalar(u8, line, ' ').?..], " /");
            var arg: []const u8 = undefined;

            if (std.mem.startsWith(u8, line, "push")) {
                arg = it.next().?;
                cmd = Command.create(.C_PUSH, arg, atoi(it.next().?));
            } else if (std.mem.startsWith(u8, line, "pop")) {
                arg = it.next().?;
                cmd = Command.create(.C_POP, arg, atoi(it.next().?));
            } else {
                cmd = null;
            }

            break :blk cmd;
        },
        else => blk: {
            var lastidx = for (line) |char, i| {
                switch (char) {
                    ' ', '/' => {
                        break i;
                    },
                    else => {},
                }
            } else line.len;
            var token = line[0..lastidx];

            break :blk Command.create(.C_ARITHMETIC, token, null);
        },
    };
}
