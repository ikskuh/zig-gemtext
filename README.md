# Gemini Text Processor

This is a library and a tool to manipulate [gemini text files](https://gemini.circumlunar.space/docs/specification.html).

It provides both an easy-to-use API as well as a streaming parser with minimal allocation requirements and a proper separation between temporary allocations required for parsing and allocations for returned text fragments.

The library is thoroughly tested with a lot of gemini text edge cases and all (tested) are handled reasonably.