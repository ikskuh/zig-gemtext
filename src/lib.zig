const std = @import("std");
const gemini = @import("gemtext.zig");

const c = @cImport({
    @cInclude("gemtext.h");
});

const allocator = if (std.builtin.is_test)
    std.testing.allocator
else
    std.heap.c_allocator;

const Error = error{
    OutOfMemory,
};

fn errorToC(err: Error) c.gemtext_error {
    return switch (err) {
        error.OutOfMemory => return .GEMTEXT_ERR_OUT_OF_MEMORY,
    };
}

fn getFragments(document: *c.gemtext_document) []c.gemtext_fragment {
    var result: []c.gemtext_fragment = undefined;

    if (document.fragment_count > 0) {
        // we can safely remove `const` here as we've allocated this memory ourselves and
        // know that it's mutable!
        result = @intToPtr([*]c.gemtext_fragment, @ptrToInt(document.fragments))[0..document.fragment_count];
    } else {
        result = std.mem.zeroes([]c.gemtext_fragment);
    }
    return result;
}

fn setFragments(document: *c.gemtext_document, slice: []c.gemtext_fragment) void {
    document.fragment_count = slice.len;
    document.fragments = slice.ptr;
}

fn dupeString(src: [*:0]const u8) ![*:0]u8 {
    return (try allocator.dupeZ(u8, std.mem.span(src))).ptr;
}

fn freeString(src: [*:0]const u8) void {
    allocator.free(std.mem.spanZ(@intToPtr([*:0]u8, @ptrToInt(src))));
}

fn dupeLines(src_lines: c.gemtext_lines) !c.gemtext_lines {
    const lines = try allocator.alloc([*c]const u8, src_lines.count);
    errdefer allocator.free(lines);

    var offset: usize = 0;
    errdefer for (lines[0..offset]) |line|
        allocator.free(std.mem.spanZ(line));

    while (offset < lines.len) : (offset += 1) {
        lines[offset] = (try allocator.dupeZ(u8, std.mem.spanZ(src_lines.lines[offset]))).ptr;
    }
    return c.gemtext_lines{
        .count = lines.len,
        .lines = lines.ptr,
    };
}

fn duplicateFragment(src: c.gemtext_fragment) !c.gemtext_fragment {
    return switch (src.type) {
        .GEMTEXT_FRAGMENT_EMPTY => return src,
        .GEMTEXT_FRAGMENT_PARAGRAPH => c.gemtext_fragment{
            .type = .GEMTEXT_FRAGMENT_PARAGRAPH,
            .unnamed_0 = .{
                .paragraph = try dupeString(src.unnamed_0.paragraph),
            },
        },
        .GEMTEXT_FRAGMENT_PREFORMATTED => blk: {
            var container = c.gemtext_fragment{
                .type = .GEMTEXT_FRAGMENT_PREFORMATTED,
                .unnamed_0 = .{
                    .preformatted = .{
                        .lines = undefined,
                        .alt_text = undefined,
                    },
                },
            };

            container.unnamed_0.preformatted.lines = try dupeLines(src.unnamed_0.preformatted.lines);
            errdefer destroyLines(&container.unnamed_0.preformatted.lines);

            container.unnamed_0.preformatted.alt_text = if (src.unnamed_0.preformatted.alt_text) |alt_text|
                try dupeString(alt_text)
            else
                null;

            break :blk container;
        },
        .GEMTEXT_FRAGMENT_QUOTE => c.gemtext_fragment{
            .type = .GEMTEXT_FRAGMENT_QUOTE,
            .unnamed_0 = .{
                .quote = try dupeLines(src.unnamed_0.quote),
            },
        },
        .GEMTEXT_FRAGMENT_LINK => blk: {
            var container = c.gemtext_fragment{
                .type = .GEMTEXT_FRAGMENT_LINK,
                .unnamed_0 = .{
                    .link = .{
                        .href = undefined,
                        .title = undefined,
                    },
                },
            };

            container.unnamed_0.link.href = try dupeString(src.unnamed_0.link.href);
            errdefer freeString(container.unnamed_0.link.href);

            container.unnamed_0.link.title = if (src.unnamed_0.link.title) |title|
                try dupeString(title)
            else
                null;

            break :blk container;
        },
        .GEMTEXT_FRAGMENT_LIST => c.gemtext_fragment{
            .type = .GEMTEXT_FRAGMENT_LIST,
            .unnamed_0 = .{
                .list = try dupeLines(src.unnamed_0.list),
            },
        },
        .GEMTEXT_FRAGMENT_HEADING => c.gemtext_fragment{
            .type = .GEMTEXT_FRAGMENT_HEADING,
            .unnamed_0 = .{
                .heading = .{
                    .level = src.unnamed_0.heading.level,
                    .text = try dupeString(src.unnamed_0.paragraph),
                },
            },
        },
        else => @panic("Passed an invalid fragment to gemtext!"),
    };
}

