
#include <stdio.h>
#include <chibi/eval.h>

#define SEXP_PORT_BUFFER_SIZE 1024
#define SEXP_LAST_CONTEXT_CHECK_LIMIT 256

#define sexp_cookie_ctx(vec) sexp_vector_ref((sexp)vec, SEXP_ZERO)
#define sexp_cookie_buffer(vec) sexp_vector_ref((sexp)vec, SEXP_ONE)
#define sexp_cookie_read(vec) sexp_vector_ref((sexp)vec, SEXP_TWO)
#define sexp_cookie_write(vec) sexp_vector_ref((sexp)vec, SEXP_THREE)
#define sexp_cookie_seek(vec) sexp_vector_ref((sexp)vec, SEXP_FOUR)
#define sexp_cookie_close(vec) sexp_vector_ref((sexp)vec, SEXP_FIVE)

#if ! SEXP_USE_BOEHM
static int sexp_in_heap_p (sexp_heap h, sexp p) {
  for ( ; h; h = h->next)
    if (((sexp)h < p) && (p < (sexp)((char*)h + h->size)))
      return 1;
  return 0;
}
#endif

static sexp sexp_last_context (sexp ctx, sexp *cstack) {
  sexp res=SEXP_FALSE, p;
#if ! SEXP_USE_BOEHM
  sexp_sint_t i;
  sexp_heap h = sexp_context_heap(ctx);
  for (i=0; i<SEXP_LAST_CONTEXT_CHECK_LIMIT; i++) {
    p = cstack[i];
    if (p && (p != ctx) && sexp_pointerp(p) && sexp_in_heap_p(h, p)
        && (sexp_pointer_tag(p) == SEXP_CONTEXT)
        && (sexp_context_heap(p) == h)) {
      res = p;
      break;
    }
  }
#endif
  return res;
}

static ssize_t sexp_cookie_reader (void *cookie, char *buffer, size_t size) {
  sexp vec = (sexp)cookie, ctx, res;
  if (! sexp_procedurep(sexp_cookie_read(vec))) return -1;
  sexp_gc_var2(ctx2, args);
  ctx = sexp_cookie_ctx(vec);
  ctx2 = sexp_last_context(ctx, (sexp*)&cookie);
  sexp_gc_preserve2(ctx, ctx2, args);
  if (size > sexp_string_length(sexp_cookie_buffer(vec)))
    sexp_cookie_buffer(vec) = sexp_make_string(ctx, sexp_make_fixnum(size), SEXP_VOID);
  args = sexp_list2(ctx, sexp_cookie_buffer(vec), sexp_make_fixnum(size));
  res = sexp_apply(ctx, sexp_cookie_read(vec), args);
  sexp_gc_release2(ctx);
  if (sexp_fixnump(res)) {
    memcpy(buffer, sexp_string_data(sexp_cookie_buffer(vec)), sexp_unbox_fixnum(res));
    return sexp_unbox_fixnum(res);
  } else {
    return -1;
  }
}

static ssize_t sexp_cookie_writer (void *cookie, const char *buffer, size_t size) {
  sexp vec = (sexp)cookie, ctx, res;
  if (! sexp_procedurep(sexp_cookie_write(vec))) return -1;
  sexp_gc_var2(ctx2, args);
  ctx = sexp_cookie_ctx(vec);
  ctx2 = sexp_last_context(ctx, (sexp*)&cookie);
  sexp_gc_preserve2(ctx, ctx2, args);
  if (size > sexp_string_length(sexp_cookie_buffer(vec)))
    sexp_cookie_buffer(vec) = sexp_make_string(ctx, sexp_make_fixnum(size), SEXP_VOID);
  memcpy(sexp_string_data(sexp_cookie_buffer(vec)), buffer, size);
  args = sexp_list2(ctx, sexp_cookie_buffer(vec), sexp_make_fixnum(size));
  res = sexp_apply(ctx, sexp_cookie_write(vec), args);
  sexp_gc_release2(ctx);
  return (sexp_fixnump(res) ? sexp_unbox_fixnum(res) : -1);
}

static int sexp_cookie_seeker (void *cookie, off64_t *position, int whence) {
  sexp vec = (sexp)cookie, ctx, res;
  if (! sexp_procedurep(sexp_cookie_seek(vec))) return -1;
  sexp_gc_var2(ctx2, args);
  ctx = sexp_cookie_ctx(vec);
  ctx2 = sexp_last_context(ctx, (sexp*)&cookie);
  sexp_gc_preserve2(ctx, ctx2, args);
  args = sexp_make_integer(ctx, *position);
  args = sexp_list2(ctx, args, sexp_make_fixnum(whence));
  res = sexp_apply(ctx, sexp_cookie_seek(vec), args);
  if (sexp_fixnump(res))
    *position = sexp_unbox_fixnum(res);
  sexp_gc_release2(ctx);
  return sexp_fixnump(res);
}

