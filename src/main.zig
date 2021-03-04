const std = @import("std");
const testing = std.testing;

pub const FragmentType = std.meta.TagType(Fragment);
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

/// A gemtext document
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
        try renderFragments(self.fragments.items, writer);
    }
};

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

    line_buffer: std.ArrayList(u8),
    state: State,

    /// Initialize a new parser.
    pub fn init(allocator: *std.mem.Allocator) Self {
        return Self{
            .line_buffer = std.ArrayList(u8).init(allocator),
            .state = .default,
        };
    }

    /// Destroy the parser and all its allocated memory.
    pub fn deinit(self: *Self) void {
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
        while (offset < slice.len) : (offset += 1) {
            if (slice[offset] == '\n') {
                defer self.line_buffer.shrinkRetainingCapacity(0);

                // When we are testing, we set the temporary line memory to '!' so we can recognize this in tests.
                defer if (std.builtin.is_test) std.mem.set(u8, self.line_buffer.items, '!');

                var line = self.line_buffer.items;
                if (line.len > 0 and line[line.len - 1] == '\r') {
                    line = line[0 .. line.len - 1];
                }

                switch (self.state) {
                    .default => {
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
                    },
                    .block_quote => @panic("TODO: block_quote implemented yet"),
                    .preformatted => @panic("TODO: preformatted implemented yet"),
                    .list => @panic("TODO: list implemented yet"),
                }
            } else {
                try self.line_buffer.append(slice[offset]);
            }
        }
        return Result{ .consumed = slice.len, .fragment = null };
    }
};

/// Renders a sequence of fragments into a gemini text document.
/// `fragments` is a slice of fragments which describe the document,
/// `writer` is a `std.io.Writer` structure that will be the target of the document rendering.
/// The document will be rendered with CR LF line endings.
pub fn renderFragments(fragments: []const Fragment, writer: anytype) !void {
    const line_ending = "\r\n";
    for (fragments) |fragment| {
        switch (fragment) {
            .empty => try writer.writeAll(line_ending),
            .paragraph => |paragraph| try writer.print("{s}" ++ line_ending, .{paragraph}),
            .preformatted => |preformatted| {
                if (preformatted.alt_text) |alt_text| {
                    try writer.print("```{s}" ++ line_ending, .{alt_text});
                } else {
                    try writer.writeAll("```" ++ line_ending);
                }
                for (preformatted.text.lines) |line| {
                    try writer.writeAll(line);
                    try writer.writeAll(line_ending);
                }
                try writer.writeAll("```" ++ line_ending);
            },
            .quote => |quote| for (quote.lines) |line| {
                try writer.writeAll("> ");
                try writer.writeAll(line);
                try writer.writeAll(line_ending);
            },
            .link => |link| {
                try writer.writeAll("=> ");
                try writer.writeAll(link.href);
                if (link.title) |title| {
                    try writer.writeAll(" ");
                    try writer.writeAll(title);
                }
                try writer.writeAll(line_ending);
            },
            .list => |list| for (list.lines) |line| {
                try writer.writeAll("* ");
                try writer.writeAll(line);
                try writer.writeAll(line_ending);
            },
            .heading => |heading| {
                switch (heading.level) {
                    .h1 => try writer.writeAll("# "),
                    .h2 => try writer.writeAll("## "),
                    .h3 => try writer.writeAll("### "),
                }
                try writer.writeAll(heading.text);
                try writer.writeAll(line_ending);
            },
        }
    }
}

fn testDocumentRendering(expected: []const u8, fragments: []const Fragment) !void {
    var buffer: [4096]u8 = undefined;

    var stream = std.io.fixedBufferStream(&buffer);

    try renderFragments(fragments, stream.writer());

    std.testing.expectEqualStrings(expected, stream.getWritten());
}

test "render empty line" {
    try testDocumentRendering("\r\n", &[_]Fragment{
        Fragment{
            .empty = {},
        },
    });
}

test "render multiple lines" {
    try testDocumentRendering("\r\n\r\n", &[_]Fragment{
        Fragment{ .empty = {} },
        Fragment{ .empty = {} },
    });
}

test "render paragraph line" {
    try testDocumentRendering("Hello, World!\r\n", &[_]Fragment{
        Fragment{
            .paragraph = "Hello, World!",
        },
    });
}

test "render preformatted text (no alt text)" {
    try testDocumentRendering("```\r\nint main() {\r\n    return 0;\r\n}\r\n```\r\n", &[_]Fragment{
        Fragment{
            .preformatted = Preformatted{
                .alt_text = null,
                .text = TextLines{
                    .lines = &[_][]const u8{
                        "int main() {",
                        "    return 0;",
                        "}",
                    },
                },
            },
        },
    });
}

