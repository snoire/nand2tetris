const std = @import("std");
const Allocator = std.mem.Allocator;
const Writer = std.fs.File.Writer;
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
var writer: Writer = undefined;

var fileNameBuf: [std.os.NAME_MAX]u8 = undefined;
var fileName: []u8 = undefined;
var labelPrefix: []const u8 = undefined; // "file.func" or "file" if func is null

pub fn init(allocator: Allocator, wt: Writer) !void {
    writer = wt;

    map = std.StringHashMap([]const u8).init(allocator);
    const kvpair = .{
        .{ "local", "LCL" },
        .{ "argument", "ARG" },
        .{ "this", "THIS" },
        .{ "that", "THAT" },
    };

    inline for (kvpair) |pair| {
        try map.put(pair.@"0", pair.@"1");
    }

    // write bootstrap code
    // SP=256
    try writer.print(
        \\@256
        \\D=A
        \\@SP
        \\M=D
        \\
    , .{});

    // call Sys.init
    try call(.{ .type = .C_CALL, .arg1 = "Sys.init", .arg2 = 0 });
}

pub fn deinit() void {
    map.deinit();
}

pub fn setFileName(file: []const u8) !void {
    fileName = try std.fmt.bufPrint(&fileNameBuf, "{s}", .{file});
    labelPrefix = fileName;
}

