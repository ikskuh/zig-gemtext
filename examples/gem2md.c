//! This example implements a AST based parsing which
//! first reads in the whole file into a document, then
//! renders the parsed document again.

#include <stdio.h>
#include <stdbool.h>
#include "gemtext.h"

void renderToStream(void *ctx, char const *buffer, size_t length)
{
  size_t offset = 0;
  while (offset < length)
  {
    int len = fwrite(buffer + offset, 1, length, (FILE *)ctx);
    if (len < 0)
      return;
    if (len == 0)
      break;
    offset += (size_t)len;
  }
}

int main()
{
  struct gemtext_document document;

  if (gemtextDocumentParseFile(&document, stdin) != GEMTEXT_SUCCESS)
    return 1;

  enum gemtext_error error = gemtextRender(
      GEMTEXT_RENDER_MARKDOWN,
      document.fragments,
      document.fragment_count,
      stdout,
      renderToStream);

  gemtextDocumentDestroy(&document);

  if (error != GEMTEXT_SUCCESS)
    return 1;

  return 0;
}