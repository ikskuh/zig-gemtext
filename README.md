# Gemini Text Processor

This is a library and a tool to manipulate [gemini text files](https://gemini.circumlunar.space/docs/specification.html).

It provides both an easy-to-use API as well as a streaming parser with minimal allocation requirements and a proper separation between temporary allocations required for parsing and allocations for returned text fragments.

The library is thoroughly tested with a lot of gemini text edge cases and all (tested) are handled reasonably.

## Features

- Fully spec-compliant gemini text parsing
- Non-blocking streaming parser
- Convenient API
- Rendering to several formats
  - Gemini text
  - HTML
  - Markdown
  - RTF

## Example

This is a simple example that parses a gemini file and converts it into a HTML file.

```zig
pub fn main() !void {
    var document = try gemtext.Document.parse(
      std.heap.page_allocator,
      std.io.getStdIn().reader(),
    );
    defer document.deinit();

    try gemtext.renderer.html(
      document.fragments.items, 
      std.io.getStdOut().writer(),
    );
}
```