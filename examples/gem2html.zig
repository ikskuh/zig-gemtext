const std = @import("std");
const gemtext = @import("gemtext");

pub fn main() !void {
    var document = try gemtext.Document.parse(std.heap.page_allocator, std.io.getStdIn().reader());
    defer document.deinit();

    try gemtext.renderer.html(document.fragments.items, std.io.getStdOut().writer());
}
