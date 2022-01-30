const std = @import("std");
const parser = @import("parser.zig");
const Parser = parser.Parser;
const code = @import("code.zig");
const Code = code.Code;
const print = std.debug.print;
const allocator = std.heap.page_allocator;

pub fn main() anyerror!void {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        print("Usage: {s} <file.asm>\n", .{args[0]});
        return;
    }

    // open asm file
    const cwd = std.fs.cwd();
    const asmfile = try cwd.openFile(args[1], .{});
    defer asmfile.close();

    // truncate hack file for writing
    const filebase = std.mem.trimRight(u8, args[1], "asm");
    const hackfilename = try std.mem.concat(allocator, u8, &[_][]const u8{ filebase, "hack" });
    defer allocator.free(hackfilename);
    const hackfile = try cwd.createFile(hackfilename, .{ .truncate = true });
    defer hackfile.close();

    // parse asm
    var p = try Parser.init(allocator, asmfile);
    defer p.deinit();

    var c = try Code.init(allocator, &p.symtable);
    defer c.deinit();

    // write to hack file
    for (p.statements.items) |statement| {
        try hackfile.writer().print("{s}\n", .{c.translate(statement)});
    }
}
