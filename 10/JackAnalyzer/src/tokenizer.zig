const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Token = struct {
    const Self = @This();
    const TokenType = enum(u3) {
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

pub const Parser = struct {
    const Self = @This();

    buf: []const u8,
    pos: usize,
    allocator: std.mem.Allocator,
    tokens: std.ArrayList(Token),
    keywords: std.StringHashMap(Token.KeyWord),

    fn initKeywords(allocator: Allocator) !std.StringHashMap(Token.KeyWord) {
        const TK = Token.KeyWord;
        const kvpair = .{
            .{ "class", TK.CLASS },
            .{ "method", TK.METHOD },
            .{ "function", TK.FUNCTION },
            .{ "constructor", TK.CONSTRUCTOR },
            .{ "int", TK.INT },
            .{ "boolean", TK.BOOLEAN },
            .{ "char", TK.CHAR },
            .{ "void", TK.VOID },
            .{ "var", TK.VAR },
            .{ "static", TK.STATIC },
            .{ "field", TK.FIELD },
            .{ "let", TK.LET },
            .{ "do", TK.DO },
            .{ "if", TK.IF },
            .{ "else", TK.ELSE },
            .{ "while", TK.WHILE },
            .{ "return", TK.RETURN },
            .{ "true", TK.TRUE },
            .{ "false", TK.FALSE },
            .{ "null", TK.NULL },
            .{ "this", TK.THIS },
        };

        var keywords = std.StringHashMap(Token.KeyWord).init(allocator);
        inline for (kvpair) |pair| {
            try keywords.put(pair.@"0", pair.@"1");
        }
        return keywords;
    }

    pub fn init(allocator: Allocator, source: []const u8) !Self {
        const keywords = try initKeywords(allocator);
        var tokens = std.ArrayList(Token).init(allocator);

        return Self{
            .buf = source,
            .pos = 0,
            .allocator = allocator,
            .tokens = tokens,
            .keywords = keywords,
        };
    }

    pub fn deinit(self: *Self) void {
        self.tokens.deinit();
        self.keywords.deinit();
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
                if (self.keywords.get(lexeme)) |keytype| {
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
