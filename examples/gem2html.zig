//! This example implements a streaming converter for gemini text to HTML.
//! It reads data indefinitly from stdin and will output each recognized
//! text fragment as soon as possible.

const std = @import("std");
const gemtext = @import("gemtext");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = &gpa.allocator;

    var stream = std.io.getStdIn().reader();

    var buffer: [16384]u8 = undefined;

    var parser = gemtext.Parser.init(allocator);
    defer parser.deinit();

    while (true) {
        const length = try stream.read(&buffer);
        if (length == 0)
            break;

        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();

        var offset: usize = 0;
        while (offset < length) {
            var result = try parser.feed(&arena.allocator, buffer[offset..length]);
            if (result.fragment) |*frag| {
                defer frag.free(&arena.allocator);

                try gemtext.renderer.html(&[_]gemtext.Fragment{frag.*}, std.io.getStdOut().writer());
            }
            offset += result.consumed;
        }
    }
    var frag = try parser.finalize(allocator);
    if (frag) |*frg| {
        defer frg.free(allocator);

        try gemtext.renderer.html(&[_]gemtext.Fragment{frg.*}, std.io.getStdOut().writer());
    }
}
