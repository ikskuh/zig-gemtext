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

fn duplicateFragment(src: c.gemtext_fragment) !c.gemtext_fragment {
    switch (src.type) {
        .GEMTEXT_FRAGMENT_EMPTY => return src,
        .GEMTEXT_FRAGMENT_PARAGRAPH => {
            return c.gemtext_fragment{
                .type = .GEMTEXT_FRAGMENT_PARAGRAPH,
                .unnamed_0 = .{
                    .paragraph = try dupeString(src.unnamed_0.paragraph),
                },
            };
        },
        .GEMTEXT_FRAGMENT_PREFORMATTED => unreachable,
        .GEMTEXT_FRAGMENT_QUOTE => unreachable,
        .GEMTEXT_FRAGMENT_LINK => unreachable,
        .GEMTEXT_FRAGMENT_LIST => unreachable,
        .GEMTEXT_FRAGMENT_HEADING => unreachable,
        else => @panic("Passed an invalid fragment to gemtext!"),
    }
}
fn destroyFragment(fragment: *c.gemtext_fragment) void {
    switch (fragment.type) {
        .GEMTEXT_FRAGMENT_EMPTY => {},
        .GEMTEXT_FRAGMENT_PARAGRAPH => freeString(fragment.unnamed_0.paragraph),
        .GEMTEXT_FRAGMENT_PREFORMATTED => unreachable,
        .GEMTEXT_FRAGMENT_QUOTE => unreachable,
        .GEMTEXT_FRAGMENT_LINK => unreachable,
        .GEMTEXT_FRAGMENT_LIST => unreachable,
        .GEMTEXT_FRAGMENT_HEADING => unreachable,
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
