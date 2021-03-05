const std = @import("std");
const testing = std.testing;

/// Provides a set of renderers for gemtext documents.
pub const renderer = struct {
    pub const gemtext = @import("renderers/gemtext.zig").render;
    pub const html = @import("renderers/html.zig").render;
};

/// The type of a `Fragment`.
pub const FragmentType = std.meta.TagType(Fragment);

/// A fragment is a part of a gemini text document.
/// It is either a basic line or contains several lines grouped into logical units.
pub const Fragment = union(enum) {
    const Self = @This();

    empty,
    paragraph: []const u8,
    preformatted: Preformatted,
    quote: TextLines,
    link: Link,
    list: TextLines,
    heading: Heading,

    pub fn free(self: *Self, allocator: *std.mem.Allocator) void {
        switch (self.*) {
            .empty => {},
            .paragraph => |text| allocator.free(text),
            .preformatted => |*preformatted| {
                if (preformatted.alt_text) |alt|
                    allocator.free(alt);
                freeTextLines(&preformatted.text, allocator);
            },
            .quote => |*quote| freeTextLines(quote, allocator),
            .link => |link| {
                if (link.title) |title|
                    allocator.free(title);
                allocator.free(link.href);
            },
            .list => |*list| freeTextLines(list, allocator),
            .heading => |heading| allocator.free(heading.text),
        }
        self.* = undefined;
    }
};

fn freeTextLines(lines: *TextLines, allocator: *std.mem.Allocator) void {
    for (lines.lines) |line| {
        allocator.free(line);
    }
    allocator.free(lines.lines);
}

/// A grouped set of lines that appear in the same kind of formatting.
pub const TextLines = struct {
    lines: []const []const u8,
};

pub const Level = enum {
    h1,
    h2,
    h3,
};

pub const Heading = struct {
    level: Level,
    text: []const u8,
};

pub const Preformatted = struct {
    alt_text: ?[]const u8,
    text: TextLines,
};

pub const Link = struct {
    href: []const u8,
    title: ?[]const u8,
};

