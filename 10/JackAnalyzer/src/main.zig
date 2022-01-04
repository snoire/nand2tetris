const std = @import("std");
const print = std.debug.print;
const allocator = std.heap.page_allocator;

pub fn main() anyerror!void {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        print("Usage: {s} <dir/file.jack>\n", .{args[0]});
        return;
    }

    const filename = args[1];
    const cwd = std.fs.cwd();
    const file = try cwd.openFile(filename, .{ .read = true });
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

fn handleFile(_: std.fs.Dir, input: []const u8) !void {
    //const jackfile = try outputDir.openFile(input, .{ .read = true });
    //defer jackfile.close();
    //const reader = jackfile.reader();

    const output = try std.mem.concat(allocator, u8, &[_][]const u8{ input[0 .. input.len - 5], "T.xml" });
    defer allocator.free(output);

    //const xmlfile = try outputDir.createFile(output, .{ .truncate = true });
    //defer xmlfile.close();
    //const writer = xmlfile.writer();
    print("xml: {s}\n", .{output});
}
