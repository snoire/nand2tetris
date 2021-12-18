const std = @import("std");
const print = std.debug.print;
const allocator = std.heap.page_allocator;
const parser = @import("parser.zig");

pub fn main() anyerror!void {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        print("Usage: {s} <file.vm>\n", .{args[0]});
        return;
    }

    // open vm file
    const cwd = std.fs.cwd();
    const vmfile = try cwd.openFile(args[1], .{ .read = true });
    defer vmfile.close();

    // truncate asm file for writing
    const filebase = std.mem.trimRight(u8, args[1], "vm");
    const asmfilename = try std.mem.concat(allocator, u8, &[_][]const u8{ filebase, "asm" });
    defer allocator.free(asmfilename);
    const asmfile = try cwd.createFile(asmfilename, .{ .truncate = true });
    defer asmfile.close();
    //print("output: {s}\n", .{asmfilename});

    const reader = vmfile.reader();
    const buffer = try allocator.alloc(u8, 1024);
    defer allocator.free(buffer);

    while (try parser.nextLine(reader, buffer)) |line| {
        var cmd = try parser.parseCMD(line);
        if (cmd != null) {
            print("{any}\n", .{cmd});
        }
    }
}