/// A gemini text document
pub const Document = struct {
    const Self = @This();

    arena: std.heap.ArenaAllocator,
    fragments: std.ArrayList(Fragment),

    pub fn init(allocator: *std.mem.Allocator) Self {
        return Self{
            .arena = std.heap.ArenaAllocator.init(allocator),
            .fragments = std.ArrayList(Fragment).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.arena.deinit();
        self.fragments.deinit();
    }

    /// Renders the document into canonical gemini text.
    pub fn render(self: Self, writer: anytype) !void {
        try renderer.gemtext(self.fragments.items, writer);
    }

    /// Parses a document from a text string.
    pub fn parseString(allocator: *std.mem.Allocator, text: []const u8) !Document {
        var stream = std.io.fixedBufferStream(text);
        return parse(allocator, stream.reader());
    }

    /// Parses a document from a stream.
    pub fn parse(allocator: *std.mem.Allocator, reader: anytype) !Document {
        var doc = Document.init(allocator);
        errdefer doc.deinit();

        var parser = Parser.init(allocator);
        defer parser.deinit();

        while (true) {
            var buffer: [1024]u8 = undefined;
            const len = try reader.readAll(&buffer);
            if (len == 0)
                break;

            var offset: usize = 0;
            while (offset < len) {
                var res = try parser.feed(&doc.arena.allocator, buffer[offset..len]);
                offset += res.consumed;
                if (res.fragment) |*frag| {
                    errdefer frag.free(&doc.arena.allocator);
                    try doc.fragments.append(frag.*);
                }
            }
        }

        if (try parser.finalize(&doc.arena.allocator)) |*frag| {
            errdefer frag.free(&doc.arena.allocator);
            try doc.fragments.append(frag.*);
        }

        return doc;
    }
};

/// this declares the strippable whitespace in a gemini text line
const legal_whitespace = "\t ";

fn trimLine(input: []const u8) []const u8 {
    return std.mem.trim(u8, input, legal_whitespace);
}

fn dupeAndTrim(allocator: *std.mem.Allocator, input: []const u8) ![]u8 {
    return try allocator.dupe(
        u8,
        trimLine(input),
    );
}

/// A gemtext asynchronous push parser that will be non-blocking.
pub const Parser = struct {
    const Self = @This();

    const State = enum {
        default,
        block_quote,
        preformatted,
        list,
    };

    pub const Result = struct {
        /// The number of bytes that were consumed form the input slice.
        consumed: usize,
        /// The fragment that was parsed.
        fragment: ?Fragment,
    };

    allocator: *std.mem.Allocator,
    line_buffer: std.ArrayList(u8),
    text_block_buffer: std.ArrayList([]u8),
    state: State,

    /// Initialize a new parser.
    pub fn init(allocator: *std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .line_buffer = std.ArrayList(u8).init(allocator),
            .text_block_buffer = std.ArrayList([]u8).init(allocator),
            .state = .default,
        };
    }

    /// Destroy the parser and all its allocated memory.
    pub fn deinit(self: *Self) void {
        for (self.text_block_buffer.items) |string| {
            self.allocator.free(string);
        }
        self.text_block_buffer.deinit();
        self.line_buffer.deinit();
        self.* = undefined;
    }

    /// Feed a slice into the parser.
    /// This will continue parsing the gemtext document. `slice` is the next bytes in the 
    /// document byte sequence.
    /// The result will contain both the number of `consumed` bytes in `slice` and a `fragment` if any line was detected.
    /// `fragment_allocator` will be used to allocate the memory returned in `Fragment` if any.
    pub fn feed(self: *Self, fragment_allocator: *std.mem.Allocator, slice: []const u8) !Result {
        var offset: usize = 0;
        main_loop: while (offset < slice.len) : (offset += 1) {
            if (slice[offset] == '\n') {
                var line = self.line_buffer.items;
                if (line.len > 0 and line[line.len - 1] == '\r') {
                    line = line[0 .. line.len - 1];
                }

                if (self.state == .preformatted and !std.mem.startsWith(u8, line, "```")) {
                    // we are in a preformatted block that is not terminated right now...
                    const line_buffer = try self.allocator.dupe(u8, line);
                    errdefer self.allocator.free(line_buffer);

                    try self.text_block_buffer.append(line_buffer);

                    self.line_buffer.shrinkRetainingCapacity(0);

                    continue :main_loop;
                } else if (std.mem.startsWith(u8, line, "* ")) {
                    switch (self.state) {
                        .block_quote => {
                            var res = Result{
                                .consumed = offset, // one less so we will land here the next round again
                                .fragment = try self.createBlockFragment(fragment_allocator, .block_quote),
                            };
                            self.state = .default;
                            return res;
                        },
                        .preformatted => {
                            var res = Result{
                                .consumed = offset, // one less so we will land here the next round again
                                .fragment = try self.createBlockFragment(fragment_allocator, .preformatted),
                            };
                            self.state = .default;
                            return res;
                        },
                        .list, .default => {},
                    }

                    if (self.state != .list)
                        std.debug.assert(self.text_block_buffer.items.len == 0);

                    self.state = .list;

                    const line_buffer = try self.allocator.dupe(u8, trimLine(line[2..]));
                    errdefer self.allocator.free(line_buffer);

                    try self.text_block_buffer.append(line_buffer);

                    self.line_buffer.shrinkRetainingCapacity(0);

                    continue :main_loop;
                } else if (std.mem.startsWith(u8, line, ">")) {
                    switch (self.state) {
                        .list => {
                            var res = Result{
                                .consumed = offset, // one less so we will land here the next round again
                                .fragment = try self.createBlockFragment(fragment_allocator, .list),
                            };
                            self.state = .default;
                            return res;
                        },
                        .preformatted => {
                            var res = Result{
                                .consumed = offset, // one less so we will land here the next round again
                                .fragment = try self.createBlockFragment(fragment_allocator, .preformatted),
                            };
                            self.state = .default;
                            return res;
                        },
                        .block_quote, .default => {},
                    }

                    if (self.state != .block_quote)
                        std.debug.assert(self.text_block_buffer.items.len == 0);

                    self.state = .block_quote;

                    const line_buffer = try self.allocator.dupe(u8, trimLine(line[1..]));
                    errdefer self.allocator.free(line_buffer);

                    try self.text_block_buffer.append(line_buffer);

                    self.line_buffer.shrinkRetainingCapacity(0);

                    continue :main_loop;
                } else if (std.mem.startsWith(u8, line, "```")) {
                    switch (self.state) {
                        .list => {
                            self.state = .default;
                            return Result{
                                .consumed = offset, // one less so we will land here the next round again
                                .fragment = try self.createBlockFragment(fragment_allocator, .list),
                            };
                        },
                        .block_quote => {
                            self.state = .default;
                            return Result{
                                .consumed = offset, // one less so we will land here the next round again
                                .fragment = try self.createBlockFragment(fragment_allocator, .block_quote),
                            };
                        },
                        .preformatted => {
                            self.state = .default;
                            self.line_buffer.shrinkRetainingCapacity(0);
                            return Result{
                                .consumed = offset + 1,
                                .fragment = try self.createBlockFragment(fragment_allocator, .preformatted),
                            };
                        },
                        .default => {
                            std.debug.assert(self.text_block_buffer.items.len == 0);
                            self.state = .preformatted;

                            // preformatted text blocks are prefixed with a line that stores the alt text.
                            // if the alt text string is empty, we're storing a `null` there later.

                            const line_buffer = try self.allocator.dupe(u8, trimLine(line[3..]));
                            errdefer self.allocator.free(line_buffer);

                            try self.text_block_buffer.append(line_buffer);

                            self.line_buffer.shrinkRetainingCapacity(0);

                            continue :main_loop;
                        },
                    }
                    unreachable;
                }

                // If we get here, we are reading a line that is not in the block anymore, so
                // we need to finalize and emit that block, then return that fragment

                if (try self.createBlockFragmentFromStateAndResetState(fragment_allocator)) |fragment| {
                    return Result{
                        .consumed = offset, // one less so we will land here the next round again
                        .fragment = fragment,
                    };
                }

                // The defer must be after the processing of multi-line blocks, otherwise
                // we lose the current line info.
                defer self.line_buffer.shrinkRetainingCapacity(0);
                std.debug.assert(self.state == .default);

                var fragment: Fragment = if (std.mem.eql(u8, trimLine(line), ""))
                    Fragment{ .empty = {} }
                else if (std.mem.startsWith(u8, line, "###"))
                    Fragment{ .heading = Heading{ .level = .h3, .text = try dupeAndTrim(fragment_allocator, line[3..]) } }
                else if (std.mem.startsWith(u8, line, "##"))
                    Fragment{ .heading = Heading{ .level = .h2, .text = try dupeAndTrim(fragment_allocator, line[2..]) } }
                else if (std.mem.startsWith(u8, line, "#"))
                    Fragment{ .heading = Heading{ .level = .h1, .text = try dupeAndTrim(fragment_allocator, line[1..]) } }
                else if (std.mem.startsWith(u8, line, "=>")) blk: {
                    const temp = trimLine(line[2..]);

                    for (temp) |c, i| {
                        const str = [_]u8{c};
                        if (std.mem.indexOf(u8, legal_whitespace, &str) != null) {
                            break :blk Fragment{ .link = Link{
                                .href = try dupeAndTrim(fragment_allocator, trimLine(temp[0..i])),
                                .title = try dupeAndTrim(fragment_allocator, trimLine(temp[i + 1 ..])),
                            } };
                        }
                    } else {
                        break :blk Fragment{ .link = Link{
                            .href = try dupeAndTrim(fragment_allocator, temp),
                            .title = null,
                        } };
                    }
                } else Fragment{ .paragraph = try dupeAndTrim(fragment_allocator, line) };

                return Result{
                    .consumed = offset + 1,
                    .fragment = fragment,
                };
            } else {
                try self.line_buffer.append(slice[offset]);
            }
        }

        return Result{
            .consumed = slice.len,
            .fragment = null,
        };
    }

    /// Notifies the parser that we've reached the end of the document.
    /// This funtion makes sure every block is terminated properly and returned
    /// even if the last line is not terminated.
    /// `fragment_allocator` will be used to allocate the memory returned in `Fragment` if any.
    pub fn finalize(self: *Self, fragment_allocator: *std.mem.Allocator) !?Fragment {
        // for default state and an empty line, we can be sure that there is nothing
        // to be done. If the line is empty, but we're still in a block, we still have to terminate
        // that block to be sure
        if (self.state == .default and self.line_buffer.items.len == 0)
            return null;

        // feed a line end sequence to guaranteed termination of the current line.
        // This will either finish a normal line or complete the current block.
        var res = try self.feed(fragment_allocator, "\n");

        // when we get a fragment, we ended a normal line
        if (res.fragment != null)
            return res.fragment.?;

        // if not, we are currently parsing a block and must now convert the block
        // into a fragment.
        std.debug.assert(self.state != .default);
        var frag_or_null = try self.createBlockFragmentFromStateAndResetState(fragment_allocator);
        return frag_or_null orelse unreachable;
    }

    const BlockType = enum { preformatted, block_quote, list };
    fn createBlockFragment(self: *Self, fragment_allocator: *std.mem.Allocator, fragment_type: BlockType) !Fragment {
        var alt_text: ?[]const u8 = if (fragment_type == .preformatted) blk: {
            std.debug.assert(self.text_block_buffer.items.len > 0);

            const src_alt_text = self.text_block_buffer.orderedRemove(0);
            defer self.allocator.free(src_alt_text);

            break :blk if (!std.mem.eql(u8, src_alt_text, ""))
                try fragment_allocator.dupe(u8, src_alt_text)
            else
                null;
        } else null;
        errdefer if (alt_text) |text|
            fragment_allocator.free(text);

        var lines = try fragment_allocator.alloc([]const u8, self.text_block_buffer.items.len);
        errdefer fragment_allocator.free(lines);

        var offset: usize = 0;
        errdefer while (offset > 0) {
            offset -= 1;
            fragment_allocator.free(lines[offset]);
        };

        while (offset < lines.len) : (offset += 1) {
            lines[offset] = try fragment_allocator.dupe(u8, self.text_block_buffer.items[offset]);
        }

        for (self.text_block_buffer.items) |item| {
            self.allocator.free(item);
        }

        self.text_block_buffer.shrinkRetainingCapacity(0);

        return switch (fragment_type) {
            .preformatted => Fragment{ .preformatted = Preformatted{
                .alt_text = alt_text,
                .text = TextLines{ .lines = lines },
            } },
            .block_quote => Fragment{ .quote = TextLines{ .lines = lines } },
            .list => Fragment{ .list = TextLines{ .lines = lines } },
        };
    }

    fn createBlockFragmentFromStateAndResetState(self: *Self, fragment_allocator: *std.mem.Allocator) !?Fragment {
        defer self.state = .default;
        return switch (self.state) {
            .block_quote => try self.createBlockFragment(fragment_allocator, .block_quote),
            .preformatted => try self.createBlockFragment(fragment_allocator, .preformatted),
            .list => try self.createBlockFragment(fragment_allocator, .list),
            .default => null,
        };
    }
};
