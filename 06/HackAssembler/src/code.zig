const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;

const dSet = .{
    .{ "M", "001" },
    .{ "D", "010" },
    .{ "DM", "011" },
    .{ "A", "100" },
    .{ "AM", "101" },
    .{ "AD", "110" },
    .{ "ADM", "111" },
};

const cSet = .{
    .{ "0", "0101010" },
    .{ "1", "0111111" },
    .{ "-1", "0111010" },
    .{ "D", "0001100" },
    .{ "A", "0110000" },
    .{ "M", "1110000" },
    .{ "!D", "0001101" },
    .{ "!A", "0110001" },
    .{ "!M", "1110001" },
    .{ "-D", "0001111" },
    .{ "-A", "0110011" },
    .{ "-M", "1110011" },
    .{ "D+1", "0011111" },
    .{ "A+1", "0110111" },
    .{ "M+1", "1110111" },
    .{ "D-1", "0001110" },
    .{ "A-1", "0110010" },
    .{ "M-1", "1110010" },
    .{ "D+A", "0000010" },
    .{ "D+M", "1000010" },
    .{ "D-A", "0010011" },
    .{ "D-M", "1010011" },
    .{ "A-D", "0000111" },
    .{ "M-D", "1000111" },
    .{ "D&A", "0000000" },
    .{ "D&M", "1000000" },
    .{ "D|A", "0010101" },
    .{ "D|M", "1010101" },
};

const jSet = .{
    .{ "JGT", "001" },
    .{ "JEQ", "010" },
    .{ "JGE", "011" },
    .{ "JLT", "100" },
    .{ "JNE", "101" },
    .{ "JLE", "110" },
    .{ "JMP", "111" },
};

fn atoi(string: []const u8) callconv(.Inline) usize {
    var num: usize = 0;
    for (string) |char| {
        num = 10 * num + (char - '0');
    }
    return num;
}

pub const Code = struct {
    const Self = @This();

    ramaddr: usize,
    ramaddrStr: [16]u8,
    dmap: std.StringHashMap([]const u8),
    cmap: std.StringHashMap([]const u8),
    jmap: std.StringHashMap([]const u8),
    symtable: *std.StringHashMap(usize),

    pub fn init(allocator: *Allocator, symtable: *std.StringHashMap(usize)) !Self {
        var dmap = std.StringHashMap([]const u8).init(allocator);
        inline for (dSet) |pair| {
            try dmap.put(pair.@"0", pair.@"1");
        }

        var cmap = std.StringHashMap([]const u8).init(allocator);
        inline for (cSet) |pair| {
            try cmap.put(pair.@"0", pair.@"1");
        }

        var jmap = std.StringHashMap([]const u8).init(allocator);
        inline for (jSet) |pair| {
            try jmap.put(pair.@"0", pair.@"1");
        }

        return Self{
            .ramaddr = 15,
            .ramaddrStr = undefined,
            .dmap = dmap,
            .cmap = cmap,
            .jmap = jmap,
            .symtable = symtable,
        };
    }

    pub fn deinit(self: *Self) void {
        self.dmap.deinit();
        self.cmap.deinit();
        self.jmap.deinit();
    }

    pub fn translate(self: *Self, statement: []const u8) ![]const u8 {
        if (statement[0] == '@') {
            // A instruction
            var lastidx = for (statement) |char, i| {
                switch (char) {
                    ' ', '/' => {
                        break i;
                    },
                    else => {},
                }
            } else statement.len;
            var token = statement[1..lastidx];

            var num = switch (statement[1]) {
                '0'...'9' => blk: {
                    break :blk atoi(token);
                },
                else => blk: {
                    var value = self.symtable.get(token);
                    if (value == null) {
                        self.ramaddr += 1;
                        try self.symtable.put(token, self.ramaddr);
                        value = self.ramaddr;
                    }
                    break :blk value;
                },
            };

            _ = try std.fmt.bufPrint(&self.ramaddrStr, "0{b:0>15}", .{num.?});

            return &self.ramaddrStr;
        } else {
            // C instruction
            return statement;
        }
    }
};
