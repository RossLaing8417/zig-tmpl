const std = @import("std");

pub fn main() void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);

    var area = std.heap.ArenaAllocator.init(gpa.allocator());
    defer area.deinit();

    const allocator = area.allocator();

    const args = std.process.argsAlloc(allocator) catch |err| {
        fatal("Error reading args: {s}\n", .{@errorName(err)});
    };

    if (args.len != 3) {
        fatal("Source and target arguments required\n", .{});
    }

    std.debug.print("tmpl: {s} -> {s}\n", .{ args[1], args[2] });

    var source_file = std.fs.cwd().openFile(args[1], .{}) catch |err| {
        fatal("Error opening source file {s}: {s}\n", .{ args[1], @errorName(err) });
    };
    defer source_file.close();

    var target_file = std.fs.cwd().createFile(args[2], .{}) catch |err| {
        fatal("Error creating target file {s}: {s}\n", .{ args[2], @errorName(err) });
    };
    defer target_file.close();

    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    const reader = source_file.reader();
    reader.readAllArrayList(&buffer, (source_file.metadata() catch |err| {
        fatal("Error reading source file metadata {s}: {s}\n", .{ args[1], @errorName(err) });
    }).size()) catch |err| {
        fatal("Error reading source file {s}:\n{}\n", .{ args[1], err });
    };

    const tokens = parse(allocator, buffer.items) catch |err| {
        fatal("Error parsing source file contents {s}: {s}\n", .{ args[1], @errorName(err) });
    };
    defer allocator.free(tokens);

    const parsed = render(allocator, tokens) catch |err| {
        fatal("Error rendering contents {s}: {s}\n", .{ args[2], @errorName(err) });
    };
    defer allocator.free(parsed);

    target_file.writeAll(parsed) catch |err| {
        fatal("Error writing target file {s}:\n{}\n", .{ args[2], err });
    };
}

fn fatal(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print(fmt, args);
    std.process.exit(1);
}

fn parse(allocator: std.mem.Allocator, source: []const u8) ![]const Token {
    var tokens = try std.ArrayList(Token).initCapacity(allocator, std.mem.count(u8, source, "#") + 1);
    defer tokens.deinit();

    var lexer = Lexer.init(source);
    while (true) {
        const token = lexer.nextToken();
        switch (token.type) {
            .Illegal => fatal("Error parsing source: {s}\n", .{token.literal}),
            .Eof => break,
            else => {},
        }
        try tokens.append(token);
    }

    return tokens.toOwnedSlice();
}

fn render(allocator: std.mem.Allocator, tokens: []const Token) ![]const u8 {
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    try buffer.appendSlice(
        \\const std = @import("std");
        \\pub fn exec(allocator: std.mem.Allocator, writer: std.io.AnyWriter, data: anytype) !void {
        \\    // --- Start
        \\
    );

    var data_fmt: bool = false;

    for (tokens) |token| {
        switch (token.type) {
            .Text => {
                if (token.literal.len > 0) {
                    var itr = std.mem.splitSequence(u8, token.literal, "\n");
                    try buffer.appendSlice("try writer.writeAll(\n");
                    while (itr.next()) |line| {
                        try buffer.appendSlice("\\\\");
                        try buffer.appendSlice(line);
                        try buffer.append('\n');
                    }
                    try buffer.appendSlice(");\n");
                }
            },
            .DataFmt => {
                try buffer.appendSlice("try writer.print(\"{");
                try buffer.appendSlice(token.literal);
                try buffer.appendSlice("}\",.{(");
                data_fmt = true;
            },
            .Data => {
                if (!data_fmt) {
                    try buffer.appendSlice("try writer.print(\"{}\",.{(");
                }
                try buffer.appendSlice(token.literal);
                try buffer.appendSlice(")});");
                data_fmt = false;
            },
            .Code => {
                try buffer.appendSlice(token.literal);
                try buffer.append('\n');
            },
            .Eof, .Illegal => unreachable,
        }
    }

    try buffer.appendSlice(
        \\
        \\    // --- End
        \\    const _allocator = allocator;
        \\    const _writer = writer;
        \\    const _data = data;
        \\    _ = _allocator;
        \\    _ = _writer;
        \\    _ = _data;
        \\}
        \\
    );

    return buffer.toOwnedSlice();
}

const TokenType = enum {
    Illegal,
    Eof,

    Text,
    DataFmt,
    Data,
    Code,
};

const Token = struct {
    type: TokenType,
    literal: []const u8,
};

const Lexer = struct {
    source: []const u8,
    position: usize = 0,
    read_position: usize = 0,
    char: u8 = 0,

    pub fn init(source: []const u8) Lexer {
        var lexer = Lexer{
            .source = source,
        };

        lexer.nextChar();

        return lexer;
    }

    pub fn nextToken(self: *Lexer) Token {
        const token: Token = switch (self.char) {
            0 => .{ .type = .Eof, .literal = "" },

            '#' => blk: {
                self.nextChar();
                if (self.char == '{') {
                    break :blk .{ .type = .DataFmt, .literal = self.readDataFmt() };
                }
                if (self.char == '=') {
                    self.nextChar();
                    const position = self.position;
                    while (self.char != '#') : (self.nextChar()) {}
                    break :blk .{ .type = .Data, .literal = self.source[position..self.position] };
                }
                const position = self.position;
                while (self.char != '#') : (self.nextChar()) {}
                break :blk .{ .type = .Code, .literal = self.source[position..self.position] };
            },

            '=' => blk: {
                if (self.source[self.position - 1] == '}') {
                    self.nextChar();
                    const position = self.position;
                    while (self.char != '#') : (self.nextChar()) {}
                    break :blk .{ .type = .Data, .literal = self.source[position..self.position] };
                }
                break :blk .{ .type = .Illegal, .literal = "Unexpected '='" };
            },

            else => blk: {
                const position = self.position;
                while (self.peekChar() != '#' and self.peekChar() != 0) : (self.nextChar()) {
                    if (self.char == '\'' and self.peekChar() == '#') {
                        self.nextChar();
                    }
                }
                break :blk .{ .type = .Text, .literal = self.source[position..self.read_position] };
            },
        };

        self.nextChar();

        return token;
    }

    fn nextChar(self: *Lexer) void {
        if (self.read_position >= self.source.len) {
            self.char = 0;
        } else {
            self.char = self.source[self.read_position];
        }
        self.position = self.read_position;
        self.read_position += 1;
    }

    fn peekChar(self: *Lexer) u8 {
        if (self.read_position >= self.source.len) {
            return 0;
        }
        return self.source[self.read_position];
    }

    fn readDataFmt(self: *Lexer) []const u8 {
        self.nextChar();
        const position = self.position;
        while (self.char != '}' and self.peekChar() != 0) : (self.nextChar()) {}
        return self.source[position..self.position];
    }
};
