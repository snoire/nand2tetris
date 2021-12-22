const std = @import("std");
const Allocator = std.mem.Allocator;
const Command = @import("parser.zig").Command;

const @"A=SP-1" =
    \\@SP
    \\A=M-1
;

const @"*SP=D, SP++" =
    \\@SP
    \\A=M
    \\M=D
    \\@SP
    \\M=M+1
;

const @"SP--, D=*SP" =
    \\@SP
    \\AM=M-1
    \\D=M
;

const @"SP--, D=*SP, A=SP-1" =
    \\@SP
    \\AM=M-1
    \\D=M
    \\A=A-1
;

// 这里不能是指针，init 函数中生成的哈希表要存到这里
var map: std.StringHashMap([]const u8) = undefined;

pub fn init(allocator: Allocator) !void {
    map = std.StringHashMap([]const u8).init(allocator);
    const kvpair = .{
        .{ "eq", "JEQ" },
        .{ "gt", "JGT" },
        .{ "lt", "JLT" },
        .{ "local", "LCL" },
        .{ "argument", "ARG" },
        .{ "this", "THIS" },
        .{ "that", "THAT" },
    };

    inline for (kvpair) |pair| {
        try map.put(pair.@"0", pair.@"1");
    }
}

pub fn deinit() void {
    map.deinit();
}

pub fn arithmetic(cmd: Command, buffer: []u8) ![]const u8 {
    const S = struct {
        var index: usize = 0; // static local variable
    };

    var buf: []u8 = undefined;
    var sign: u8 = undefined;
    switch (cmd.arg1[0]) {
        'e', 'g', 'l' => { // eq, gt, lt
            buf = try std.fmt.bufPrint(buffer,
                \\{0s}
                \\D=M-D
                \\@TRUE{1d}
                \\D;{2s}
                \\{3s}
                \\M=0
                \\@CONTINUE{1d}
                \\0;JMP
                \\(TRUE{1d})
                \\{3s}
                \\M=-1
                \\(CONTINUE{1d})
                \\
            , .{
                @"SP--, D=*SP, A=SP-1",
                S.index,
                map.get(cmd.arg1).?,
                @"A=SP-1",
            });
            S.index += 1;
        },
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
            buf = try std.fmt.bufPrint(buffer,
                \\{s}
                \\M=M{c}D
                \\
            , .{
                @"SP--, D=*SP, A=SP-1",
                sign,
            });
        },
        'n' => { // neg, not
            if (std.mem.eql(u8, cmd.arg1, "neg")) {
                sign = '-';
            } else if (std.mem.eql(u8, cmd.arg1, "not")) {
                sign = '!';
            } else {
                unreachable;
            }
            buf = try std.fmt.bufPrint(buffer,
                \\{s}
                \\M={c}M
                \\
            , .{
                @"A=SP-1",
                sign,
            });
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
                \\{s}
                \\
            , .{
                cmd.arg2,
                @"*SP=D, SP++",
            });
        },
        's' => { // static
            if (cmd.type == .C_PUSH) {
                buf = try std.fmt.bufPrint(buffer,
                    \\@{s}.{d}
                    \\D=M
                    \\{s}
                    \\
                , .{
                    basename,
                    cmd.arg2,
                    @"*SP=D, SP++",
                });
            } else {
                buf = try std.fmt.bufPrint(buffer,
                    \\{s}
                    \\@{s}.{d}
                    \\M=D
                    \\
                , .{
                    @"SP--, D=*SP",
                    basename,
                    cmd.arg2,
                });
            }
        },
        'p' => { // pointer
            var p: []const u8 = if (cmd.arg2.? == 0) "THIS" else "THAT";
            if (cmd.type == .C_PUSH) {
                buf = try std.fmt.bufPrint(buffer,
                    \\@{s}
                    \\D=M
                    \\{s}
                    \\
                , .{
                    // 不能这么写，好像只运行一次
                    //if (cmd.arg2.? == 0) "THIS" else "THAT",
                    p,
                    @"*SP=D, SP++",
                });
            } else {
                buf = try std.fmt.bufPrint(buffer,
                    \\{s}
                    \\@{s}
                    \\M=D
                    \\
                , .{
                    @"SP--, D=*SP",
                    p,
                });
            }
        },
        't', 'l', 'a' => {
            if (std.mem.eql(u8, cmd.arg1, "temp")) {
                if (cmd.type == .C_PUSH) {
                    buf = try std.fmt.bufPrint(buffer,
                        \\@{d}
                        \\D=M
                        \\{s}
                        \\
                    , .{
                        5 + cmd.arg2.?,
                        @"*SP=D, SP++",
                    });
                } else {
                    buf = try std.fmt.bufPrint(buffer,
                        \\{s}
                        \\@{d}
                        \\M=D
                        \\
                    , .{
                        @"SP--, D=*SP",
                        5 + cmd.arg2.?,
                    });
                }
            } else { // local, argument, this, that
                if (cmd.type == .C_PUSH) {
                    buf = try std.fmt.bufPrint(buffer,
                        \\@{s}
                        \\D=M
                        \\@{d}
                        \\A=D+A
                        \\D=M
                        \\{s}
                        \\
                    , .{
                        map.get(cmd.arg1).?,
                        cmd.arg2.?,
                        @"*SP=D, SP++",
                    });
                } else {
                    buf = try std.fmt.bufPrint(buffer,
                        \\@{s}
                        \\D=M
                        \\@{d}
                        \\D=D+A
                        \\@R13
                        \\M=D
                        \\{s}
                        \\@R13
                        \\A=M
                        \\M=D
                        \\
                    , .{
                        map.get(cmd.arg1).?,
                        cmd.arg2.?,
                        @"SP--, D=*SP",
                    });
                }
            }
        },
        else => unreachable,
    }

    return buf;
}
