//! This example implements a AST based parsing which
//! first reads in the whole file into a document, then
//! renders the parsed document again.

const std = @import("std");
const gemtext = @import("gemtext");

pub fn main() !void {
    var document = try gemtext.Document.parse(std.heap.page_allocator, std.io.getStdIn().reader());
    defer document.deinit();

    try gemtext.renderer.markdown(document.fragments.items, std.io.getStdOut().writer());
}
