const std = @import("std");
usingnamespace @import("../gemtext.zig");

/// Renders a sequence of fragments into a gemini text document.
/// `fragments` is a slice of fragments which describe the document,
/// `writer` is a `std.io.Writer` structure that will be the target of the document rendering.
/// The document will be rendered with CR LF line endings.
pub fn render(fragments: []const Fragment, writer: anytype) !void {
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
