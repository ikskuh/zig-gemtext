#ifndef _GEMTEXT_H_
#define _GEMTEXT_H_

#include <stddef.h>
#include <stdalign.h>

enum gemtext_error
{
  /// The operation was successful.
  GEMTEXT_SUCCESS = 0,

  /// The same as `GEMTEXT_SUCCESS`, but indicates that the `fragment` variable
  /// was initialized.
  /// Only valid for `gemtextParserFeed` and `gemtextParserFinalize`.
  GEMTEXT_SUCCESS_FRAGMENT = 1,

  /// The operation failed due to a lack of memory.
  GEMTEXT_ERR_OUT_OF_MEMORY = -1,

  /// The operation failed as a given index was out of bounds.
  GEMTEXT_ERR_OUT_OF_BOUNDS = -2,
};

enum gemtext_fragment_type
{
  GEMTEXT_FRAGMENT_EMPTY = 0,
  GEMTEXT_FRAGMENT_PARAGRAPH = 1,
  GEMTEXT_FRAGMENT_PREFORMATTED = 2,
  GEMTEXT_FRAGMENT_QUOTE = 3,
  GEMTEXT_FRAGMENT_LINK = 4,
  GEMTEXT_FRAGMENT_LIST = 5,
  GEMTEXT_FRAGMENT_HEADING = 6,
};

enum gemtext_renderer
{
  /// Renders canonical gemini text
  GEMTEXT_RENDER_GEMTEXT = 0,

  /// Renders the gemini text as HTML.
  GEMTEXT_RENDER_HTML = 1,

  /// Renders the gemini text as commonmark markdown.
  GEMTEXT_RENDER_MARKDOWN = 2,

  /// Renders the gemini text as rich text.
  GEMTEXT_RENDER_RTF = 3,
};

enum gemtext_heading_level
{
  GEMTEXT_HEADING_H1 = 1,
  GEMTEXT_HEADING_H2 = 2,
  GEMTEXT_HEADING_H3 = 3,
};

struct gemtext_lines
{
  size_t count;
  char const *const *lines;
};

struct gemtext_preformatted
{
  struct gemtext_lines lines;
  char const *alt_text; // can be NULL
};

struct gemtext_link
{
  char const *href;
  char const *title; // can be NULL
};

struct gemtext_heading
{
  char const *text;
  enum gemtext_heading_level level;
};

struct gemtext_fragment
{
  enum gemtext_fragment_type type;
  union
  {
    char const *paragraph;
    struct gemtext_preformatted preformatted;
    struct gemtext_lines quote;
    struct gemtext_link link;
    struct gemtext_lines list;
    struct gemtext_heading heading;
  };
};

struct gemtext_document
{
  size_t fragment_count;
  struct gemtext_fragment const *fragments;
};

struct gemtext_parser
{
  // KEEP THIS IN SYNC WITH THE ASSERT IN src/gemtext.zig:Parser!
  alignas(16) char opaque[128];
};

/// Initializes the `document`.
enum gemtext_error gemtextDocumentCreate(struct gemtext_document *document);

/// Inserts a `fragment` at `index` in `document`.
enum gemtext_error gemtextDocumentInsert(struct gemtext_document *document, size_t index, struct gemtext_fragment const *fragment);

/// Appends a `fragment` at the end to `document`.
enum gemtext_error gemtextDocumentAppend(struct gemtext_document *document, struct gemtext_fragment const *fragment);

/// Removes a fragment from `document` at `index`.
void gemtextDocumentRemove(struct gemtext_document *document, size_t index);

/// Destroys the `document` and all contained resources.
void gemtextDocumentDestroy(struct gemtext_document *document);

/// Initializes `parser`.
enum gemtext_error gemtextParserCreate(struct gemtext_parser *parser);

/// Destroys `parser` and all contained resources.
void gemtextParserDestroy(struct gemtext_parser *parser);

/// Feeds a sequence of `bytes` into the parser and returns
/// the number of `consumed_bytes` to the caller. This sequence is `total_bytes` long.
/// If a `fragment` was parsed, returns `GEMTEXT_SUCCESS_FRAGMENT`
/// and the variable `fragment` was initialized by the parser to a valid value.
/// If `consumed_bytes` is less than `total_bytes`, the parser has not consumed
/// all bytes in the input sequence and the caller should process the returned fragment,
/// then feed the rest of the bytes into the parser.
/// If a `fragment` was returned, it must be freed with `gemtextParserDestroyFragment`.
enum gemtext_error gemtextParserFeed(
    struct gemtext_parser *parser,
    struct gemtext_fragment *fragment,
    size_t *consumed_bytes,
    size_t total_bytes,
    char const *bytes);

/// Tells the parser that we finished the current file and will flush all internal
/// buffers.
/// If `GEMTEXT_SUCCESS_FRAGMENT` is returned, `fragment` will be valid and must be
/// freed with `gemtextParserDestroyFragment`.
enum gemtext_error gemtextParserFinalize(
    struct gemtext_parser *parser,
    struct gemtext_fragment *fragment);

/// Destroys a `fragment` returned by `gemtextParserFeed()` or `gemtextParserFinalize()`. `parser` is the
/// associated parser that was passed into `gemtextParserFeed()` or `gemtextParserFinalize()`.
void gemtextParserDestroyFragment(
    struct gemtext_parser *parser,
    struct gemtext_fragment *fragment);

/// Renders a sequence of `fragments` with the selected `renderer`.
/// Every time text is emitted, `render` is called with
/// both the `context` parameter passed verbatim into the callback
/// as well as a sequence of `bytes` with the given `length`.
enum gemtext_error gemtextRender(
    enum gemtext_renderer renderer,
    struct gemtext_fragment const *fragments,
    size_t fragment_count,
    void *context,
    void (*render)(void *context, char const *bytes, size_t length));

#endif // _GEMTEXT_H_
