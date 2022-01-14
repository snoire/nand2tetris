const std = @import("std");
const Token = @import("tokenizer.zig").Token;
const Self = @This();

index: usize = 0,
tokens: []Token,
writer: std.fs.File.Writer,
whitespace: std.json.StringifyOptions.Whitespace = std.json.StringifyOptions.Whitespace{
    .indent_level = 1,
    .indent = .{ .Space = 2 },
},

// print one line with indent
fn print(self: *Self, comptime format: []const u8, args: anytype) void {
    self.writer.writeByte('\n') catch unreachable;
    self.whitespace.outputIndent(self.writer) catch unreachable;
    std.fmt.format(self.writer, format, args) catch unreachable;
}

fn writeAll(self: *Self, bytes: []const u8) void {
    self.writer.writeAll(bytes) catch unreachable;
}

fn eql(self: *Self, slices: []const []const u8) bool {
    for (slices) |slice| {
        if (std.mem.eql(u8, slice, self.tokens[self.index].lexeme)) {
            return true;
        }
    }
    return false;
}

fn next(self: *Self) ?Token {
    const i = self.index;
    if (i < self.tokens.len) {
        self.index += 1;
        return self.tokens[i];
    }
    return null;
}

// TODO
//fn get(self: *Self, lexemes: []const []const u8) Token {
//}

// wrapper of "func"
fn compile(self: *Self, comptime func: []const u8) if (@typeInfo(@TypeOf(@field(Self, func))).Fn.return_type) |return_type| return_type else void {
    self.print("<{s}>", .{func});
    self.whitespace.indent_level += 1;

    // call func
    const return_type = if (@typeInfo(@TypeOf(@field(Self, func))).Fn.return_type) |return_type| return_type else void;
    const result: return_type = @field(Self, func)(self);

    self.whitespace.indent_level -= 1;
    self.print("</{s}>", .{func});

    return result;
}

// compiles a complete class
pub fn compileClass(self: *Self) void {
    self.writeAll("<class>");

    self.print("{}", .{self.next()});
    self.print("{}", .{self.next()});
    self.print("{}", .{self.next()});

    while (self.eql(&[_][]const u8{ "static", "field" })) {
        self.compile("classVarDec");
    }

    while (self.eql(&[_][]const u8{ "constructor", "function", "method" })) {
        self.compile("subroutineDec");
    }

    self.print("{}", .{self.next()});
    self.writeAll("\n</class>\n");
}

fn classVarDec(self: *Self) void {
    self.print("{}", .{self.next()});
    self.print("{}", .{self.next()});
    self.print("{}", .{self.next()});

    while (self.eql(&[_][]const u8{","})) {
        self.print("{}", .{self.next()});
        self.print("{}", .{self.next()});
    }
    self.print("{}", .{self.next()});
}

fn subroutineDec(self: *Self) void {
    self.print("{}", .{self.next()});
    self.print("{}", .{self.next()});
    self.print("{}", .{self.next()});
    self.print("{}", .{self.next()});

    self.compile("parameterList");
    self.print("{}", .{self.next()});
    self.compile("subroutineBody");
}

fn parameterList(self: *Self) void {
    _ = self;
}

fn subroutineBody(self: *Self) void {
    self.print("{}", .{self.next()});

    while (self.eql(&[_][]const u8{"var"})) {
        self.compile("varDec");
    }

    self.compile("statements");

    self.print("{}", .{self.next()});
}

fn varDec(self: *Self) void {
    self.print("{}", .{self.next()});
    self.print("{}", .{self.next()});
    self.print("{}", .{self.next()});

    while (self.eql(&[_][]const u8{","})) {
        self.print("{}", .{self.next()});
        self.print("{}", .{self.next()});
    }

    self.print("{}", .{self.next()});
}

fn statements(self: *Self) void {
    while (true) {
        if (self.eql(&[_][]const u8{"let"})) {
            self.compile("letStatement");
        } else if (self.eql(&[_][]const u8{"if"})) {
            self.compile("ifStatement");
        } else if (self.eql(&[_][]const u8{"while"})) {
            self.compile("whileStatement");
        } else if (self.eql(&[_][]const u8{"do"})) {
            self.compile("doStatement");
        } else if (self.eql(&[_][]const u8{"return"})) {
            self.compile("returnStatement");
        } else {
            break;
        }
    }
}

