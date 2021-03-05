const std = @import("std");
usingnamespace @import("../gemtext.zig");

fn fmtHtmlText(
    data: []const u8,
    comptime fmt: []const u8,
    options: std.fmt.FormatOptions,
    writer: anytype,
) !void {
    const illegal = "<>&\"\'";

    const replacement = [_][]const u8{
        "&lt;",
        "&gt;",
        "&amp;",
        "&quot;",
        "&apos;",
    };

    var last_offset: usize = 0;
    for (data) |c, index| {
        if (std.mem.indexOf(u8, illegal, &[1]u8{c})) |i| {
            if (index > last_offset) {
                try writer.writeAll(data[last_offset..index]);
            }
            last_offset = index + 1;
            try writer.writeAll(replacement[i]);
        }
    }
    if (data.len > last_offset) {
        try writer.writeAll(data[last_offset..]);
    }
}

pub fn fmtHtml(slice: []const u8) std.fmt.Formatter(fmtHtmlText) {
    return .{ .data = slice };
}

/// Renders a sequence of fragments into a html document.
/// `fragments` is a slice of fragments which describe the document,
/// `writer` is a `std.io.Writer` structure that will be the target of the document rendering.
/// The document will be rendered with CR LF line endings.
pub fn render(fragments: []const Fragment, writer: anytype) !void {
    const line_ending = "\r\n";
    for (fragments) |fragment| {
        switch (fragment) {
            .empty => try writer.writeAll("<p>&nbsp;</p>\r\n"),
            .paragraph => |paragraph| try writer.print("<p>{s}</p>" ++ line_ending, .{fmtHtml(paragraph)}),
            .preformatted => |preformatted| {
                try writer.writeAll("<pre>");
                for (preformatted.text.lines) |line, i| {
                    if (i > 0)
                        try writer.writeAll(line_ending);
                    try writer.print("{}", .{fmtHtml(line)});
                }
                try writer.writeAll("</pre>" ++ line_ending);
            },
            .quote => |quote| {
                try writer.writeAll("<blockquote>");
                for (quote.lines) |line, i| {
                    if (i > 0)
                        try writer.writeAll("<br>" ++ line_ending);
                    try writer.print("{}", .{fmtHtml(line)});
                }
                try writer.writeAll("</blockquote>" ++ line_ending);
            },
            .link => |link| {
                if (link.title) |title| {
                    try writer.print("<p><a href=\"{s}\">{}</a></p>" ++ line_ending, .{ link.href, fmtHtml(title) });
                } else {
                    try writer.print("<p><a href=\"{s}\">{}</a></p>" ++ line_ending, .{ link.href, fmtHtml(link.href) });
                }
            },
            .list => |list| {
                try writer.writeAll("<ul>" ++ line_ending);
                for (list.lines) |line| {
                    try writer.print("<li>{}</li>" ++ line_ending, .{fmtHtml(line)});
                }
                try writer.writeAll("</ul>" ++ line_ending);
            },
            .heading => |heading| {
                switch (heading.level) {
                    .h1 => try writer.print("<h1>{}</h1>" ++ line_ending, .{fmtHtml(heading.text)}),
                    .h2 => try writer.print("<h2>{}</h1>" ++ line_ending, .{fmtHtml(heading.text)}),
                    .h3 => try writer.print("<h3>{}</h1>" ++ line_ending, .{fmtHtml(heading.text)}),
                }
            },
        }
    }
}
