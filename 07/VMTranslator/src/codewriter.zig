const std = @import("std");
const builtin = @import("builtin");
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const Command = @import("parser.zig").Command;

const @"SP++" =
    \\@SP
    \\M=M+1
    \\
;
const @"SP--" =
    \\@SP
    \\AM=M-1
    \\
;
const @"SP--2" = @"SP--" ++
    \\D=M
    \\A=A-1
    \\
;

pub fn arithmetic(cmd: Command, buffer: []u8) ![]const u8 {
    var buf: []u8 = undefined;
    switch (cmd.arg1[0]) {
        'a' => {
            if (std.mem.eql(u8, cmd.arg1, "add")) {
                buf = try std.fmt.bufPrint(buffer, "{s}M=M+D\n", .{@"SP--2"});
            } else if (std.mem.eql(u8, cmd.arg1, "and")) {
                buf = try std.fmt.bufPrint(buffer, "{s}M=M&D\n", .{@"SP--2"});
            } else {
                unreachable;
            }
        },
        'e' => {},
        'g' => {},
        'n' => {},
        'l' => {},
        's' => {},
        else => unreachable,
    }

    return buf;
}

pub fn pushpop(cmd: Command, buffer: []u8, basename: []const u8) ![]const u8 {
    var buf: []u8 = undefined;

    switch (cmd.arg1[0]) {
        'c' => { // constant
            buf = try std.fmt.bufPrint(buffer,
                \\@{d}
                \\D=A
                \\@SP
                \\A=M
                \\M=D
                \\@SP
                \\M=M+1
                \\
            , .{cmd.arg2});
        },
        'l' => {},
        's' => {
            if (cmd.type == .C_PUSH) {
                buf = try std.fmt.bufPrint(buffer,
                    \\@{s}.{d}
                    \\D=A
                    \\@SP
                    \\A=M
                    \\M=D
                    \\@SP
                    \\M=M+1
                    \\
                , .{ basename, cmd.arg2 });
            } else {
                buf = try std.fmt.bufPrint(buffer,
                    \\@SP
                    \\AM=M-1
                    \\D=M
                    \\@{s}.{d}
                    \\M=D
                    \\
                , .{ basename, cmd.arg2 });
            }
        },
        'a' => {},
        't' => {},
        'p' => {},
        else => unreachable,
    }

    return buf;
}