fn destroyLines(src_lines: *c.gemtext_lines) void {
    if (src_lines.count > 0) {
        const lines = src_lines.lines[0..src_lines.count];
        for (lines) |line| {
            allocator.free(std.mem.spanZ(line));
        }
        allocator.free(lines);
    }
}

fn destroyFragment(fragment: *c.gemtext_fragment) void {
    switch (fragment.type) {
        .GEMTEXT_FRAGMENT_EMPTY => {},
        .GEMTEXT_FRAGMENT_PARAGRAPH => freeString(fragment.unnamed_0.paragraph),
        .GEMTEXT_FRAGMENT_PREFORMATTED => {
            if (fragment.unnamed_0.preformatted.alt_text) |alt|
                freeString(alt);
            destroyLines(&fragment.unnamed_0.preformatted.lines);
        },
        .GEMTEXT_FRAGMENT_QUOTE => destroyLines(&fragment.unnamed_0.quote),
        .GEMTEXT_FRAGMENT_LINK => {
            if (fragment.unnamed_0.link.title) |title|
                freeString(title);
            freeString(fragment.unnamed_0.link.href);
        },
        .GEMTEXT_FRAGMENT_LIST => destroyLines(&fragment.unnamed_0.list),
        .GEMTEXT_FRAGMENT_HEADING => freeString(fragment.unnamed_0.heading.text),
        else => @panic("Passed an invalid fragment to gemtext!"),
    }
    fragment.* = undefined;
}

export fn gemtextDocumentCreate(document: *c.gemtext_document) c.gemtext_error {
    document.* = .{
        .fragment_count = undefined,
        .fragments = undefined,
    };

    setFragments(document, allocator.alloc(c.gemtext_fragment, 0) catch |e| return errorToC(e));

    return .GEMTEXT_SUCCESS;
}

fn debugPrintFragment(comptime header: []const u8, fragment: c.gemtext_fragment) void {
    std.debug.print(header, .{});
    switch (fragment.type) {
        .GEMTEXT_FRAGMENT_EMPTY => std.debug.print(" GEMTEXT_FRAGMENT_EMPTY\n", .{}),
        .GEMTEXT_FRAGMENT_PARAGRAPH => std.debug.print(" GEMTEXT_FRAGMENT_PARAGRAPH => {s}\n", .{fragment.unnamed_0.paragraph}),
        .GEMTEXT_FRAGMENT_PREFORMATTED => std.debug.print(" GEMTEXT_FRAGMENT_PREFORMATTED => {}\n", .{fragment.unnamed_0.preformatted}),
        .GEMTEXT_FRAGMENT_QUOTE => std.debug.print(" GEMTEXT_FRAGMENT_QUOTE => {}\n", .{fragment.unnamed_0.quote}),
        .GEMTEXT_FRAGMENT_LINK => std.debug.print(" GEMTEXT_FRAGMENT_LINK => {}\n", .{fragment.unnamed_0.link}),
        .GEMTEXT_FRAGMENT_LIST => std.debug.print(" GEMTEXT_FRAGMENT_LIST => {}\n", .{fragment.unnamed_0.list}),
        .GEMTEXT_FRAGMENT_HEADING => std.debug.print(" GEMTEXT_FRAGMENT_HEADING => {}\n", .{fragment.unnamed_0.heading}),
        else => unreachable,
    }
}