pub fn arithmetic(cmd: Command) !void {
    const S = struct {
        var index: usize = 0; // static local variable
    };

    var sign: u8 = undefined;
    switch (cmd.arg1[0]) {
        'e', 'g', 'l' => { // eq, gt, lt
            var output: [2]u8 = undefined;
            // 生成的 label 前加 '$'，防止和 vm 中的 label 冲突
            try writer.print(
                \\{0s}
                \\D=M-D
                \\@${1s}_TRUE{2d}
                \\D;J{1s}
                \\{3s}
                \\M=0
                \\@${1s}_END{2d}
                \\0;JMP
                \\(${1s}_TRUE{2d})
                \\{3s}
                \\M=-1
                \\(${1s}_END{2d})
                \\
            , .{
                @"SP--, D=*SP, A=SP-1",
                std.ascii.upperString(&output, cmd.arg1),
                S.index,
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

            try writer.print(
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

            try writer.print(
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
}

pub fn pushpop(cmd: Command) !void {
    switch (cmd.arg1[0]) {
        'c' => { // constant
            try writer.print(
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
                try writer.print(
                    \\@{s}.{d}
                    \\D=M
                    \\{s}
                    \\
                , .{
                    fileName,
                    cmd.arg2,
                    @"*SP=D, SP++",
                });
            } else {
                try writer.print(
                    \\{s}
                    \\@{s}.{d}
                    \\M=D
                    \\
                , .{
                    @"SP--, D=*SP",
                    fileName,
                    cmd.arg2,
                });
            }
        },
        'p' => { // pointer
            var p: []const u8 = if (cmd.arg2.? == 0) "THIS" else "THAT";
            if (cmd.type == .C_PUSH) {
                try writer.print(
                    \\@{s}
                    \\D=M
                    \\{s}
                    \\
                , .{
                    // 不能这么写，好像只运行一次
                    // 已知 bug：https://github.com/ziglang/zig/issues/5230
                    //if (cmd.arg2.? == 0) "THIS" else "THAT",
                    p,
                    @"*SP=D, SP++",
                });
            } else {
                try writer.print(
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
                    try writer.print(
                        \\@{d}
                        \\D=M
                        \\{s}
                        \\
                    , .{
                        5 + cmd.arg2.?,
                        @"*SP=D, SP++",
                    });
                } else {
                    try writer.print(
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
                    try writer.print(
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
                    try writer.print(
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
}

pub fn label(cmd: Command) !void {
    try writer.print(
        \\({s}${s})
        \\
    , .{ labelPrefix, cmd.arg1 });
}

pub fn goto(cmd: Command) !void {
    try writer.print(
        \\@{s}${s}
        \\0;JMP
        \\
    , .{ labelPrefix, cmd.arg1 });
}

pub fn if_goto(cmd: Command) !void {
    try writer.print(
        \\{s}
        \\@{s}${s}
        \\D;JNE
        \\
    , .{
        @"SP--, D=*SP",
        labelPrefix,
        cmd.arg1,
    });
}

pub fn call(cmd: Command) !void {
    const S = struct {
        var index: usize = 0; // static local variable
    };

    // push returnAddress
    try writer.print(
        \\@RA_CALL_{s}{d}
        \\D=A
        \\{s}
        \\
    , .{
        cmd.arg1,
        S.index,
        @"*SP=D, SP++",
    });

    // push LCL, ARG, THIS, THAT
    const symbols = [_][]const u8{ "LCL", "ARG", "THIS", "THAT" };
    inline for (symbols) |symbol| {
        try writer.print(
            \\@{s}
            \\D=M
            \\{s}
            \\
        , .{
            symbol,
            @"*SP=D, SP++",
        });
    }

    // LCL=SP, ARG=SP-5-nArgs, goto f
    try writer.print(
        \\@SP
        \\D=M
        \\@LCL
        \\M=D
        \\@5
        \\D=D-A
        \\@{0d}
        \\D=D-A
        \\@ARG
        \\M=D
        \\@{1s}
        \\0;JMP
        \\(RA_CALL_{1s}{2d})
        \\
    , .{
        cmd.arg2.?,
        cmd.arg1,
        S.index,
    });

    S.index += 1;
}

pub fn function(cmd: Command) !void {
    var nVars: usize = cmd.arg2.?;
    const S = struct {
        var index: usize = 0; // static local variable
    };

    try writer.print("({s})\n", .{cmd.arg1});
    if (nVars == 0) return;

    // 多于一个参数，就循环执行
    if (nVars > 1) {
        try writer.print(
            \\@{d}
            \\D=A
            \\@R14
            \\M=D
            \\($INIT_LCLVAR{d})
            \\
        , .{
            cmd.arg2.?,
            S.index,
        });
    }

    // 当前的 SP 指向 LCL，所以 push constant 0 相当于清空 local 段
    try pushpop(.{ .type = .C_PUSH, .arg1 = "constant", .arg2 = 0 });

    if (nVars > 1) {
        // 书上写 DM 可以作为 dest，但是 cpu Emulator 只认 MD 。。
        try writer.print(
            \\@R14
            \\MD=M-1
            \\@$INIT_LCLVAR{d}
            \\D;JGT
            \\
        , .{S.index});
    }

    S.index += 1;
    labelPrefix = cmd.arg1;
}

pub fn @"return"() !void {
    // 0 个参数时, ARG 和 Return IP 是同一个，retAddr 会被覆盖，所以要先存起来
    // R15=LCL, R14=*(LCL-5)
    try writer.print(
        \\@LCL
        \\D=M
        \\@R15
        \\M=D
        \\@5
        \\A=D-A
        \\D=M
        \\@R14
        \\M=D
        \\
    , .{});

    // *ARG=pop(), SP=ARG+1
    try writer.print(
        \\{s}
        \\@ARG
        \\A=M
        \\M=D
        \\@ARG
        \\D=M+1
        \\@SP
        \\M=D
        \\
    , .{@"SP--, D=*SP"});

    // symbol = *(R15--)
    const symbols = [_][]const u8{ "THAT", "THIS", "ARG", "LCL" };
    inline for (symbols) |symbol| {
        try writer.print(
            \\@R15
            \\AM=M-1
            \\D=M
            \\@{s}
            \\M=D
            \\
        , .{symbol});
    }

    // goto *R14
    try writer.print(
        \\@R14
        \\A=M
        \\0;JMP
        \\
    , .{});

    labelPrefix = fileName;
}
