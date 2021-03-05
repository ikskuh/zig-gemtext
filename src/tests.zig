const std = @import("std");
const gemini = @import("gemtext.zig");

usingnamespace gemini;

fn testDocumentRendering(expected: []const u8, fragments: []const Fragment) !void {
    var buffer: [4096]u8 = undefined;

    var stream = std.io.fixedBufferStream(&buffer);

    try renderer.gemtext(fragments, stream.writer());

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

fn expectFragmentEqual(expected_opt: ?Fragment, actual_opt: ?Fragment) void {
    if (expected_opt == null) {
        std.testing.expect(actual_opt == null);
        return;
    }

    const expected = expected_opt.?;
    const actual = actual_opt.?;

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

fn testFragmentParsing(fragment: ?Fragment, text: []const u8) !void {
    // duplicate the passed in text to clear it later.
    const dupe_text = try std.testing.allocator.dupe(u8, text);
    defer std.testing.allocator.free(dupe_text);

    var parser = Parser.init(std.testing.allocator);
    defer parser.deinit();

    var got_fragment = false;
    var offset: usize = 0;
    while (offset < dupe_text.len) {
        var res = try parser.feed(std.testing.allocator, dupe_text[offset..]);
        offset += res.consumed;
        if (res.fragment) |*frag| {
            defer frag.free(std.testing.allocator);
            std.testing.expectEqual(false, got_fragment);

            // Clear the input text to make sure we didn't accidently pass a reference to our input slice
            std.mem.set(u8, dupe_text, '?');

            expectFragmentEqual(fragment, frag.*);
            got_fragment = true;
            break;
        }
    }

    std.testing.expectEqual(text.len, offset);

    if (try parser.finalize(std.testing.allocator)) |*frag| {
        defer frag.free(std.testing.allocator);
        std.testing.expectEqual(false, got_fragment);

        // Clear the input text to make sure we didn't accidently pass a reference to our input slice
        std.mem.set(u8, dupe_text, '?');

        expectFragmentEqual(fragment, frag.*);
    } else {
        if (fragment != null) {
            std.testing.expectEqual(true, got_fragment);
        } else {
            std.testing.expectEqual(false, got_fragment);
        }
    }
}

test "parse incomplete fragment" {
    var parser = Parser.init(std.testing.allocator);
    defer parser.deinit();

    std.testing.expectEqual(Parser.Result{ .consumed = 8, .fragment = null }, try parser.feed(std.testing.allocator, "12345678"));
    std.testing.expectEqual(Parser.Result{ .consumed = 8, .fragment = null }, try parser.feed(std.testing.allocator, "12345678"));
    std.testing.expectEqual(Parser.Result{ .consumed = 8, .fragment = null }, try parser.feed(std.testing.allocator, "12345678"));
    std.testing.expectEqual(Parser.Result{ .consumed = 8, .fragment = null }, try parser.feed(std.testing.allocator, "12345678"));
}

test "parse empty line" {
    try testFragmentParsing(null, "");
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

    try testFragmentParsing(Fragment{ .heading = Heading{ .level = .h3, .text = "#H1" } }, "####H1\r\n");
    try testFragmentParsing(Fragment{ .heading = Heading{ .level = .h3, .text = "#H1" } }, "####H1\r\n");
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

test "parse list block" {
    const list_0 = Fragment{
        .list = TextLines{
            .lines = &[_][]const u8{
                "item 0",
            },
        },
    };

    const list_3 = Fragment{
        .list = TextLines{
            .lines = &[_][]const u8{
                "item 1",
                "item 2",
                "item 3",
            },
        },
    };

    try testFragmentParsing(list_0, "* item 0");
    try testFragmentParsing(list_0, "* item 0\r\n");
    try testFragmentParsing(list_0, "*    item 0     ");
    try testFragmentParsing(list_0, "*    item 0     \r\n");

    try testFragmentParsing(list_3, "* item 1\r\n* item 2\r\n* item 3");
    try testFragmentParsing(list_3, "* item 1\r\n* item 2\r\n* item 3\r\n");
}

test "parse quote block" {
    const quote_0 = Fragment{
        .quote = TextLines{
            .lines = &[_][]const u8{
                "item 0",
            },
        },
    };

    const quote_3 = Fragment{
        .quote = TextLines{
            .lines = &[_][]const u8{
                "item 1",
                "item 2",
                "item 3",
            },
        },
    };

    try testFragmentParsing(quote_0, ">item 0");
    try testFragmentParsing(quote_0, ">item 0\r\n");
    try testFragmentParsing(quote_0, "> item 0");
    try testFragmentParsing(quote_0, "> item 0\r\n");
    try testFragmentParsing(quote_0, ">item 0     ");
    try testFragmentParsing(quote_0, ">item 0     \r\n");
    try testFragmentParsing(quote_0, ">    item 0     ");
    try testFragmentParsing(quote_0, ">    item 0     \r\n");

    try testFragmentParsing(quote_3, ">item 1\r\n>item 2\r\n>item 3");
    try testFragmentParsing(quote_3, ">item 1\r\n>item 2\r\n>item 3\r\n");
}

test "parse preformatted blocks (no alt text)" {
    const empty_block = Fragment{
        .preformatted = Preformatted{
            .alt_text = null,
            .text = TextLines{
                .lines = &[_][]const u8{},
            },
        },
    };

    const single_line_block = Fragment{
        .preformatted = Preformatted{
            .alt_text = null,
            .text = TextLines{
                .lines = &[_][]const u8{
                    " hello world ",
                },
            },
        },
    };

    const c_code_block = Fragment{
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
    };

    try testFragmentParsing(empty_block, "```");
    try testFragmentParsing(empty_block, "```\r\n```");
    try testFragmentParsing(empty_block, "```\r\n```\r\n");

    try testFragmentParsing(single_line_block, "```\r\n hello world ");
    try testFragmentParsing(single_line_block, "```\r\n hello world \r\n```");
    try testFragmentParsing(single_line_block, "```\r\n hello world \r\n```\r\n");

    try testFragmentParsing(c_code_block, "```\r\nint main() {\r\n    return 0;\r\n}");
    try testFragmentParsing(c_code_block, "```\r\nint main() {\r\n    return 0;\r\n}\r\n```");
    try testFragmentParsing(c_code_block, "```\r\nint main() {\r\n    return 0;\r\n}\r\n```\r\n");
}

test "parse preformatted blocks (with alt text)" {
    const empty_block = Fragment{
        .preformatted = Preformatted{
            .alt_text = "alt",
            .text = TextLines{
                .lines = &[_][]const u8{},
            },
        },
    };

    const single_line_block = Fragment{
        .preformatted = Preformatted{
            .alt_text = "alt",
            .text = TextLines{
                .lines = &[_][]const u8{
                    " hello world ",
                },
            },
        },
    };

    const c_code_block = Fragment{
        .preformatted = Preformatted{
            .alt_text = "alt",
            .text = TextLines{
                .lines = &[_][]const u8{
                    "int main() {",
                    "    return 0;",
                    "}",
                },
            },
        },
    };

    try testFragmentParsing(empty_block, "```alt");
    try testFragmentParsing(empty_block, "```alt\r\n```");
    try testFragmentParsing(empty_block, "```alt\r\n```\r\n");

    try testFragmentParsing(empty_block, "``` alt");
    try testFragmentParsing(empty_block, "```alt ");
    try testFragmentParsing(empty_block, "``` alt ");
    try testFragmentParsing(empty_block, "```    alt     ");

    try testFragmentParsing(single_line_block, "```alt\r\n hello world ");
    try testFragmentParsing(single_line_block, "```alt\r\n hello world \r\n```");
    try testFragmentParsing(single_line_block, "```alt\r\n hello world \r\n```\r\n");

    try testFragmentParsing(c_code_block, "```alt\r\nint main() {\r\n    return 0;\r\n}");
    try testFragmentParsing(c_code_block, "```alt\r\nint main() {\r\n    return 0;\r\n}\r\n```");
    try testFragmentParsing(c_code_block, "```alt\r\nint main() {\r\n    return 0;\r\n}\r\n```\r\n");
}

fn testSequenceParsing(expected_sequence: []const Fragment, text: []const u8) !void {
    // duplicate the passed in text to clear it later.
    const dupe_text = try std.testing.allocator.dupe(u8, text);
    defer std.testing.allocator.free(dupe_text);

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var actual_sequence = std.ArrayList(Fragment).init(std.testing.allocator);
    defer actual_sequence.deinit();

    {
        var parser = Parser.init(std.testing.allocator);
        defer parser.deinit();

        var offset: usize = 0;
        while (offset < dupe_text.len) {
            var res = try parser.feed(&arena.allocator, dupe_text[offset..]);
            offset += res.consumed;
            if (res.fragment) |frag| {
                try actual_sequence.append(frag);
            }
        }

        std.testing.expectEqual(text.len, offset);

        if (try parser.finalize(&arena.allocator)) |frag| {
            try actual_sequence.append(frag);
        }
    }

    // Clear the input text to make sure we didn't accidently pass a reference to our input slice
    std.mem.set(u8, dupe_text, '?');

    std.testing.expectEqual(expected_sequence.len, actual_sequence.items.len);

    for (expected_sequence) |expected, i| {
        expectFragmentEqual(expected, actual_sequence.items[i]);
    }
}

test "basic sequence parsing" {
    try testSequenceParsing(
        &[_]Fragment{
            Fragment{ .paragraph = "Hello" },
            Fragment{ .paragraph = "World!" },
        },
        \\Hello
        \\World!
        ,
    );
    try testSequenceParsing(
        &[_]Fragment{
            Fragment{ .empty = {} },
            Fragment{ .paragraph = "World!" },
        },
        \\
        \\World!
        \\
        ,
    );
    try testSequenceParsing(
        &[_]Fragment{
            Fragment{ .heading = Heading{ .level = .h1, .text = "Heading" } },
            Fragment{ .paragraph = "This is a bullet list:" },
            Fragment{ .list = TextLines{ .lines = &[_][]const u8{
                "Tortillias",
                "Cheese Dip",
                "Spicy Dip",
            } } },
        },
        \\# Heading
        \\This is a bullet list:
        \\* Tortillias
        \\* Cheese Dip
        \\* Spicy Dip
        \\
        ,
    );
}

test "sequenc hand over between block types" {
    // these are all possible permutations of list, quote and preformatted
    // this tests the proper hand over and termination between all block types

    const sequence_permutations = [_][3]usize{
        [3]usize{ 0, 1, 2 },
        [3]usize{ 1, 0, 2 },
        [3]usize{ 2, 0, 1 },
        [3]usize{ 0, 2, 1 },
        [3]usize{ 1, 2, 0 },
        [3]usize{ 2, 1, 0 },
    };

    const fragment_src = [3]Fragment{
        Fragment{
            .quote = TextLines{
                .lines = &[_][]const u8{
                    "ein",
                    "stein",
                    "said",
                },
            },
        },
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
        Fragment{
            .list = TextLines{
                .lines = &[_][]const u8{
                    "philly",
                    "cheese",
                    "steak",
                },
            },
        },
    };

    const text_src = [3][]const u8{
        "> ein\r\n>stein\r\n> said \r\n",
        "```\r\nint main() {\r\n    return 0;\r\n}\r\n```\r\n",
        "* philly \r\n*    cheese   \r\n* steak\r\n",
    };

    inline for (sequence_permutations) |permutation| {
        const expected_sequence = [_]Fragment{
            Fragment{ .paragraph = "---" },
            fragment_src[permutation[0]],
            fragment_src[permutation[1]],
            fragment_src[permutation[2]],
            Fragment{ .paragraph = "---" },
        };
        const text_rendering =
            "---\r\n" ++
            text_src[permutation[0]] ++
            text_src[permutation[1]] ++
            text_src[permutation[2]] ++
            "---\r\n";
        try testSequenceParsing(&expected_sequence, text_rendering);
    }
}

test "parse and render canonical document" {
    const document_text =
        "# Introduction\r\n" ++ // heading, h1
        "This is a basic text line\r\n" ++ // paragraph
        "And this is another one\r\n" ++
        "* And we can also do\r\n" ++ // list
        "* some nice\r\n" ++
        "* lists\r\n" ++
        "\r\n" ++ // empty
        "or empty lines!\r\n" ++
        "## Code Example\r\n" ++ // heading, h2
        "```c\r\n" ++ // preformatted
        "int main() {\r\n" ++
        "    return 0;\r\n" ++
        "}\r\n" ++
        "```\r\n" ++
        "### Quotes\r\n" ++ // heading, h3
        "we can also quote Einstein\r\n" ++
        "> This is a small step for a ziguana\r\n" ++ // quote
        "> but a great step for zig-kind!\r\n" ++
        "=> ftp://ftp.scene.org/pub/ Demoscene Archives\r\n"; // link

    var output_buffer: [2 * document_text.len]u8 = undefined;

    var input_stream = std.io.fixedBufferStream(document_text);
    var output_stream = std.io.fixedBufferStream(&output_buffer);

    var document = try Document.parse(std.testing.allocator, input_stream.reader());
    defer document.deinit();

    try document.render(output_stream.writer());

    std.testing.expectEqualStrings(document_text, output_stream.getWritten());
}

test "Parse examples from the spec" {
    const spec_examples =
        \\Text lines should be presented to the user, after being wrapped to the appropriate width for the client's viewport (see below).  Text lines may be presented to the user in a visually pleasing manner for general reading, the precise meaning of which is at the client's discretion.  For example, variable width fonts may be used, spacing may be normalised, with spaces between sentences being made wider than spacing between words, and other such typographical niceties may be applied.  Clients may permit users to customise the appearance of text lines by altering the font, font size, text and background colour, etc.  Authors should not expect to exercise any control over the precise rendering of their text lines, only of their actual textual content.  Content such as ASCII art, computer source code, etc. which may appear incorrectly when treated as such should be enclosed between preformatting toggle lines (see 5.4.3).
        \\Authors who insist on hard-wrapping their content MUST be aware that the content will display neatly on clients whose display device is as wide as the hard-wrapped length or wider, but will appear with irregular line widths on narrower clients.
        \\
        \\=> gemini://example.org/
        \\=> gemini://example.org/ An example link
        \\=> gemini://example.org/foo	Another example link at the same host
        \\=> foo/bar/baz.txt	A relative link
        \\=> 	gopher://example.org:70/1 A gopher link
        \\```
        \\=>[<whitespace>]<URL>[<whitespace><USER-FRIENDLY LINK NAME>]
        \\```
        \\# Appendix 1. Full two digit status codes
        \\## 10 INPUT
        \\### 5.5.3 Quote lines
        \\* <whitespa0ce> is any non-zero number of consecutive spaces or tabs
        \\* Square brackets indicate that the enclosed content is optional.
        \\* <URL> is a URL, which may be absolute or relative.
    ;

    var document = try Document.parseString(std.testing.allocator, spec_examples);
    defer document.deinit();
}