export fn gemtextDocumentInsert(document: *c.gemtext_document, index: usize, fragment: *const c.gemtext_fragment) c.gemtext_error {
    var fragments = getFragments(document);
    defer setFragments(document, fragments);

    if (index > fragments.len)
        return .GEMTEXT_ERR_OUT_OF_BOUNDS;

    var fragment_dupe = duplicateFragment(fragment.*) catch |e| return errorToC(e);

    fragments = allocator.realloc(fragments, fragments.len + 1) catch |e| {
        destroyFragment(&fragment_dupe);
        return errorToC(e);
    };

    const shift_count = fragments.len - index;
    if (shift_count > 0) {
        std.mem.copyBackwards(
            c.gemtext_fragment,
            fragments[index + 1 .. fragments.len],
            fragments[index .. fragments.len - 1],
        );
    }

    fragments[index] = fragment_dupe;

    return .GEMTEXT_SUCCESS;
}

export fn gemtextDocumentAppend(document: *c.gemtext_document, fragment: *const c.gemtext_fragment) c.gemtext_error {
    return gemtextDocumentInsert(document, document.fragment_count, fragment);
}

export fn gemtextDocumentRemove(document: *c.gemtext_document, index: usize) void {
    var fragments = getFragments(document);
    defer setFragments(document, fragments);

    if (index > fragments.len)
        return;

    destroyFragment(&fragments[index]);

    const shift_count = document.fragment_count - index;
    if (shift_count > 0) {
        std.mem.copy(
            c.gemtext_fragment,
            fragments[index .. fragments.len - 1],
            fragments[index + 1 .. fragments.len],
        );
    }

    fragments = allocator.shrink(fragments, fragments.len - 1);
}

export fn gemtextDocumentDestroy(document: *c.gemtext_document) void {
    const fragments = getFragments(document);
    for (fragments) |*frag| {
        destroyFragment(frag);
    }
    allocator.free(fragments);
    document.* = undefined;
}

export fn gemtextParserCreate(raw_parser: *c.gemtext_parser) c.gemtext_error {
    const parser = @ptrCast(*gemini.Parser, raw_parser);
    parser.* = gemini.Parser.init(allocator);
    return .GEMTEXT_SUCCESS;
}

export fn gemtextParserDestroy(raw_parser: *c.gemtext_parser) void {
    const parser = @ptrCast(*gemini.Parser, raw_parser);
    parser.deinit();
    raw_parser.* = undefined;
}

fn ensureCString(str: [*:0]const u8) [*:0]const u8 {
    return str;
}

/// Converts a TextLines element to a c.gemtext_lines and destroys
/// the `.lines` array of TextLines on the way. If the conversion fails,
/// the `.lines` is kept alive.
fn convertTextLinesToC(src_lines: *gemini.TextLines) !c.gemtext_lines {
    const lines = try allocator.alloc([*:0]const u8, src_lines.lines.len);
    for (lines) |*line, i| {
        line.* = src_lines.lines[i].ptr;
    }

    allocator.free(src_lines.lines);
    src_lines.* = undefined;

    return c.gemtext_lines{
        .count = lines.len,
        .lines = @ptrCast([*][*c]const u8, lines),
    };
}

