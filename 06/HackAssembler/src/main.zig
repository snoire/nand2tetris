const std = @import("std");
const builtin = @import("builtin");
const print = std.debug.print;
const allocator = std.heap.page_allocator;

const MAX_FILE_SIZE = 0x1000000;

fn nextLine(reader: anytype, buffer: []u8) !?[]const u8 {
    // 显示指定变量类型为 []const u8，把 []u8 赋值给它
    // 因为下面的 trimRight 返回 []const u8，不能把 []const u8 赋值给 []u8
    var line: []const u8 = (try reader.readUntilDelimiterOrEof(buffer, '\n')) orelse return null;

    // trim annoying windows-only carriage return character
    if (builtin.os.tag == .windows) {
        line = std.mem.trimRight(u8, line, "\r");
    }

    return line;
}

pub fn main() anyerror!void {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        print("Usage: {s} <file.asm>\n", .{args[0]});
        return;
    }

    // open asm file
    const cwd = std.fs.cwd();
    const asmfile = try cwd.openFile(args[1], .{ .read = true });
    defer asmfile.close();

    // parse asm
    const reader = asmfile.reader();
    var buf: [2048]u8 = undefined;

    while (try nextLine(reader, &buf)) |line| {
        print("{s}\n", .{line});
    }


    // write to hack file
    const filebase = std.mem.trimRight(u8, args[1], "asm");
    const hackfile = try std.mem.concat(allocator, u8, &[_][]const u8{filebase, "hack"});
    defer allocator.free(hackfile);

    // TODO
    //print("filename: {s}\n", .{hackfile});
    //print("{s}", .{bytes});
    //try cwd.writeFile(hackfile, bytes);
}

test "basic test" {
    try std.testing.expectEqual(10, 3 + 7);
}
