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

    // remove comments
    line = std.mem.sliceTo(line, '/');

    // trim annoying windows-only carriage return character and whiteSpace
    line = std.mem.trimRight(u8, line, " \t\r");

    return line;
}

pub fn parseCMD(line: []const u8) !?Command {
    if (line.len == 0) return null;

    var cmd: ?Command = undefined;
    var indexOfFristSpace = std.mem.indexOfScalar(u8, line, ' ');

    if (indexOfFristSpace == null) { // C_ARITHMETIC or C_RETURN
        cmd = Command.create(if (std.mem.eql(u8, line, "return")) .C_RETURN else .C_ARITHMETIC, line, null);
    } else {
        // skip the cmd name
        var it = std.mem.tokenize(u8, line[indexOfFristSpace.?..], " ");

        var arg1 = it.next().?;
        var arg2 = it.next();
        var cmdtype: CommandType = switch (line[0]) {
            // 这里没法自动推测，必须要这样写
            // https://stackoverflow.com/questions/68416521/zig-0-8-0-error-values-of-type-enum-literal-must-be-comptime-known
            'p' => if (std.mem.startsWith(u8, line, "push")) CommandType.C_PUSH else CommandType.C_POP,
            'l' => .C_LABEL,
            'i' => .C_IF,
            'g' => .C_GOTO,
            'f' => .C_FUNCTION,
            'c' => .C_CALL,
            else => unreachable,
        };

        cmd = Command.create(cmdtype, arg1, if (arg2 == null) null else atoi(arg2.?));
    }

    return cmd;
}
