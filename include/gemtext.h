#ifndef _GEMTEXT_H_
#define _GEMTEXT_H_

#include <stddef.h>

enum gemtext_error
{
  GEMTEXT_SUCCESS = 0,
  GEMTEXT_ERR_OUT_OF_MEMORY = 1,
  GEMTEXT_ERR_OUT_OF_BOUNDS = 2,
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

enum gemtext_heading_level
{
  GEMTEXT_HEADING_H1 = 1,
  GEMTEXT_HEADING_H2 = 1,
  GEMTEXT_HEADING_H3 = 1,
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
  char const *title;
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

#endif // _GEMTEXT_H_
