const std = @import("std");
const print = std.debug.print;
const allocator = std.heap.page_allocator;
const parser = @import("tokenizer.zig").Parser;
const compiler = @import("compiler.zig");
const MAX_FILE_SIZE = 0x1000000;

pub fn main() anyerror!void {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        print("Usage: {s} <dir/file.jack>\n", .{args[0]});
        return;
    }

    const filename = args[1];
    const cwd = std.fs.cwd();
    const file = try cwd.openFile(filename, .{});
    defer file.close();

    const stat = try file.stat();
    if (stat.kind == .Directory) {
        const outputDirName = filename;
        var outputDir = try cwd.openDir(outputDirName, .{ .iterate = true });
        defer outputDir.close();

        // iterate over the outputDir to find the .jack files in it
        var iter = outputDir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind == .File and std.mem.endsWith(u8, entry.name, ".jack")) {
                try handleFile(outputDir, entry.name);
            }
        }
    } else if (stat.kind == .File) {
        if (std.mem.endsWith(u8, filename, ".jack")) {
            const outputDirName = std.fs.path.dirname(filename) orelse "./";
            var outputDir = try cwd.openDir(outputDirName, .{});
            defer outputDir.close();

            try handleFile(outputDir, std.fs.path.basename(filename));
        }
    } else {
        unreachable;
    }
}

fn handleFile(outputDir: std.fs.Dir, input: []const u8) !void {
    const jackfile = try outputDir.openFile(input, .{});
    defer jackfile.close();

    const bytes = try jackfile.readToEndAlloc(allocator, MAX_FILE_SIZE);
    defer allocator.free(bytes);

    const output = try std.mem.concat(allocator, u8, &[_][]const u8{ input[0 .. input.len - 4], "vm" });
    defer allocator.free(output);

    const vmfile = try outputDir.createFile(output, .{ .truncate = true });
    defer vmfile.close();
    const writer = vmfile.writer();

    var t = try parser.init(allocator, bytes);
    defer t.deinit();

    var tokens = try t.scan();
    var c = compiler.init(allocator, tokens.items, writer);
    defer c.deinit();

    try c.compileClass();
}