test "render preformatted text (with alt text)" {
    try testDocumentRendering("```c\r\nint main() {\r\n    return 0;\r\n}\r\n```\r\n", &[_]Fragment{
        Fragment{
            .preformatted = Preformatted{
                .alt_text = "c",
                .text = TextLines{
                    .lines = &[_][]const u8{
                        "int main() {",
                        "    return 0;",
                        "}",
                    },
                },
            },
        },
    });
}

test "render quote text lines" {
    try testDocumentRendering("> Two things are infinite: the universe and human stupidity; and I'm not sure about the universe.\r\n> - Albert Einstein\r\n", &[_]Fragment{
        Fragment{ .quote = TextLines{
            .lines = &[_][]const u8{
                "Two things are infinite: the universe and human stupidity; and I'm not sure about the universe.",
                "- Albert Einstein",
            },
        } },
    });
}

test "render link lines" {
    try testDocumentRendering("=> gemini://kristall.random-projects.net/\r\n=> gemini://kristall.random-projects.net/ Kristall Small-Internet Browser\r\n", &[_]Fragment{
        Fragment{
            .link = Link{
                .href = "gemini://kristall.random-projects.net/",
                .title = null,
            },
        },
        Fragment{
            .link = Link{
                .href = "gemini://kristall.random-projects.net/",
                .title = "Kristall Small-Internet Browser",
            },
        },
    });
}

test "render headings" {
    try testDocumentRendering("# Heading 1\r\n## Heading 2\r\n### Heading 3\r\n", &[_]Fragment{
        Fragment{ .heading = Heading{ .level = .h1, .text = "Heading 1" } },
        Fragment{ .heading = Heading{ .level = .h2, .text = "Heading 2" } },
        Fragment{ .heading = Heading{ .level = .h3, .text = "Heading 3" } },
    });
}

fn expectEqualLines(expected: TextLines, actual: TextLines) void {
    std.testing.expectEqual(expected.lines.len, actual.lines.len);
    for (expected.lines) |line, i| {
        std.testing.expectEqualStrings(line, actual.lines[i]);
    }
}

fn expectFragmentEqual(expected: Fragment, actual: Fragment) void {
    std.testing.expectEqual(@as(FragmentType, expected), @as(FragmentType, actual));

    switch (expected) {
        .empty => {},
        .paragraph => |paragraph| std.testing.expectEqualStrings(paragraph, actual.paragraph),
        .preformatted => |preformatted| {
            if (preformatted.alt_text) |alt_text|
                std.testing.expectEqualStrings(alt_text, actual.preformatted.alt_text.?);
            expectEqualLines(preformatted.text, actual.preformatted.text);
        },
        .quote => |quote| expectEqualLines(quote, actual.quote),
        .link => |link| {
            if (link.title) |title|
                std.testing.expectEqualStrings(title, actual.link.title.?);
            std.testing.expectEqualStrings(link.href, actual.link.href);
        },
        .list => |list| expectEqualLines(list, actual.list),
        .heading => |heading| {
            std.testing.expectEqual(heading.level, actual.heading.level);
            std.testing.expectEqualStrings(heading.text, actual.heading.text);
        },
    }
}

fn testFragmentParsing(fragment: Fragment, text: []const u8) !void {
    // duplicate the passed in text to clear it later.
    const dupe_text = try std.testing.allocator.dupe(u8, text);
    defer std.testing.allocator.free(dupe_text);

    var parser = Parser.init(std.testing.allocator);
    defer parser.deinit();

    var offset: usize = 0;
    while (offset < dupe_text.len) {
        var res = try parser.feed(std.testing.allocator, dupe_text[offset..]);
        offset += res.consumed;
        if (res.fragment) |*frag| {
            defer frag.free(std.testing.allocator);

            // Clear the input text to make sure we didn't accidently pass a reference to our input slice
            std.mem.set(u8, dupe_text, '?');

            expectFragmentEqual(fragment, frag.*);
            break;
        }
    }
    std.testing.expectEqual(text.len, offset);
}

test "parse empty line" {
    try testFragmentParsing(Fragment{ .empty = {} }, "");
    try testFragmentParsing(Fragment{ .empty = {} }, "\r\n");
}

test "parse normal paragraph" {
    try testFragmentParsing(Fragment{ .paragraph = "Hello World!" }, "Hello World!");
    try testFragmentParsing(Fragment{ .paragraph = "Hello World!" }, "Hello World!\r\n");
}

