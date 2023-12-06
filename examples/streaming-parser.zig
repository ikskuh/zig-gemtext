//! This example implements AST construction based
//! on a streaming parser.

const std = @import("std");
const gemtext = @import("gemtext");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var document = gemtext.Document.init(allocator);
    defer document.deinit();

    {
        var parser = gemtext.Parser.init(allocator);
        defer parser.deinit();

        var stream = std.io.getStdIn().reader();

        while (true) {
            var buffer: [1024]u8 = undefined;
            const len = try stream.readAll(&buffer);
            if (len == 0)
                break;

            var offset: usize = 0;
            while (offset < len) {
                var result = try parser.feed(document.arena.allocator(), buffer[offset..len]);
                offset += result.consumed;
                if (result.fragment) |*frag| {
                    try document.fragments.append(frag.*);
                }
            }

            if (try parser.finalize(document.arena.allocator())) |*frag| {
                try document.fragments.append(frag.*);
            }
        }
    }

    try gemtext.renderer.gemtext(
        document.fragments.items,
        std.io.getStdOut().writer(),
    );
}