fn convertFragmentToC(fragment: *gemini.Fragment) !c.gemtext_fragment {
    return switch (fragment.*) {
        .empty => |empty| c.gemtext_fragment{
            .type = .GEMTEXT_FRAGMENT_EMPTY,
            .unnamed_0 = undefined,
        },
        .paragraph => |paragraph| c.gemtext_fragment{
            .type = .GEMTEXT_FRAGMENT_PARAGRAPH,
            .unnamed_0 = .{
                .paragraph = ensureCString(paragraph.ptr),
            },
        },
        .preformatted => |*preformatted| c.gemtext_fragment{
            .type = .GEMTEXT_FRAGMENT_PREFORMATTED,
            .unnamed_0 = .{
                .preformatted = .{
                    .alt_text = if (preformatted.alt_text) |alt_text|
                        ensureCString(alt_text.ptr)
                    else
                        null,
                    .lines = try convertTextLinesToC(&preformatted.text),
                },
            },
        },
        .quote => |*quote| c.gemtext_fragment{
            .type = .GEMTEXT_FRAGMENT_QUOTE,
            .unnamed_0 = .{
                .quote = try convertTextLinesToC(quote),
            },
        },
        .link => |link| c.gemtext_fragment{
            .type = .GEMTEXT_FRAGMENT_LINK,
            .unnamed_0 = .{
                .link = .{
                    .href = ensureCString(link.href.ptr),
                    .title = if (link.title) |title|
                        ensureCString(title)
                    else
                        null,
                },
            },
        },
        .list => |*list| c.gemtext_fragment{
            .type = .GEMTEXT_FRAGMENT_LIST,
            .unnamed_0 = .{
                .list = try convertTextLinesToC(list),
            },
        },
        .heading => |heading| c.gemtext_fragment{
            .type = .GEMTEXT_FRAGMENT_HEADING,
            .unnamed_0 = .{
                .heading = .{
                    .level = switch (heading.level) {
                        .h1 => c.gemtext_heading_level.GEMTEXT_HEADING_H1,
                        .h2 => c.gemtext_heading_level.GEMTEXT_HEADING_H2,
                        .h3 => c.gemtext_heading_level.GEMTEXT_HEADING_H3,
                    },
                    .text = ensureCString(heading.text.ptr),
                },
            },
        },
    };
}

export fn gemtextParserFeed(
    raw_parser: *c.gemtext_parser,
    out_fragment: *c.gemtext_fragment,
    consumed_bytes: *usize,
    total_bytes: usize,
    bytes: [*]const u8,
) c.gemtext_error {
    const parser = @ptrCast(*gemini.Parser, raw_parser);

    const input_slice = bytes[0..total_bytes];
    var result = parser.feed(allocator, input_slice) catch |e| return errorToC(e);

    consumed_bytes.* = result.consumed;
    if (result.fragment) |*fragment| {
        // as we used c_allocator, we can just return a "flat" copy of the gemini.Fragment here
        out_fragment.* = convertFragmentToC(fragment) catch |e| {
            fragment.free(allocator);
            return errorToC(e);
        };
        return .GEMTEXT_SUCCESS_FRAGMENT;
    } else {
        out_fragment.* = undefined;
        return .GEMTEXT_SUCCESS;
    }
}

export fn gemtextParserFinalize(
    raw_parser: *c.gemtext_parser,
    out_fragment: *c.gemtext_fragment,
) c.gemtext_error {
    const parser = @ptrCast(*gemini.Parser, raw_parser);

    var result = parser.finalize(allocator) catch |e| return errorToC(e);

    if (result) |*fragment| {
        // as we used c_allocator, we can just return a "flat" copy of the gemini.Fragment here
        out_fragment.* = convertFragmentToC(fragment) catch |e| {
            fragment.free(allocator);
            return errorToC(e);
        };
        return .GEMTEXT_SUCCESS_FRAGMENT;
    } else {
        out_fragment.* = undefined;
        return .GEMTEXT_SUCCESS;
    }
}

export fn gemtextParserDestroyFragment(
    parser: *c.gemtext_parser,
    fragment: *c.gemtext_fragment,
) void {
    _ = parser; // we ignore the parser for this, it's just here for future safety
    destroyFragment(fragment);
}