test "parse heading line" {
    try testFragmentParsing(Fragment{ .heading = Heading{ .level = .h1, .text = "Hello World!" } }, "#Hello World!");
    try testFragmentParsing(Fragment{ .heading = Heading{ .level = .h1, .text = "Hello World!" } }, "#Hello World!\r\n");
    try testFragmentParsing(Fragment{ .heading = Heading{ .level = .h1, .text = "Hello World!" } }, "# Hello World!");
    try testFragmentParsing(Fragment{ .heading = Heading{ .level = .h1, .text = "Hello World!" } }, "# Hello World!\r\n");

    try testFragmentParsing(Fragment{ .heading = Heading{ .level = .h2, .text = "Hello World!" } }, "##Hello World!");
    try testFragmentParsing(Fragment{ .heading = Heading{ .level = .h2, .text = "Hello World!" } }, "##Hello World!\r\n");
    try testFragmentParsing(Fragment{ .heading = Heading{ .level = .h2, .text = "Hello World!" } }, "## Hello World!");
    try testFragmentParsing(Fragment{ .heading = Heading{ .level = .h2, .text = "Hello World!" } }, "## Hello World!\r\n");

    try testFragmentParsing(Fragment{ .heading = Heading{ .level = .h3, .text = "Hello World!" } }, "###Hello World!");
    try testFragmentParsing(Fragment{ .heading = Heading{ .level = .h3, .text = "Hello World!" } }, "###Hello World!\r\n");
    try testFragmentParsing(Fragment{ .heading = Heading{ .level = .h3, .text = "Hello World!" } }, "### Hello World!");
    try testFragmentParsing(Fragment{ .heading = Heading{ .level = .h3, .text = "Hello World!" } }, "### Hello World!\r\n");
}

test "parse link (no title)" {
    const fragment = Fragment{
        .link = Link{
            .href = "gemini://circumlunar.space/",
            .title = null,
        },
    };

    try testFragmentParsing(fragment, "=>gemini://circumlunar.space/");
    try testFragmentParsing(fragment, "=>gemini://circumlunar.space/\r\n");
    try testFragmentParsing(fragment, "=> gemini://circumlunar.space/");
    try testFragmentParsing(fragment, "=> gemini://circumlunar.space/\r\n");

    try testFragmentParsing(fragment, "=>gemini://circumlunar.space/      ");
    try testFragmentParsing(fragment, "=>gemini://circumlunar.space/      \r\n");
    try testFragmentParsing(fragment, "=> gemini://circumlunar.space/      ");
    try testFragmentParsing(fragment, "=> gemini://circumlunar.space/      \r\n");
}

test "parse link (with title)" {
    const fragment = Fragment{
        .link = Link{
            .href = "gemini://circumlunar.space/",
            .title = "This is a link!",
        },
    };

    try testFragmentParsing(fragment, "=>gemini://circumlunar.space/ This is a link!");
    try testFragmentParsing(fragment, "=>gemini://circumlunar.space/ This is a link!\r\n");
    try testFragmentParsing(fragment, "=> gemini://circumlunar.space/ This is a link!");
    try testFragmentParsing(fragment, "=> gemini://circumlunar.space/ This is a link!\r\n");

    try testFragmentParsing(fragment, "=>gemini://circumlunar.space/ This is a link!      ");
    try testFragmentParsing(fragment, "=>gemini://circumlunar.space/ This is a link!      \r\n");
    try testFragmentParsing(fragment, "=> gemini://circumlunar.space/ This is a link!      ");
    try testFragmentParsing(fragment, "=> gemini://circumlunar.space/ This is a link!      \r\n");

    try testFragmentParsing(fragment, "=>gemini://circumlunar.space/            This is a link!");
    try testFragmentParsing(fragment, "=>gemini://circumlunar.space/            This is a link!\r\n");
    try testFragmentParsing(fragment, "=> gemini://circumlunar.space/            This is a link!");
    try testFragmentParsing(fragment, "=> gemini://circumlunar.space/            This is a link!\r\n");

    try testFragmentParsing(fragment, "=>gemini://circumlunar.space/            This is a link!      ");
    try testFragmentParsing(fragment, "=>gemini://circumlunar.space/            This is a link!      \r\n");
    try testFragmentParsing(fragment, "=> gemini://circumlunar.space/            This is a link!      ");
    try testFragmentParsing(fragment, "=> gemini://circumlunar.space/            This is a link!      \r\n");
}
