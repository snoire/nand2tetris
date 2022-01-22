const std = @import("std");
const Token = @import("tokenizer.zig").Token;
const TokenType = Token.TokenType;
const KeyWord = Token.KeyWord;

const SymbolTable = @import("symboltable.zig");
const VarKind = SymbolTable.Kind;
const Self = @This();

index: usize = 0,
tokens: []Token,

writer: std.fs.File.Writer,
whitespace: std.json.StringifyOptions.Whitespace = .{
    .indent_level = 1,
    .indent = .{ .Space = 2 },
}, // TODO

className: []const u8,
table: SymbolTable,

pub fn init(allocator: std.mem.Allocator, tokens: []Token, writer: std.fs.File.Writer) Self {
    return Self{
        .tokens = tokens,
        .writer = writer,
        .className = undefined,
        .table = SymbolTable.init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.table.deinit();
}


// print one line with indent
fn print(self: *Self, comptime format: []const u8, args: anytype) void {
    self.writer.writeAll("\r\n") catch unreachable;
    self.whitespace.outputIndent(self.writer) catch unreachable;
    std.fmt.format(self.writer, format, args) catch unreachable;
}

fn writeAll(self: *Self, bytes: []const u8) void {
    self.writer.writeAll(bytes) catch unreachable;
}

fn eql(self: *Self, expect: anytype) bool {
    var token = self.tokens[self.index];

    switch (@TypeOf(expect)) {
        comptime_int => { // a single character symbol
            if (token.type == .SYMBOL and token.lexeme[0] == expect)
                return true;
        },
        else => |expect_type| {
            comptime std.debug.assert(@typeInfo(expect_type) == .Pointer);
            const p = @typeInfo(expect_type).Pointer;

            comptime std.debug.assert(p.is_const and @typeInfo(p.child) == .Array);
            const arr = @typeInfo(p.child).Array;

            switch (arr.child) {
                u8 => { // symbol lists: string literal
                    if (token.type == .SYMBOL and std.mem.indexOfScalar(u8, expect, token.lexeme[0]) != null)
                        return true;
                },
                KeyWord => { // keyword list
                    if (token.type == .KEYWORD and std.mem.indexOfScalar(KeyWord, expect, token.keyword.?) != null)
                        return true;
                },
                else => @compileError("Unsupported type: " ++ @typeName(expect_type)),
            }
        },
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
pub fn compileClass(self: *Self) !void {
    self.writeAll("<class>");

    self.print("{}", .{self.next()}); // CLASS
    self.print("{}", .{self.tokens[self.index]}); // IDENTIFIER
    self.className = self.next().?.lexeme;
    self.print("{}", .{self.next()}); // {

    while (self.eql(&[_]KeyWord{ .STATIC, .FIELD })) {
        try self.compile("classVarDec");
    }

    while (self.eql(&[_]KeyWord{ .CONSTRUCTOR, .FUNCTION, .METHOD })) {
        try self.compile("subroutineDec");
    }

    self.print("{}", .{self.next()}); // }
    self.writeAll("\r\n</class>\r\n");
}

fn classVarDec(self: *Self) !void {
    self.print("{}", .{self.tokens[self.index]}); // "static", "field"
    const kind: VarKind = if (self.next().?.keyword.? == .STATIC) .static else .field;

    self.print("{}", .{self.tokens[self.index]}); // type
    const varType = self.next().?.lexeme;

    self.print("{}", .{self.tokens[self.index]}); // IDENTIFIER
    var name = self.next().?.lexeme;

    try self.table.define(name, varType, kind);

    while (self.eql(',')) {
        self.print("{}", .{self.next()}); // ,
        self.print("{}", .{self.tokens[self.index]}); // IDENTIFIER
        name = self.next().?.lexeme;
        try self.table.define(name, varType, kind);
    }

    self.print("{}", .{self.next()}); // ;
}

fn subroutineDec(self: *Self) !void {
    self.table.reset();

    self.print("{}", .{self.tokens[self.index]}); // "constructor", "function", "method"
    const subroutineType = self.next().?.keyword.?;
    if (subroutineType == .METHOD) {
        try self.table.define("this", self.className, .argument);
    }
    self.print("{}", .{self.next()}); // 'void' | type
    self.print("{}", .{self.tokens[self.index]}); // IDENTIFIER
    _ = self.next().?.lexeme;

    self.print("{}", .{self.next()}); // (
    try self.compile("parameterList");
    self.print("{}", .{self.next()}); // )

    try self.compile("subroutineBody");
}

fn parameterList(self: *Self) !void {
    if (!self.eql(')')) {
        self.print("{}", .{self.tokens[self.index]}); // type
        var varType = self.next().?.lexeme;

        self.print("{}", .{self.tokens[self.index]}); // IDENTIFIER
        var name = self.next().?.lexeme;

        try self.table.define(name, varType, .argument);

        var i: usize = 1;
        while (self.eql(',')) : (i += 1) {
            self.print("{}", .{self.next()}); // ,
            self.print("{}", .{self.tokens[self.index]}); // type
            varType = self.next().?.lexeme;

            self.print("{}", .{self.tokens[self.index]}); // IDENTIFIER
            name = self.next().?.lexeme;
            try self.table.define(name, varType, .argument);
        }
    }
}

fn subroutineBody(self: *Self) !void {
    self.print("{}", .{self.next()}); // {

    while (self.eql(&[_]KeyWord{.VAR})) {
        try self.compile("varDec");
    }

    self.compile("statements");

    self.print("{}", .{self.next()}); // }
}

fn varDec(self: *Self) !void {
    self.print("{}", .{self.next()}); // var
    self.print("{}", .{self.tokens[self.index]}); // type
    const varType = self.next().?.lexeme;

    self.print("{}", .{self.tokens[self.index]}); // IDENTIFIER
    var name = self.next().?.lexeme;
    try self.table.define(name, varType, .local);

    while (self.eql(',')) {
        self.print("{}", .{self.next()}); // ,
        self.print("{}", .{self.tokens[self.index]}); // IDENTIFIER
        name = self.next().?.lexeme;
        try self.table.define(name, varType, .local);
    }

    self.print("{}", .{self.next()}); // ;
}

fn statements(self: *Self) void {
    while (true) {
        const token = self.tokens[self.index];
        if (token.type != .KEYWORD) break;
        switch (token.keyword.?) {
            .LET => self.compile("letStatement"),
            .IF => self.compile("ifStatement"),
            .WHILE => self.compile("whileStatement"),
            .DO => self.compile("doStatement"),
            .RETURN => self.compile("returnStatement"),
            else => break,
        }
    }
}

fn letStatement(self: *Self) void {
    self.print("{}", .{self.next()}); // LET
    self.print("{}", .{self.tokens[self.index]}); // IDENTIFIER
    var name = self.next().?.lexeme;
    self.print("<!-- {s}: {any} {d} -->", .{name, self.table.kindOf(name), self.table.indexOf(name)});

    // ('[' expression ']')?
    if (self.eql('[')) {
        self.print("{}", .{self.next()}); // [
        self.compile("expression");
        self.print("{}", .{self.next()}); // ]
    }

    self.print("{}", .{self.next()}); // =
    self.compile("expression");
    self.print("{}", .{self.next()}); // ;
}

fn ifStatement(self: *Self) void {
    self.print("{}", .{self.next()}); // IF
    self.print("{}", .{self.next()}); // (
    self.compile("expression");
    self.print("{}", .{self.next()}); // }

    self.print("{}", .{self.next()}); // {
    self.compile("statements");
    self.print("{}", .{self.next()}); // }

    if (self.eql(&[_]KeyWord{.ELSE})) {
        self.print("{}", .{self.next()}); // ELSE
        self.print("{}", .{self.next()}); // {
        self.compile("statements");
        self.print("{}", .{self.next()}); // }
    }
}

fn whileStatement(self: *Self) void {
    self.print("{}", .{self.next()}); // WHILE
    self.print("{}", .{self.next()}); // (
    self.compile("expression");
    self.print("{}", .{self.next()}); // )

    self.print("{}", .{self.next()}); // {
    self.compile("statements");
    self.print("{}", .{self.next()}); // }
}

fn doStatement(self: *Self) void {
    self.print("{}", .{self.next()}); // DO

    // subroutineCall
    var nextToken = self.tokens[self.index + 1];
    if (std.mem.eql(u8, nextToken.lexeme, ".")) {
        self.print("{}", .{self.next()}); // IDENTIFIER
        self.print("{}", .{self.next()}); // .
    }
    self.print("{}", .{self.next()}); // IDENTIFIER
    self.print("{}", .{self.next()}); // (
    _ = self.compile("expressionList");
    self.print("{}", .{self.next()}); // )

    self.print("{}", .{self.next()}); // ;
}

fn returnStatement(self: *Self) void {
    self.print("{}", .{self.next()}); // RETURN
    if (!self.eql(';')) {
        self.compile("expression");
    }

    self.print("{}", .{self.next()}); // ;
}

fn expression(self: *Self) void {
    self.compile("term");
    while (self.eql("+-*/&|<>=")) {
        self.print("{}", .{self.next()}); // op
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
                    self.print("{}", .{self.next()}); // (
                    self.compile("expression");
                    self.print("{}", .{self.next()}); // )
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
                    self.print("{}", .{self.tokens[self.index]}); // varName
                    var name = self.next().?.lexeme;
                    self.print("<!-- {s}: {any} {d} -->", .{name, self.table.kindOf(name), self.table.indexOf(name)});

                    self.print("{}", .{self.next()}); // [
                    self.compile("expression");
                    self.print("{}", .{self.next()}); // ]
                },
                // subroutineCall
                '.', '(' => {
                    if (std.mem.eql(u8, nextToken.lexeme, ".")) {
                        self.print("{}", .{self.next()}); // className | varName
                        self.print("{}", .{self.next()}); // .
                    }
                    self.print("{}", .{self.next()}); // IDENTIFIER
                    self.print("{}", .{self.next()}); // (
                    _ = self.compile("expressionList");
                    self.print("{}", .{self.next()}); // )
                },
                // varName
                else => {
                    self.print("{}", .{self.tokens[self.index]}); // varName
                    var name = self.next().?.lexeme;
                    self.print("<!-- {s}: {any} {d} -->", .{name, self.table.kindOf(name), self.table.indexOf(name)});
                },
            }
        },
    }
}

fn expressionList(self: *Self) usize {
    var number: usize = if (self.eql(')')) 0 else blk: {
        self.compile("expression");
        var i: usize = 1;
        while (self.eql(',')) : (i += 1) {
            self.print("{}", .{self.next()});
            self.compile("expression");
        }
        break :blk i;
    };

    return number;
}
