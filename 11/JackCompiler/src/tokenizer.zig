const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Token = struct {
    const Self = @This();
    pub const TokenType = enum(u3) {
        KEYWORD,
        SYMBOL,
        IDENTIFIER,
        INT_CONST,
        STRING_CONST,
    };

    const tokentypes = [_][]const u8{
        "keyword",
        "symbol",
        "identifier",
        "integerConstant",
        "stringConstant",
    };

    pub const KeyWord = enum {
        CLASS,
        METHOD,
        FUNCTION,
        CONSTRUCTOR,
        INT,
        BOOLEAN,
        CHAR,
        VOID,
        VAR,
        STATIC,
        FIELD,
        LET,
        DO,
        IF,
        ELSE,
        WHILE,
        RETURN,
        TRUE,
        FALSE,
        NULL,
        THIS,
    };

    const keywords = std.ComptimeStringMap(KeyWord, .{
        .{ "class", .CLASS },
        .{ "method", .METHOD },
        .{ "function", .FUNCTION },
        .{ "constructor", .CONSTRUCTOR },
        .{ "int", .INT },
        .{ "boolean", .BOOLEAN },
        .{ "char", .CHAR },
        .{ "void", .VOID },
        .{ "var", .VAR },
        .{ "static", .STATIC },
        .{ "field", .FIELD },
        .{ "let", .LET },
        .{ "do", .DO },
        .{ "if", .IF },
        .{ "else", .ELSE },
        .{ "while", .WHILE },
        .{ "return", .RETURN },
        .{ "true", .TRUE },
        .{ "false", .FALSE },
        .{ "null", .NULL },
        .{ "this", .THIS },
    });

    pub const Literal = union(enum) {
        identifier: []const u8,
        string: []const u8,
        number: usize,
    };

    type: TokenType,
    lexeme: []const u8,
    keyword: ?KeyWord,
    number: ?usize,

    pub fn create(@"type": TokenType, lexeme: []const u8, keyword: ?KeyWord, number: ?usize) Self {
        return Self{
            .type = @"type",
            .lexeme = lexeme,
            .keyword = keyword,
            .number = number,
        };
    }

    pub fn getKeyword(bytes: []const u8) ?KeyWord {
        return keywords.get(bytes);
    }

    pub fn format(self: Self, comptime _: []const u8, _: std.fmt.FormatOptions, w: anytype) !void {
        try w.print("<{0s}> {1s} </{0s}>", .{ tokentypes[@enumToInt(self.@"type")], escape(self.lexeme) });
    }

    fn escape(symbol: []const u8) []const u8 {
        return switch (symbol[0]) {
            '<' => "&lt;",
            '>' => "&gt;",
            '"' => "&quot;",
            '&' => "&amp;",
            else => symbol,
        };
    }
};

pub const Tokenizer = struct {
    const Self = @This();

    buf: []const u8,
    pos: usize,
    allocator: Allocator,
    tokens: std.ArrayList(Token),

    pub fn init(allocator: Allocator, source: []const u8) !Self {
        var tokens = std.ArrayList(Token).init(allocator);

        return Self{
            .buf = source,
            .pos = 0,
            .allocator = allocator,
            .tokens = tokens,
        };
    }

    pub fn deinit(self: *Self) void {
        self.tokens.deinit();
    }

    pub fn scan(self: *Self) !std.ArrayList(Token) {
        while (self.pos < self.buf.len) {
            try self.scantoken();
        }
        return self.tokens;
    }

    fn scantoken(self: *Self) !void {
        self.skip();
        if (self.pos >= self.buf.len) return;

        const token = switch (self.buf[self.pos]) {
            '"' => blk: {
                var end = std.mem.indexOf(u8, self.buf[self.pos + 1 ..], "\"").?;
                var lexeme = self.buf[self.pos + 1 .. self.pos + 1 + end];
                self.pos = self.pos + 2 + end;
                break :blk Token.create(.STRING_CONST, lexeme, null, null);
            },
            '0'...'9' => blk: {
                var end = self.pos;
                while (end < self.buf.len and std.ascii.isDigit(self.buf[end])) {
                    end += 1;
                }
                var lexeme = self.buf[self.pos..end];
                self.pos = end;
                // INT_CONSTs are values in the range 0 to 32767
                break :blk Token.create(.INT_CONST, lexeme, null, try std.fmt.parseInt(u15, lexeme, 10));
            },
            'a'...'z', 'A'...'Z', '_' => blk: {
                var end = self.pos;
                while (end < self.buf.len and (std.ascii.isAlNum(self.buf[end]) or self.buf[end] == '_')) {
                    end += 1;
                }
                var lexeme = self.buf[self.pos..end];
                self.pos = end;
                if (Token.getKeyword(lexeme)) |keytype| {
                    break :blk Token.create(.KEYWORD, lexeme, keytype, null);
                } else {
                    break :blk Token.create(.IDENTIFIER, lexeme, null, null);
                }
            },
            else => blk: {
                var lexeme = self.buf[self.pos .. self.pos + 1];
                self.pos += 1;
                break :blk Token.create(.SYMBOL, lexeme, null, null);
            },
        };

        try self.tokens.append(token);
    }

    fn skip(self: *Self) void {
        while (self.pos < self.buf.len) {
            const ch = self.buf[self.pos];
            switch (ch) {
                '\r', '\n', ' ', '\t' => {
                    self.pos += 1;
                },
                '/' => {
                    if (self.buf[self.pos + 1] == '/') {
                        self.pos += std.mem.indexOf(u8, self.buf[self.pos..], "\n").? + 1;
                    } else if (self.buf[self.pos + 1] == '*') {
                        self.pos += std.mem.indexOf(u8, self.buf[self.pos..], "*/").? + 2;
                    } else {
                        break;
                    }
                },
                else => break,
            }
        }
    }
};
