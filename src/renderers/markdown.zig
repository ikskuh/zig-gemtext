const std = @import("std");
const gemtext = @import("../gemtext.zig");
const Fragment = gemtext.Fragment;

const fmtHtml = @import("html.zig").fmtHtml;

/// Renders a sequence of fragments into a gemini text document.
/// `fragments` is a slice of fragments which describe the document,
/// `writer` is a `std.io.Writer` structure that will be the target of the document rendering.
/// The document will be rendered with CR LF line endings.
pub fn render(fragments: []const Fragment, writer: anytype) !void {
    const line_ending = "\r\n";
    for (fragments) |fragment, i| {
        if (i > 0)
            try writer.writeAll(line_ending);
        switch (fragment) {
            .empty => try writer.writeAll("&nbsp;" ++ line_ending),
            .paragraph => |paragraph| try writer.print("{s}" ++ line_ending, .{fmtHtml(paragraph)}),
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
                try writer.print("> {}  " ++ line_ending, .{fmtHtml(line)});
            },
            .link => |link| {
                if (link.title) |title| {
                    try writer.print("[{s}]({s})", .{ fmtHtml(title), link.href });
                } else {
                    try writer.writeAll(link.href);
                }
                try writer.writeAll(line_ending);
            },
            .list => |list| for (list.lines) |line| {
                try writer.print("- {}" ++ line_ending, .{fmtHtml(line)});
            },
            .heading => |heading| {
                switch (heading.level) {
                    .h1 => try writer.print("# {}" ++ line_ending, .{fmtHtml(heading.text)}),
                    .h2 => try writer.print("## {}" ++ line_ending, .{fmtHtml(heading.text)}),
                    .h3 => try writer.print("### {}" ++ line_ending, .{fmtHtml(heading.text)}),
                }
            },
        }
    }
}
