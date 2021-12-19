const std = @import("std");
const Command = @import("parser.zig").Command;

const asmcode1 =
    \\@SP
    \\A=M-1
;
const asmcode2 =
    \\@SP
    \\AM=M-1
    \\D=M
    \\A=A-1
;

pub fn arithmetic(cmd: Command, buffer: []u8) ![]const u8 {
    const S = struct {
        var index: usize = 0; // static local variable
    };

    var buf: []u8 = undefined;
    var sign: u8 = undefined;
    switch (cmd.arg1[0]) {
        'a', 's', 'o' => { // add, and, sub, or
            if (std.mem.eql(u8, cmd.arg1, "add")) {
                sign = '+';
            } else if (std.mem.eql(u8, cmd.arg1, "and")) {
                sign = '&';
            } else if (std.mem.eql(u8, cmd.arg1, "sub")) {
                sign = '-';
            } else if (std.mem.eql(u8, cmd.arg1, "or")) {
                sign = '|';
            } else {
                unreachable;
            }
            buf = try std.fmt.bufPrint(buffer, "{s}\nM=M{c}D\n", .{ asmcode2, sign });
        },
        'e', 'g', 'l' => { // eq, gt, lt
            buf = try std.fmt.bufPrint(buffer,
                \\{0s}
                \\D=M-D
                \\@TRUE{1d}
                \\D;J{2c}{3c}
                \\{4s}
                \\M=0
                \\@CONTINUE{1d}
                \\0;JMP
                \\(TRUE{1d})
                \\{4s}
                \\M=-1
                \\(CONTINUE{1d})
                \\
            , .{
                asmcode2,
                S.index,
                cmd.arg1[0] - 32,
                cmd.arg1[1] - 32,
                asmcode1,
            });
            S.index += 1;
        },
        'n' => { // neg, not
            if (std.mem.eql(u8, cmd.arg1, "neg")) {
                sign = '-';
            } else if (std.mem.eql(u8, cmd.arg1, "not")) {
                sign = '!';
            } else {
                unreachable;
            }
            buf = try std.fmt.bufPrint(buffer, "{s}\nM={c}M\n", .{ asmcode1, sign });
        },
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
