const std = @import("std");
const print = std.debug.print;
const allocator = std.heap.page_allocator;
const parser = @import("parser.zig");
const codewriter = @import("codewriter.zig");

pub fn main() anyerror!void {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        print("Usage: {s} <dir/file.vm>\n", .{args[0]});
        return;
    }

    const filename = args[1];
    const cwd = std.fs.cwd();
    const file = try cwd.openFile(filename, .{ .read = true });
    defer file.close();

    const stat = try file.stat();
    var asmfilename: []u8 = undefined;
    var outputDir: std.fs.Dir = undefined;

    if (stat.kind == .File) {
        const noextension = filename[0 .. filename.len - 2]; // file name without extension "vm"
        asmfilename = try std.mem.concat(allocator, u8, &[_][]const u8{ noextension, "asm" });
        outputDir = try cwd.openDir(std.fs.path.dirname(filename).?, .{ .iterate = true });
    } else if (stat.kind == .Directory) {
        asmfilename = try std.mem.concat(allocator, u8, &[_][]const u8{ filename, "/", std.fs.path.basename(filename), ".asm" });
        outputDir = try cwd.openDir(filename, .{ .iterate = true });
    } else {
        unreachable;
    }
    defer allocator.free(asmfilename);
    defer outputDir.close();

    // truncate asm file for writing
    const asmfile = try cwd.createFile(asmfilename, .{ .truncate = true });
    defer asmfile.close();
    const writer = asmfile.writer();

    const linebuf = try allocator.alloc(u8, 1024);
    defer allocator.free(linebuf);

    try codewriter.init(allocator, writer);
    defer codewriter.deinit();

    // iterate over the outputDir to find the .vm files in it
    var iter = outputDir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind == .File and std.mem.endsWith(u8, entry.name, ".vm")) {
            const vmfile = try outputDir.openFile(entry.name, .{ .read = true });
            defer vmfile.close();

            const reader = vmfile.reader();
            try codewriter.setFileName(entry.name[0 .. entry.name.len - 3]); // file name without extension ".vm"

            // translate
            while (try parser.nextLine(reader, linebuf)) |line| {
                if (try parser.parseCMD(line)) |cmd| {
                    try writer.print("// {s}\n", .{line});

                    switch (cmd.type) {
                        .C_PUSH, .C_POP => try codewriter.pushpop(cmd),
                        .C_ARITHMETIC => try codewriter.arithmetic(cmd),
                        .C_LABEL => try codewriter.label(cmd),
                        .C_GOTO => try codewriter.goto(cmd),
                        .C_IF => try codewriter.if_goto(cmd),
                        .C_CALL => try codewriter.call(cmd),
                        .C_FUNCTION => try codewriter.function(cmd),
                        .C_RETURN => try codewriter.@"return"(),
                    }
                }
            }
        }
    }
}