static int sexp_cookie_cleaner (void *cookie) {
  sexp vec = (sexp)cookie, ctx, res;
  if (! sexp_procedurep(sexp_cookie_close(vec))) return 0;
  ctx = sexp_cookie_ctx(vec);
  res = sexp_apply(ctx, sexp_cookie_close(vec), SEXP_NULL);
  return (sexp_exceptionp(res) ? -1 : sexp_truep(res));
}

#if ! SEXP_BSD

static cookie_io_functions_t sexp_cookie = {
  .read  = (cookie_read_function_t*)sexp_cookie_reader,
  .write = (cookie_write_function_t*)sexp_cookie_writer,
  .seek  = (cookie_seek_function_t*)sexp_cookie_seeker,
  .close = (cookie_close_function_t*)sexp_cookie_cleaner,
};

static cookie_io_functions_t sexp_cookie_no_seek = {
  .read  = (cookie_read_function_t*)sexp_cookie_reader,
  .write = (cookie_write_function_t*)sexp_cookie_writer,
  .seek  = NULL,
  .close = (cookie_close_function_t*)sexp_cookie_cleaner,
};

#endif

#if SEXP_USE_STRING_STREAMS

static sexp sexp_make_custom_port (sexp ctx, char *mode, sexp read, sexp write,
                                   sexp seek, sexp close) {
  FILE *in;
  sexp res;
  sexp_gc_var1(vec);
  if (sexp_truep(read) && ! sexp_procedurep(read))
    return sexp_type_exception(ctx, "make-custom-port: read not a procedure", read);
  if (sexp_truep(write) && ! sexp_procedurep(write))
    return sexp_type_exception(ctx, "make-custom-port: write not a procedure", write);
  if (sexp_truep(seek) && ! sexp_procedurep(seek))
    return sexp_type_exception(ctx, "make-custom-port: seek not a procedure", seek);
  if (sexp_truep(close) && ! sexp_procedurep(close))
    return sexp_type_exception(ctx, "make-custom-port: close not a procedure", close);
  sexp_gc_preserve1(ctx, vec);
  vec = sexp_make_vector(ctx, SEXP_SIX, SEXP_VOID);
  sexp_cookie_ctx(vec) = ctx;
  sexp_cookie_buffer(vec)
    = sexp_make_string(ctx, sexp_make_fixnum(SEXP_PORT_BUFFER_SIZE), SEXP_VOID);
  sexp_cookie_read(vec) = read;
  sexp_cookie_write(vec) = write;
  sexp_cookie_seek(vec) = seek;
  sexp_cookie_close(vec) = close;
#if SEXP_BSD
  in = funopen(vec,
               (sexp_procedurep(read) ? sexp_cookie_reader : NULL),
               (sexp_procedurep(write) ? sexp_cookie_writer : NULL),
               NULL, /* (sexp_procedurep(seek) ? sexp_cookie_reader : NULL), */
               (sexp_procedurep(close) ? sexp_cookie_cleaner : NULL));
#else
  in = fopencookie(vec, mode, (sexp_truep(seek) ? sexp_cookie : sexp_cookie_no_seek));
#endif
  if (! in) {
    res = sexp_user_exception(ctx, read, "couldn't make custom port", read);
  } else {
    res = sexp_make_input_port(ctx, in, SEXP_FALSE);
    sexp_port_cookie(res) = vec;  /* for gc preserving */
  }
  sexp_gc_release1(ctx);
  return res;
}

#else

static sexp sexp_make_custom_port (sexp ctx, char *mode, sexp read, sexp write,
                                   sexp seek, sexp close) {
  return sexp_user_exception(ctx, SEXP_FALSE, "custom ports not supported in this configuration", SEXP_NULL);
}

#endif

static sexp sexp_make_custom_input_port (sexp ctx, sexp read, sexp seek, sexp close) {
  return sexp_make_custom_port(ctx, "r", read, SEXP_FALSE, seek, close);
}

static sexp sexp_make_custom_output_port (sexp ctx, sexp write, sexp seek, sexp close) {
  sexp res = sexp_make_custom_port(ctx, "w", SEXP_FALSE, write, seek, close);
  sexp_pointer_tag(res) = SEXP_OPORT;
  return res;
}