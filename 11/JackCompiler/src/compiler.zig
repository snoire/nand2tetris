const std = @import("std");
const bufPrint = std.fmt.bufPrint;
const BufPrintError = std.fmt.BufPrintError;
const Self = @This();

const Token = @import("tokenizer.zig").Token;
const TokenType = Token.TokenType;
const KeyWord = Token.KeyWord;

const SymbolTable = @import("symboltable.zig");
const VarKind = SymbolTable.Kind;
const VMWriter = @import("vmwriter.zig");
const Segment = VMWriter.Segment;

index: usize = 0,
if_counter: usize = 0,
while_counter: usize = 0,

className: []const u8 = undefined,
funcNameBuf: [128]u8 = undefined,
funcName: []const u8 = undefined,
subroutineType: KeyWord = undefined,

tokens: []Token,
table: SymbolTable,
vm: VMWriter,

pub fn init(allocator: std.mem.Allocator, tokens: []Token, writer: std.fs.File.Writer) Self {
    return Self{
        .tokens = tokens,
        .table = SymbolTable.init(allocator),
        .vm = VMWriter{ .writer = writer },
    };
}

pub fn deinit(self: *Self) void {
    self.table.deinit();
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

// compiles a complete class
pub fn compileClass(self: *Self) !void {
    _ = self.next(); // CLASS
    self.className = self.next().?.lexeme;

    _ = self.next(); // {

    while (self.eql(&[_]KeyWord{ .STATIC, .FIELD })) {
        try self.classVarDec();
    }

    while (self.eql(&[_]KeyWord{ .CONSTRUCTOR, .FUNCTION, .METHOD })) {
        try self.subroutineDec();
    }

    _ = self.next(); // }
}

fn classVarDec(self: *Self) !void {
    const kind: VarKind = if (self.next().?.keyword.? == .STATIC) .static else .field;
    const varType = self.next().?.lexeme;
    var name = self.next().?.lexeme;
    try self.table.define(name, varType, kind);

    while (self.eql(',')) {
        _ = self.next(); // ,
        name = self.next().?.lexeme;
        try self.table.define(name, varType, kind);
    }

    _ = self.next(); // ;
}

fn subroutineDec(self: *Self) !void {
    self.table.reset();

    self.subroutineType = self.next().?.keyword.?; // "constructor", "function", "method"
    if (self.subroutineType == .METHOD) {
        try self.table.define("this", self.className, .argument);
    }
    _ = self.next(); // 'void' | type
    self.funcName = try bufPrint(&self.funcNameBuf, "{s}.{s}", .{ self.className, self.next().?.lexeme });

    _ = self.next(); // (
    try self.parameterList();
    _ = self.next(); // )

    try self.subroutineBody();
}

fn parameterList(self: *Self) !void {
    if (!self.eql(')')) {
        var varType = self.next().?.lexeme;
        var name = self.next().?.lexeme;
        try self.table.define(name, varType, .argument);

        while (self.eql(',')) {
            _ = self.next(); // ,
            varType = self.next().?.lexeme;
            name = self.next().?.lexeme;
            try self.table.define(name, varType, .argument);
        }
    }
}

fn subroutineBody(self: *Self) !void {
    _ = self.next(); // {

    while (self.eql(&[_]KeyWord{.VAR})) {
        try self.varDec();
    }

    self.vm.function(self.funcName, self.table.varCount(.local));

    switch (self.subroutineType) {
        .CONSTRUCTOR => {
            self.vm.push(.constant, self.table.varCount(.field));
            self.vm.call("Memory.alloc", 1);
            self.vm.pop(.pointer, 0);
        },
        .METHOD => {
            self.vm.push(.argument, 0);
            self.vm.pop(.pointer, 0);
        },
        .FUNCTION => {},
        else => unreachable,
    }

    try self.statements();
    _ = self.next(); // }
}

fn varDec(self: *Self) !void {
    _ = self.next(); // var
    const varType = self.next().?.lexeme;
    var name = self.next().?.lexeme;
    try self.table.define(name, varType, .local);

    while (self.eql(',')) {
        _ = self.next(); // ,
        name = self.next().?.lexeme;
        try self.table.define(name, varType, .local);
    }

    _ = self.next(); // ;
}

// inferred error sets are incompatible with recursion, use an explicit error set instead
fn statements(self: *Self) BufPrintError!void {
    while (true) {
        const token = self.tokens[self.index];
        if (token.type != .KEYWORD) break;
        switch (token.keyword.?) {
            .LET => try self.letStatement(),
            .IF => try self.ifStatement(),
            .WHILE => try self.whileStatement(),
            .DO => try self.doStatement(),
            .RETURN => try self.returnStatement(),
            else => break,
        }
    }
}

fn letStatement(self: *Self) BufPrintError!void {
    _ = self.next(); // LET
    const name = self.next().?.lexeme;

    // ('[' expression ']')?
    var is_array: bool = false;
    if (self.eql('[')) {
        is_array = true;
        self.vm.push(@intToEnum(Segment, @enumToInt(self.table.kindOf(name).?)), self.table.indexOf(name));
        _ = self.next(); // [
        try self.expression();
        _ = self.next(); // ]
        self.vm.arithmetic(.add);
    }

    _ = self.next(); // =
    try self.expression();
    _ = self.next(); // ;

    if (is_array) {
        self.vm.pop(.temp, 0);
        self.vm.pop(.pointer, 1);
        self.vm.push(.temp, 0);
        self.vm.pop(.that, 0);
    } else {
        self.vm.pop(@intToEnum(Segment, @enumToInt(self.table.kindOf(name).?)), self.table.indexOf(name));
    }
}

fn ifStatement(self: *Self) BufPrintError!void {
    var buf1: [64]u8 = undefined;
    var buf2: [64]u8 = undefined;
    const L1 = try bufPrint(&buf1, "IF_FALSE{d}", .{self.if_counter});
    const L2 = try bufPrint(&buf2, "IF_END{d}", .{self.if_counter});

    self.if_counter += 1;

    _ = self.next(); // IF
    _ = self.next(); // (
    try self.expression();
    _ = self.next(); // }

    self.vm.arithmetic(.not);
    self.vm.@"if-goto"(L1);

    _ = self.next(); // {
    try self.statements();
    _ = self.next(); // }

    if (self.eql(&[_]KeyWord{.ELSE})) {
        self.vm.goto(L2);
    }

    self.vm.label(L1);

    if (self.eql(&[_]KeyWord{.ELSE})) {
        _ = self.next(); // ELSE
        _ = self.next(); // {
        try self.statements();
        _ = self.next(); // }

        self.vm.label(L2);
    }
}

fn whileStatement(self: *Self) BufPrintError!void {
    var buf1: [64]u8 = undefined;
    var buf2: [64]u8 = undefined;
    const L1 = try bufPrint(&buf1, "WHILE_EXP{d}", .{self.while_counter});
    const L2 = try bufPrint(&buf2, "WHILE_END{d}", .{self.while_counter});

    self.while_counter += 1;

    _ = self.next(); // WHILE
    self.vm.label(L1);

    _ = self.next(); // (
    try self.expression();
    _ = self.next(); // )

    self.vm.arithmetic(.not);
    self.vm.@"if-goto"(L2);

    _ = self.next(); // {
    try self.statements();
    _ = self.next(); // }
    self.vm.goto(L1);
    self.vm.label(L2);
}

fn doStatement(self: *Self) BufPrintError!void {
    _ = self.next(); // DO

    try self.subroutineCall();

    _ = self.next(); // ;
    self.vm.pop(.temp, 0);
}

fn returnStatement(self: *Self) BufPrintError!void {
    _ = self.next(); // RETURN

    if (!self.eql(';')) {
        try self.expression();
    } else {
        self.vm.push(.constant, 0);
    }

    _ = self.next(); // ;
    self.vm.@"return"();
}

fn subroutineCall(self: *Self) BufPrintError!void {
    var nArgs: usize = 0;
    const nextToken = self.tokens[self.index + 1];

    const className = if (std.mem.eql(u8, nextToken.lexeme, ".")) blk1: {
        const name = self.next().?.lexeme;
        const classname = if (self.table.kindOf(name)) |var_kind| blk2: {
            self.vm.push(@intToEnum(Segment, @enumToInt(var_kind)), self.table.indexOf(name));
            nArgs += 1;
            break :blk2 self.table.typeOf(name);
        } else name;
        _ = self.next(); // .
        break :blk1 classname;
    } else blk: {
        self.vm.push(.pointer, 0);
        nArgs += 1;
        break :blk self.className;
    };

    var funcNameBuf: [128]u8 = undefined;
    const funcName = try bufPrint(&funcNameBuf, "{s}.{s}", .{ className, self.next().?.lexeme });
    _ = self.next(); // (
    nArgs += try self.expressionList();
    _ = self.next(); // )
    self.vm.call(funcName, nArgs);
}

fn expression(self: *Self) BufPrintError!void {
    try self.term();
    while (self.eql("+-*/&|<>=")) {
        var op = self.next().?.lexeme[0];
        try self.term();

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
        .INT_CONST => self.vm.push(.constant, self.next().?.number.?),
        .STRING_CONST => {
            const str = self.next().?.lexeme;
            self.vm.push(.constant, str.len);
            self.vm.call("String.new", 1);

            for (str) |char| {
                self.vm.push(.constant, char);
                self.vm.call("String.appendChar", 2);
            }
        },
        .KEYWORD => {
            switch (token.keyword.?) {
                // keywordConstant
                .THIS => {
                    _ = self.next();
                    self.vm.push(.pointer, 0);
                },
                .TRUE, .FALSE, .NULL => |key| {
                    _ = self.next();
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
                    _ = self.next(); // (
                    try self.expression();
                    _ = self.next(); // )
                },
                // unaryOP term
                '-', '~' => {
                    var op = self.next().?.lexeme[0];
                    try self.term();
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
            const nextToken = self.tokens[self.index + 1];
            switch (nextToken.lexeme[0]) {
                // varName '[' expression ']'
                '[' => {
                    const name = self.next().?.lexeme;
                    self.vm.push(@intToEnum(Segment, @enumToInt(self.table.kindOf(name).?)), self.table.indexOf(name));

                    _ = self.next(); // [
                    try self.expression();
                    _ = self.next(); // ]

                    self.vm.arithmetic(.add);
                    self.vm.pop(.pointer, 1);
                    self.vm.push(.that, 0);
                },
                // subroutineCall
                '.', '(' => {
                    try self.subroutineCall();
                },
                // varName
                else => {
                    const name = self.next().?.lexeme;
                    self.vm.push(@intToEnum(Segment, @enumToInt(self.table.kindOf(name).?)), self.table.indexOf(name));
                },
            }
        },
    }
}

fn expressionList(self: *Self) BufPrintError!usize {
    var number: usize = if (self.eql(')')) 0 else blk: {
        try self.expression();
        var i: usize = 1;
        while (self.eql(',')) : (i += 1) {
            _ = self.next();
            try self.expression();
        }
        break :blk i;
    };

    return number;
}