const CStream = struct {
    const Self = @This();

    context: ?*c_void,
    render: fn (ctx: ?*c_void, bytes: [*]const u8, length: usize) callconv(.C) void,

    const Error = error{};
    const Writer = std.io.Writer(Self, Error, write);

    pub fn writer(self: Self) Writer {
        return Writer{ .context = self };
    }

    fn write(self: Self, slice: []const u8) Error!usize {
        self.render(self.context, slice.ptr, slice.len);
        return slice.len;
    }
};

fn convertTextLinesToZig(src_lines: c.gemtext_lines) !gemini.TextLines {
    var lines = try allocator.alloc([:0]const u8, src_lines.count);
    errdefer allocator.free(lines);

    var offset: usize = 0;

    errdefer for (lines[0..offset]) |frag|
        allocator.free(frag);

    while (offset < lines.len) : (offset += 1) {
        lines[offset] = try allocator.dupeZ(u8, std.mem.spanZ(src_lines.lines[offset]));
    }

    return gemini.TextLines{
        .lines = lines,
    };
}

fn convertFragmentToZig(src_fragment: c.gemtext_fragment) !gemini.Fragment {
    return switch (src_fragment.type) {
        .GEMTEXT_FRAGMENT_EMPTY => gemini.Fragment{ .empty = {} },
        .GEMTEXT_FRAGMENT_PARAGRAPH => gemini.Fragment{
            .paragraph = try allocator.dupeZ(u8, std.mem.spanZ(src_fragment.unnamed_0.paragraph)),
        },
        .GEMTEXT_FRAGMENT_PREFORMATTED => blk: {
            var pre = gemini.Preformatted{
                .text = undefined,
                .alt_text = if (src_fragment.unnamed_0.preformatted.alt_text) |alt_text|
                    try allocator.dupeZ(u8, std.mem.spanZ(alt_text))
                else
                    null,
            };
            defer if (pre.alt_text) |alt_text|
                allocator.free(alt_text);

            pre.text = try convertTextLinesToZig(src_fragment.unnamed_0.preformatted.lines);

            break :blk gemini.Fragment{
                .preformatted = pre,
            };
        },
        .GEMTEXT_FRAGMENT_QUOTE => gemini.Fragment{
            .quote = try convertTextLinesToZig(src_fragment.unnamed_0.quote),
        },
        .GEMTEXT_FRAGMENT_LINK => blk: {
            var link = gemini.Link{
                .title = null,
                .href = try allocator.dupeZ(u8, std.mem.spanZ(src_fragment.unnamed_0.link.href)),
            };
            errdefer allocator.free(link.href);

            link.title = if (src_fragment.unnamed_0.link.title) |title|
                try allocator.dupeZ(u8, std.mem.spanZ(title))
            else
                null;

            break :blk gemini.Fragment{ .link = link };
        },
        .GEMTEXT_FRAGMENT_LIST => gemini.Fragment{
            .list = try convertTextLinesToZig(src_fragment.unnamed_0.list),
        },
        .GEMTEXT_FRAGMENT_HEADING => gemini.Fragment{
            .heading = .{
                .text = try allocator.dupeZ(u8, std.mem.spanZ(src_fragment.unnamed_0.heading.text)),
                .level = switch (src_fragment.unnamed_0.heading.level) {
                    .GEMTEXT_HEADING_H1 => .h1,
                    .GEMTEXT_HEADING_H2 => .h2,
                    .GEMTEXT_HEADING_H3 => .h3,
                    else => @panic("passed invalid fragment to gemtext!"),
                },
            },
        },
        else => @panic("passed invalid fragment to gemtext!"),
    };
}

