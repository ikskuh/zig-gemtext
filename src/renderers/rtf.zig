const std = @import("std");
const gemtext = @import("../gemtext.zig");
const Fragment = gemtext.Fragment;

const line_ending = "\r\n";

fn fmtRtfText(
    data: []const u8,
    comptime fmt: []const u8,
    options: std.fmt.FormatOptions,
    writer: anytype,
) !void {
    _ = fmt;
    _ = options;

    const illegal = "\\{}";

    const replacement = [_][]const u8{
        "\\\\",
        "\\{",
        "\\}",
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

pub fn fmtRtf(slice: []const u8) std.fmt.Formatter(fmtRtfText) {
    return .{ .data = slice };
}

pub const header = "{\\rtf1\\ansi{\\fonttbl{\\f0\\fswiss}{\\f1\\fmodern Courier New{\\*\\falt Monospace};}}" ++ line_ending;
pub const footer = "}" ++ line_ending;

/// Renders a sequence of fragments into a rich text document.
/// `fragments` is a slice of fragments which describe the document,
/// `writer` is a `std.io.Writer` structure that will be the target of the document rendering.
/// The document will be rendered with CR LF line endings.
pub fn render(fragments: []const Fragment, writer: anytype) !void {
    for (fragments) |fragment| {
        switch (fragment) {
            .empty => try writer.writeAll("{\\pard \\ql \\f0 \\sa180 \\li0 \\fi0 \\par}" ++ line_ending),
            .paragraph => |paragraph| try writer.print("{{\\pard \\ql \\f0 \\sa180 \\li0 \\fi0 {}\\par}}" ++ line_ending, .{fmtRtf(paragraph)}),
            .preformatted => |preformatted| {
                try writer.writeAll("{\\pard \\ql \\f0 \\sa180 \\li0 \\fi0 \\f1 ");
                for (preformatted.text.lines) |line, i| {
                    if (i > 0)
                        try writer.writeAll("\\line " ++ line_ending);
                    try writer.print("{}", .{fmtRtf(line)});
                }
                try writer.writeAll("\\par}" ++ line_ending);
            },
            .quote => |quote| {
                try writer.writeAll("{\\pard \\ql \\f0 \\sa180 \\li720 \\fi0 ");
                for (quote.lines) |line, i| {
                    if (i > 0)
                        try writer.writeAll("\\line " ++ line_ending);
                    try writer.print("{}", .{fmtRtf(line)});
                }
                try writer.writeAll("\\par}" ++ line_ending);
            },
            .link => |link| {
                try writer.writeAll("{\\pard \\ql \\f0 \\sa180 \\li0 \\fi0 {\\field{\\*\\fldinst{HYPERLINK \"");
                try writer.print("{}", .{fmtRtf(link.href)});
                try writer.writeAll("\"}}{\\fldrslt{\\ul ");
                if (link.title) |title| {
                    try writer.print("{}", .{fmtRtf(title)});
                } else {
                    try writer.print("{}", .{fmtRtf(link.href)});
                }
                try writer.writeAll("}}}\\par}" ++ line_ending);
            },
            .list => |list| for (list.lines) |line, i| {
                try writer.writeAll("{\\pard \\ql \\f0 \\sa0 \\li360 \\fi-360 \\bullet \\tx360\\tab ");
                try writer.print("{}", .{fmtRtf(line)});
                if (i == list.lines.len - 1) {
                    try writer.writeAll("\\sa180\\par}" ++ line_ending);
                } else {
                    try writer.writeAll("\\par}" ++ line_ending);
                }
            },
            .heading => |heading| {
                switch (heading.level) {
                    .h1 => try writer.print("{{\\pard \\ql \\f0 \\sa180 \\li0 \\fi0 \\b \\fs36 {}\\par}}" ++ line_ending, .{fmtRtf(heading.text)}),
                    .h2 => try writer.print("{{\\pard \\ql \\f0 \\sa180 \\li0 \\fi0 \\b \\fs32 {}\\par}}" ++ line_ending, .{fmtRtf(heading.text)}),
                    .h3 => try writer.print("{{\\pard \\ql \\f0 \\sa180 \\li0 \\fi0 \\b \\fs28 {}\\par}}" ++ line_ending, .{fmtRtf(heading.text)}),
                }
            },
        }
    }
}
