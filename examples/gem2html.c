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
  char buffer[16384];

  enum gemtext_error err = GEMTEXT_SUCCESS;

  struct gemtext_parser parser;
  if ((err = gemtextParserCreate(&parser)) != GEMTEXT_SUCCESS)
    goto _cleanup_parser;

  struct gemtext_fragment fragment;

  while (true)
  {
    int length = fread(buffer, 1, sizeof buffer, stdin);
    if (length < 0)
      goto _cleanup_parser;
    if (length == 0)
      break;

    size_t offset = 0;
    while (offset < (size_t)length)
    {
      size_t bytes_read;
      err = gemtextParserFeed(&parser, &fragment, &bytes_read, (size_t)length - offset, buffer + offset);
      if (err == GEMTEXT_SUCCESS_FRAGMENT)
      {
        err = gemtextRender(GEMTEXT_RENDER_HTML, &fragment, 1, stdout, renderToStream);
        gemtextParserDestroyFragment(&parser, &fragment);
        if (err != GEMTEXT_SUCCESS)
          goto _cleanup_parser;
      }
      else if (err != GEMTEXT_SUCCESS)
        goto _cleanup_parser;
      offset += bytes_read;
    }
  }
  err = gemtextParserFinalize(&parser, &fragment);
  if (err == GEMTEXT_SUCCESS_FRAGMENT)
  {
    err = gemtextRender(GEMTEXT_RENDER_HTML, &fragment, 1, stdout, renderToStream);
    gemtextParserDestroyFragment(&parser, &fragment);
    if (err != GEMTEXT_SUCCESS)
      goto _cleanup_parser;
  }
  else if (err != GEMTEXT_SUCCESS)
    goto _cleanup_parser;

_cleanup_parser:
  gemtextParserDestroy(&parser);

  if (err != GEMTEXT_SUCCESS)
    return 1;
  return 0;
}