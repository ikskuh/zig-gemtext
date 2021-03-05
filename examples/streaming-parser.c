//! This example implements AST construction based
//! on a streaming parser.

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

  if (gemtextDocumentCreate(&document) != GEMTEXT_SUCCESS)
    return 1;

  {
    struct gemtext_parser parser;

    if (gemtextParserCreate(&parser) != GEMTEXT_SUCCESS)
    {
      gemtextDocumentDestroy(&document);
      return 1;
    }

    struct gemtext_fragment fragment;

    while (true)
    {
      char buffer[1024];
      int len = fread(buffer, 1, sizeof buffer, stdin);
      if (len < 0)
      {
        gemtextParserDestroy(&parser);
        gemtextDocumentDestroy(&document);
        return 1;
      }
      if (len == 0)
        break;

      size_t offset = 0;
      while (offset < (size_t)len)
      {
        size_t used;

        enum gemtext_error error = gemtextParserFeed(&parser, &fragment, &used, (size_t)len - offset, buffer + offset);

        offset += used;

        if (error == GEMTEXT_SUCCESS_FRAGMENT)
        {
          if (gemtextDocumentAppend(&document, &fragment) != GEMTEXT_SUCCESS)
          {
            gemtextParserDestroyFragment(&parser, &fragment);
            gemtextParserDestroy(&parser);
            gemtextDocumentDestroy(&document);
            return 1;
          }
          gemtextParserDestroyFragment(&parser, &fragment);
        }
        else if (error != GEMTEXT_SUCCESS)
        {
          gemtextParserDestroy(&parser);
          gemtextDocumentDestroy(&document);
          return 1;
        }
      }
    }

    enum gemtext_error error = gemtextParserFinalize(&parser, &fragment);
    if (error == GEMTEXT_SUCCESS_FRAGMENT)
    {
      if (gemtextDocumentAppend(&document, &fragment) != GEMTEXT_SUCCESS)
      {
        gemtextParserDestroyFragment(&parser, &fragment);
        gemtextParserDestroy(&parser);
        gemtextDocumentDestroy(&document);
        return 1;
      }
      gemtextParserDestroyFragment(&parser, &fragment);
    }
    else if (error != GEMTEXT_SUCCESS)
    {
      gemtextParserDestroy(&parser);
      gemtextDocumentDestroy(&document);
      return 1;
    }

    gemtextParserDestroy(&parser);
  }

  enum gemtext_error error = gemtextRender(
      GEMTEXT_RENDER_GEMTEXT,
      document.fragments,
      document.fragment_count,
      stdout,
      renderToStream);

  gemtextDocumentDestroy(&document);

  if (error != GEMTEXT_SUCCESS)
    return 1;

  return 0;
}