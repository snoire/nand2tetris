const std = @import("std");
const bufPrint = std.fmt.bufPrint;
const BufPrintError = std.fmt.BufPrintError;
const Token = @import("tokenizer.zig").Token;
const TokenType = Token.TokenType;
const KeyWord = Token.KeyWord;

const SymbolTable = @import("symboltable.zig");
const VarKind = SymbolTable.Kind;
const VMWriter = @import("vmwriter.zig");
const Segment = VMWriter.Segment;
const Self = @This();

index: usize = 0,
tokens: []Token,

writer: std.fs.File.Writer,
whitespace: std.json.StringifyOptions.Whitespace = .{
    .indent_level = 1,
    .indent = .{ .Space = 2 },
}, // TODO

className: []const u8 = undefined,
funcNameBuf: [128]u8 = undefined,
funcName: []const u8 = undefined,
labelNameBuf: [64]u8 = undefined,

if_counter: usize = 0,
while_counter: usize = 0,

table: SymbolTable,
vm: VMWriter,

pub fn init(allocator: std.mem.Allocator, tokens: []Token, writer: std.fs.File.Writer) Self {
    return Self{
        .tokens = tokens,
        .writer = writer,
        .table = SymbolTable.init(allocator),
        .vm = VMWriter{ .writer = std.io.getStdOut().writer() },
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
    self.funcName = try bufPrint(&self.funcNameBuf, "{s}.{s}", .{ self.className, self.next().?.lexeme });

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

        while (self.eql(',')) {
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

    self.vm.function(self.funcName, self.table.varCount(.local));
    try self.compile("statements");

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

// inferred error sets are incompatible with recursion, use an explicit error set instead
fn statements(self: *Self) BufPrintError!void {
    while (true) {
        const token = self.tokens[self.index];
        if (token.type != .KEYWORD) break;
        switch (token.keyword.?) {
            .LET => try self.compile("letStatement"),
            .IF => try self.compile("ifStatement"),
            .WHILE => try self.compile("whileStatement"),
            .DO => try self.compile("doStatement"),
            .RETURN => try self.compile("returnStatement"),
            else => break,
        }
    }
}

fn letStatement(self: *Self) BufPrintError!void {
    self.print("{}", .{self.next()}); // LET
    self.print("{}", .{self.tokens[self.index]}); // IDENTIFIER
    var name = self.next().?.lexeme;
    self.print("<!-- {s}: {any} {d} -->", .{ name, self.table.kindOf(name), self.table.indexOf(name) });

    // ('[' expression ']')?
    if (self.eql('[')) {
        self.print("{}", .{self.next()}); // [
        try self.compile("expression");
        self.print("{}", .{self.next()}); // ]
    }

    self.print("{}", .{self.next()}); // =
    try self.compile("expression");
    self.vm.pop(@intToEnum(Segment, @enumToInt(self.table.kindOf(name))), self.table.indexOf(name));
    self.print("{}", .{self.next()}); // ;
}

fn ifStatement(self: *Self) BufPrintError!void {
    const counter = self.if_counter;
    self.if_counter += 1;
    var L1: []const u8 = undefined;
    var L2: []const u8 = undefined;

    self.print("{}", .{self.next()}); // IF
    self.print("{}", .{self.next()}); // (
    try self.compile("expression");
    self.print("{}", .{self.next()}); // }

    self.vm.arithmetic(.not);
    L1 = try bufPrint(&self.labelNameBuf, "IF_FALSE{d}", .{counter});
    self.vm.@"if-goto"(L1);

    self.print("{}", .{self.next()}); // {
    try self.compile("statements");
    self.print("{}", .{self.next()}); // }

    if (self.eql(&[_]KeyWord{.ELSE})) {
        L2 = try bufPrint(&self.labelNameBuf, "IF_END{d}", .{counter});
        self.vm.goto(L2);
    }

    L1 = try bufPrint(&self.labelNameBuf, "IF_FALSE{d}", .{counter});
    self.vm.label(L1);

    if (self.eql(&[_]KeyWord{.ELSE})) {
        self.print("{}", .{self.next()}); // ELSE
        self.print("{}", .{self.next()}); // {
        try self.compile("statements");
        self.print("{}", .{self.next()}); // }

        L2 = try bufPrint(&self.labelNameBuf, "IF_END{d}", .{counter});
        self.vm.label(L2);
    }
}

fn whileStatement(self: *Self) BufPrintError!void {
    const counter = self.while_counter;
    self.while_counter += 1;
    var L1: []const u8 = undefined;
    var L2: []const u8 = undefined;

    self.print("{}", .{self.next()}); // WHILE
    L1 = try bufPrint(&self.labelNameBuf, "WHILE_EXP{d}", .{counter});
    self.vm.label(L1);

    self.print("{}", .{self.next()}); // (
    try self.compile("expression");
    self.print("{}", .{self.next()}); // )

    self.vm.arithmetic(.not);
    L2 = try bufPrint(&self.labelNameBuf, "WHILE_END{d}", .{counter});
    self.vm.@"if-goto"(L2);

    self.print("{}", .{self.next()}); // {
    try self.compile("statements");
    self.print("{}", .{self.next()}); // }
    L1 = try bufPrint(&self.labelNameBuf, "WHILE_EXP{d}", .{counter});
    self.vm.goto(L1);
    L2 = try bufPrint(&self.labelNameBuf, "WHILE_END{d}", .{counter});
    self.vm.label(L2);
}

fn doStatement(self: *Self) BufPrintError!void {
    self.print("{}", .{self.next()}); // DO

    // subroutineCall
    try self.compile("subroutineCall");

    self.print("{}", .{self.next()}); // ;
    self.vm.pop(.temp, 0);
}

fn returnStatement(self: *Self) BufPrintError!void {
    self.print("{}", .{self.next()}); // RETURN
    if (!self.eql(';')) {
        try self.compile("expression");
    } else {
        self.vm.push(.constant, 0);
    }

    self.print("{}", .{self.next()}); // ;
    self.vm.@"return"();
}

fn subroutineCall(self: *Self) BufPrintError!void {
    var nextToken = self.tokens[self.index + 1];
    self.funcName = "";

    if (std.mem.eql(u8, nextToken.lexeme, ".")) {
        self.print("{}", .{self.tokens[self.index]}); // IDENTIFIER
        self.funcName = try bufPrint(&self.funcNameBuf, "{s}.", .{self.next().?.lexeme});
        self.print("{}", .{self.next()}); // .
    }

    self.print("{}", .{self.tokens[self.index]}); // IDENTIFIER
    self.funcName = try bufPrint(&self.funcNameBuf, "{s}{s}", .{ self.funcName, self.next().?.lexeme });
    self.print("{}", .{self.next()}); // (
    const nArgs = try self.compile("expressionList");
    self.print("{}", .{self.next()}); // )
    self.vm.call(self.funcName, nArgs);
}

fn expression(self: *Self) BufPrintError!void {
    try self.compile("term");
    while (self.eql("+-*/&|<>=")) {
        self.print("{}", .{self.tokens[self.index]});
        var op = self.next().?.lexeme[0];
        try self.compile("term");

        switch (op) {
            '+' => self.vm.arithmetic(.add),
            '-' => self.vm.arithmetic(.sub),
            '*' => self.vm.call("Math.multiply", 2),
            '/' => self.vm.call("Math.divide", 2),
            '&' => self.vm.arithmetic(.@"and"),
            '|' => self.vm.arithmetic(.@"or"),
            '<' => self.vm.arithmetic(.lt),
            '>' => self.vm.arithmetic(.gt),
            '=' => self.vm.arithmetic(.eq),
            else => unreachable,
        }
    }
}

fn term(self: *Self) BufPrintError!void {
    var token = self.tokens[self.index];
    switch (token.type) {
        .INT_CONST => {
            self.print("{}", .{self.tokens[self.index]});
            self.vm.push(.constant, self.next().?.number.?);
        },
        .STRING_CONST => self.print("{}", .{self.next()}),
        .KEYWORD => {
            switch (token.keyword.?) {
                // keywordConstant
                .THIS => self.print("{}", .{self.next()}),
                .TRUE, .FALSE, .NULL => |key| {
                    self.print("{}", .{self.next()});
                    self.vm.push(.constant, 0);
                    if (key == .TRUE) {
                        self.vm.arithmetic(.not);
                    }
                },
                else => unreachable,
            }
        },
        .SYMBOL => {
            switch (token.lexeme[0]) {
                // '(' expression ')'
                '(' => {
                    self.print("{}", .{self.next()}); // (
                    try self.compile("expression");
                    self.print("{}", .{self.next()}); // )
                },
                // unaryOP term
                '-', '~' => {
                    var op = self.next().?.lexeme[0];
                    try self.compile("term");
                    if (op == '-') {
                        self.vm.arithmetic(.neg);
                    } else {
                        self.vm.arithmetic(.not);
                    }
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
                    self.print("<!-- {s}: {any} {d} -->", .{ name, self.table.kindOf(name), self.table.indexOf(name) });

                    self.print("{}", .{self.next()}); // [
                    try self.compile("expression");
                    self.print("{}", .{self.next()}); // ]
                },
                // subroutineCall
                '.', '(' => {
                    try self.compile("subroutineCall");
                },
                // varName
                else => {
                    self.print("{}", .{self.tokens[self.index]}); // varName
                    var name = self.next().?.lexeme;
                    self.print("<!-- {s}: {any} {d} -->", .{ name, self.table.kindOf(name), self.table.indexOf(name) });
                    self.vm.push(@intToEnum(Segment, @enumToInt(self.table.kindOf(name))), self.table.indexOf(name));
                },
            }
        },
    }
}

fn expressionList(self: *Self) BufPrintError!usize {
    var number: usize = if (self.eql(')')) 0 else blk: {
        try self.compile("expression");
        var i: usize = 1;
        while (self.eql(',')) : (i += 1) {
            self.print("{}", .{self.next()});
            try self.compile("expression");
        }
        break :blk i;
    };

    return number;
}