fn letStatement(self: *Self) void {
    self.print("{}", .{self.next()});
    self.print("{}", .{self.next()});

    // ('[' expression ']')?
    if (self.eql(&[_][]const u8{"["})) {
        self.print("{}", .{self.next()});
        self.compile("expression");
        self.print("{}", .{self.next()});
    }

    self.print("{}", .{self.next()});
    self.compile("expression");
    self.print("{}", .{self.next()});
}

fn ifStatement(self: *Self) void {
    self.print("{}", .{self.next()});
    self.print("{}", .{self.next()});
    self.compile("expression");
    self.print("{}", .{self.next()});

    self.print("{}", .{self.next()});
    self.compile("statements");
    self.print("{}", .{self.next()});

    if (self.eql(&[_][]const u8{"else"})) {
        self.print("{}", .{self.next()});
        self.print("{}", .{self.next()});
        self.compile("statements");
        self.print("{}", .{self.next()});
    }
}

fn whileStatement(self: *Self) void {
    _ = self;
}

fn doStatement(self: *Self) void {
    self.print("{}", .{self.next()});

    // subroutineCall
    var nextToken = self.tokens[self.index + 1];
    if (std.mem.eql(u8, nextToken.lexeme, ".")) {
        self.print("{}", .{self.next()});
        self.print("{}", .{self.next()});
    }
    self.print("{}", .{self.next()});
    self.print("{}", .{self.next()});
    _ = self.compile("expressionList");
    self.print("{}", .{self.next()});

    self.print("{}", .{self.next()});
}

fn returnStatement(self: *Self) void {
    self.print("{}", .{self.next()});
    if (!self.eql(&[_][]const u8{";"})) {
        self.compile("expression");
    }

    self.print("{}", .{self.next()});
}

fn expression(self: *Self) void {
    self.compile("term");
    while (self.eql(&[_][]const u8{ "+", "-", "*", "/", "&", "|", "<", ">", "=" })) {
        self.print("{}", .{self.next()});
        self.compile("term");
    }
}

fn term(self: *Self) void {
    var token = self.tokens[self.index];
    switch (token.type) {
        .INT_CONST => self.print("{}", .{self.next()}),
        .STRING_CONST => self.print("{}", .{self.next()}),
        .KEYWORD => {
            switch (token.keyword.?) {
                // keywordConstant
                .TRUE, .FALSE, .NULL, .THIS => self.print("{}", .{self.next()}),
                else => unreachable,
            }
        },
        .SYMBOL => {
            switch (token.lexeme[0]) {
                // '(' expression ')'
                '(' => {
                    self.print("{}", .{self.next()});
                    self.compile("expression");
                    self.print("{}", .{self.next()});
                },
                // unaryOP term
                '-', '~' => {
                    self.print("{}", .{self.next()});
                    self.compile("term");
                },
                else => unreachable,
            }
        },
        .IDENTIFIER => {
            var nextToken = self.tokens[self.index + 1];
            switch (nextToken.lexeme[0]) {
                // varName '[' expression ']'
                '[' => {
                    self.print("{}", .{self.next()});
                    self.print("{}", .{self.next()});
                    self.compile("expression");
                    self.print("{}", .{self.next()});
                },
                // subroutineCall
                '.', '(' => {
                    if (std.mem.eql(u8, nextToken.lexeme, ".")) {
                        self.print("{}", .{self.next()});
                        self.print("{}", .{self.next()});
                    }
                    self.print("{}", .{self.next()});
                    self.print("{}", .{self.next()});
                    _ = self.compile("expressionList");
                    self.print("{}", .{self.next()});
                },
                // varName
                else => self.print("{}", .{self.next()}),
            }
        },
    }
}

fn expressionList(self: *Self) usize {
    var number: usize = if (self.eql(&[_][]const u8{")"})) 0 else blk: {
        self.compile("expression");
        var i: usize = 1;
        while (self.eql(&[_][]const u8{","})) : (i += 1) {
            self.compile("expression");
        }
        break :blk i;
    };

    return number;
}