export fn gemtextRender(
    renderer: c.gemtext_renderer,
    raw_fragments: [*]const c.gemtext_fragment,
    fragment_count: usize,
    context: ?*c_void,
    render: fn (ctx: ?*c_void, bytes: [*]const u8, length: usize) callconv(.C) void,
) c.gemtext_error {
    var stream = CStream{
        .context = context,
        .render = render,
    };

    var fragments = allocator.alloc(gemini.Fragment, fragment_count) catch |e| return errorToC(e);
    defer allocator.free(fragments);

    var offset: usize = 0;

    defer for (fragments[0..offset]) |*frag|
        frag.free(allocator);

    while (offset < fragments.len) : (offset += 1) {
        fragments[offset] = convertFragmentToZig(raw_fragments[offset]) catch |e| return errorToC(e);
    }

    switch (renderer) {
        .GEMTEXT_RENDER_GEMTEXT => gemini.renderer.gemtext(fragments, stream.writer()) catch unreachable,
        .GEMTEXT_RENDER_HTML => gemini.renderer.html(fragments, stream.writer()) catch unreachable,
        .GEMTEXT_RENDER_MARKDOWN => gemini.renderer.markdown(fragments, stream.writer()) catch unreachable,
        .GEMTEXT_RENDER_RTF => gemini.renderer.rtf(fragments, stream.writer()) catch unreachable,
        else => @panic("invalid renderer passed to gemtextRender!"),
    }

    return .GEMTEXT_SUCCESS;
}

test "empty document creation/deletion" {
    var doc: c.gemtext_document = undefined;

    std.testing.expectEqual(c.gemtext_error.GEMTEXT_SUCCESS, c.gemtextDocumentCreate(&doc));
    c.gemtextDocumentDestroy(&doc);
}

test "basic document interface" {
    var doc: c.gemtext_document = undefined;

    std.testing.expectEqual(c.gemtext_error.GEMTEXT_SUCCESS, c.gemtextDocumentCreate(&doc));
    defer c.gemtextDocumentDestroy(&doc);

    var temp_buffer = "Line 2".*;

    std.testing.expectEqual(c.gemtext_error.GEMTEXT_SUCCESS, c.gemtextDocumentAppend(&doc, &c.gemtext_fragment{
        .type = .GEMTEXT_FRAGMENT_PARAGRAPH,
        .unnamed_0 = .{ .paragraph = &temp_buffer },
    }));

    temp_buffer = "Line 1".*;
    std.testing.expectEqual(c.gemtext_error.GEMTEXT_SUCCESS, c.gemtextDocumentInsert(&doc, 0, &c.gemtext_fragment{
        .type = .GEMTEXT_FRAGMENT_PARAGRAPH,
        .unnamed_0 = .{ .paragraph = &temp_buffer },
    }));

    temp_buffer = "Line 3".*;
    std.testing.expectEqual(c.gemtext_error.GEMTEXT_SUCCESS, c.gemtextDocumentInsert(&doc, 2, &c.gemtext_fragment{
        .type = .GEMTEXT_FRAGMENT_PARAGRAPH,
        .unnamed_0 = .{ .paragraph = &temp_buffer },
    }));
    temp_buffer = undefined;

    std.testing.expectEqual(@as(usize, 3), doc.fragment_count);

    std.testing.expectEqual(c.gemtext_fragment_type.GEMTEXT_FRAGMENT_PARAGRAPH, doc.fragments[0].type);
    std.testing.expectEqual(c.gemtext_fragment_type.GEMTEXT_FRAGMENT_PARAGRAPH, doc.fragments[1].type);
    std.testing.expectEqual(c.gemtext_fragment_type.GEMTEXT_FRAGMENT_PARAGRAPH, doc.fragments[2].type);

    std.testing.expectEqualStrings("Line 1", std.mem.span(doc.fragments[0].unnamed_0.paragraph));
    std.testing.expectEqualStrings("Line 2", std.mem.span(doc.fragments[1].unnamed_0.paragraph));
    std.testing.expectEqualStrings("Line 3", std.mem.span(doc.fragments[2].unnamed_0.paragraph));

    c.gemtextDocumentRemove(&doc, 1);

    std.testing.expectEqual(@as(usize, 2), doc.fragment_count);

    std.testing.expectEqual(c.gemtext_fragment_type.GEMTEXT_FRAGMENT_PARAGRAPH, doc.fragments[0].type);
    std.testing.expectEqual(c.gemtext_fragment_type.GEMTEXT_FRAGMENT_PARAGRAPH, doc.fragments[1].type);

    std.testing.expectEqualStrings("Line 1", std.mem.span(doc.fragments[0].unnamed_0.paragraph));
    std.testing.expectEqualStrings("Line 3", std.mem.span(doc.fragments[1].unnamed_0.paragraph));
}

