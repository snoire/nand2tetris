const std = @import("std");
const print = std.debug.print;
const allocator = std.heap.page_allocator;
const parser = @import("parser.zig");
const codewriter = @import("codewriter.zig");

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
    const vmfilename = args[1];
    const noextension = vmfilename[0 .. vmfilename.len - 2]; // file name without extension "vm"
    const asmfilename = try std.mem.concat(allocator, u8, &[_][]const u8{ noextension, "asm" });
    defer allocator.free(asmfilename);

    const asmfile = try cwd.createFile(asmfilename, .{ .truncate = true });
    defer asmfile.close();

    // translate
    const reader = vmfile.reader();
    const writer = asmfile.writer();

    const linebuf = try allocator.alloc(u8, 1024);
    defer allocator.free(linebuf);
    const cmdbuf = try allocator.alloc(u8, 1024);
    defer allocator.free(cmdbuf);

    try codewriter.init(allocator);
    defer codewriter.deinit();

    var basename = std.fs.path.basename(vmfilename);
    basename = basename[0 .. basename.len - 3]; // file name without extension ".vm"

    while (try parser.nextLine(reader, linebuf)) |line| {
        var cmd = try parser.parseCMD(line);
        if (cmd != null) {
            switch (cmd.?.type) {
                .C_PUSH, .C_POP => {
                    try writer.print(
                        \\//{s}
                        \\{s}
                    , .{ line, try codewriter.pushpop(cmd.?, cmdbuf, basename) });
                },
                .C_ARITHMETIC => {
                    try writer.print(
                        \\//{s}
                        \\{s}
                    , .{ line, try codewriter.arithmetic(cmd.?, cmdbuf) });
                },
                else => {},
            }
        }
    }
}
