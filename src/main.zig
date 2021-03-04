const std = @import("std");
const testing = std.testing;

pub const Fragment = union(enum) {
    empty,
    paragraph: []const u8,
    preformatted: Preformatted,
    quote: TextLines,
    link: Link,
    list: TextLines,
    heading: Heading,
};

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