test "empty parser creation/deletion" {
    var parser: c.gemtext_parser = undefined;

    std.testing.expectEqual(c.gemtext_error.GEMTEXT_SUCCESS, c.gemtextParserCreate(&parser));
    c.gemtextParserDestroy(&parser);
}

fn terminateWithCrLf(comptime input_literal: [:0]const u8) [:0]const u8 {
    @setEvalBranchQuota(20 * input_literal.len);
    comptime var result: [:0]const u8 = "";
    comptime var iter = std.mem.split(input_literal, "\n");
    inline while (comptime iter.next()) |line| {
        result = result ++ line ++ "\r\n";
    }
    return result;
}

test "basic parser invocation and document building, also rendering" {
    var parser: c.gemtext_parser = undefined;
    var document: c.gemtext_document = undefined;

    std.testing.expectEqual(c.gemtext_error.GEMTEXT_SUCCESS, c.gemtextParserCreate(&parser));
    defer c.gemtextParserDestroy(&parser);

    std.testing.expectEqual(c.gemtext_error.GEMTEXT_SUCCESS, c.gemtextDocumentCreate(&document));
    defer c.gemtextDocumentDestroy(&document);

    const document_text: []const u8 = terminateWithCrLf(@embedFile("../test-data/features.gemini"));

    var fragment: c.gemtext_fragment = undefined;

    var offset: usize = 0;
    while (offset < document_text.len) {
        var parsed_len: usize = undefined;

        var result = c.gemtextParserFeed(
            &parser,
            &fragment,
            &parsed_len,
            document_text.len - offset,
            document_text.ptr + offset,
        );

        std.testing.expect(result == .GEMTEXT_SUCCESS or result == .GEMTEXT_SUCCESS_FRAGMENT);

        offset += parsed_len;

        if (result == .GEMTEXT_SUCCESS_FRAGMENT) {
            std.testing.expectEqual(c.gemtext_error.GEMTEXT_SUCCESS, c.gemtextDocumentAppend(&document, &fragment));

            c.gemtextParserDestroyFragment(&parser, &fragment);
        }
    }
    {
        var result = c.gemtextParserFinalize(&parser, &fragment);
        std.testing.expect(result == .GEMTEXT_SUCCESS or result == .GEMTEXT_SUCCESS_FRAGMENT);
        if (result == .GEMTEXT_SUCCESS_FRAGMENT) {
            std.testing.expectEqual(c.gemtext_error.GEMTEXT_SUCCESS, c.gemtextDocumentAppend(&document, &fragment));
            c.gemtextParserDestroyFragment(&parser, &fragment);
        }
    }

    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();

    std.testing.expectEqual(c.gemtext_error.GEMTEXT_SUCCESS, c.gemtextRender(
        .GEMTEXT_RENDER_GEMTEXT,
        document.fragments,
        document.fragment_count,
        &list,
        struct {
            fn f(ctx: ?*c_void, text: [*c]const u8, len: usize) callconv(.C) void {
                var sublist = std.meta.cast(*std.ArrayList(u8), ctx.?);
                sublist.appendSlice(text[0..len]) catch unreachable;
            }
        }.f,
    ));

    std.testing.expectEqualStrings(document_text, list.items);
}
