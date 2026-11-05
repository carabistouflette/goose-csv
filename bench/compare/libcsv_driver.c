/* SPDX-License-Identifier: Apache-2.0 */
/* Benchmark adapter only; links an independently pinned LGPL libcsv source. */
#define _POSIX_C_SOURCE 200809L
#include "csv.h"
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#define MOD UINT64_C(2147483647)
#define CAP (32u * 1024u * 1024u)
typedef struct {
  unsigned char *p;
  size_t n;
} Bytes;
typedef struct {
  Bytes *fields;
  size_t n;
} InputRow;
typedef struct {
  unsigned char *data;
  size_t len, cap;
  size_t *ends, n, ecap;
  uint64_t rows, bytes, checksum;
  int dump;
} State;
static void require(int yes) {
  if (!yes) {
    fputs("comparison adapter invariant failed\n", stderr);
    exit(2);
  }
}
static void *alloc(void *p, size_t n) {
  require(n <= CAP);
  void *q = realloc(p, n ? n : 1);
  require(q != NULL);
  return q;
}
static uint64_t now(void) {
  struct timespec t;
  require(clock_gettime(CLOCK_MONOTONIC, &t) == 0);
  return (uint64_t)t.tv_sec * UINT64_C(1000000000) + (uint64_t)t.tv_nsec;
}
static uint64_t mix(uint64_t a, uint64_t b) { return (a * 257 + b + 1) % MOD; }
static void hex(const unsigned char *p, size_t n) {
  if (!n) {
    putchar('-');
    return;
  }
  for (size_t i = 0; i < n; i++)
    printf("%02x", p[i]);
}
static uint64_t field_sig(uint64_t value, const unsigned char *p, size_t n) {
  value = mix(value, n);
  if (n) {
    value = mix(value, p[0]);
    value = mix(value, p[n / 2]);
    value = mix(value, p[n - 1]);
  }
  return value;
}
static uint64_t wire_sig(const unsigned char *p, size_t n) {
  uint64_t s = n;
  if (n) {
    s = mix(s, p[0]);
    s = mix(s, p[n / 2]);
    s = mix(s, p[n - 1]);
  }
  return s;
}
static void field_cb(void *p, size_t n, void *opaque) {
  State *s = opaque;
  require(n <= CAP - s->len && s->n < 65536);
  if (s->len + n > s->cap) {
    size_t cap = s->cap ? s->cap : 4096;
    while (cap < s->len + n) {
      require(cap <= CAP / 2);
      cap *= 2;
    }
    s->data = alloc(s->data, cap);
    s->cap = cap;
  }
  if (n)
    memcpy(s->data + s->len, p, n);
  s->len += n;
  if (s->n == s->ecap) {
    s->ecap = s->ecap ? s->ecap * 2 : 32;
    s->ends = alloc(s->ends, s->ecap * sizeof(*s->ends));
  }
  s->ends[s->n++] = s->len;
}
static void row_cb(int ending, void *opaque) {
  (void)ending;
  State *s = opaque;
  uint64_t value = s->n;
  size_t begin = 0;
  if (s->dump)
    printf("R %zu", s->n);
  for (size_t i = 0; i < s->n; i++) {
    size_t n = s->ends[i] - begin;
    const unsigned char *p =
        s->data ? s->data + begin : (const unsigned char *)"";
    value = field_sig(value, p, n);
    if (s->dump) {
      putchar(' ');
      hex(p, n);
    }
    begin = s->ends[i];
  }
  if (s->dump)
    putchar('\n');
  s->rows++;
  s->checksum = (s->checksum + value) % MOD;
  s->n = 0;
  s->len = 0;
}
static int no_space(unsigned char c) {
  (void)c;
  return 0;
}
static Bytes load(const char *name) {
  FILE *f = fopen(name, "rb");
  require(f != NULL);
  require(fseek(f, 0, SEEK_END) == 0);
  long n = ftell(f);
  require(n >= 0 && n <= 8 * 1024 * 1024);
  rewind(f);
  Bytes b = {alloc(NULL, (size_t)n), (size_t)n};
  require(fread(b.p, 1, b.n, f) == b.n);
  require(fclose(f) == 0);
  return b;
}
static uint32_t number(Bytes b, size_t *at) {
  require(*at <= b.n && b.n - *at >= 4);
  uint32_t n = 0;
  for (unsigned i = 0; i < 4; i++)
    n |= (uint32_t)b.p[*at + i] << (8 * i);
  *at += 4;
  return n;
}
static InputRow *decode(Bytes b, size_t *count) {
  require(b.n >= 12 && memcmp(b.p, "GCFIELDS", 8) == 0);
  size_t at = 8;
  *count = number(b, &at);
  require(*count <= 65536);
  InputRow *rows = alloc(NULL, *count * sizeof(*rows));
  for (size_t i = 0; i < *count; i++) {
    rows[i].n = number(b, &at);
    require(rows[i].n <= 65536);
    rows[i].fields = alloc(NULL, rows[i].n * sizeof(Bytes));
    for (size_t j = 0; j < rows[i].n; j++) {
      size_t n = number(b, &at);
      require(at <= b.n && n <= b.n - at);
      rows[i].fields[j] = (Bytes){b.p + at, n};
      at += n;
    }
  }
  require(at == b.n);
  return rows;
}
static void parse(Bytes input, size_t chunk, size_t repeats, int dump) {
  struct csv_parser p;
  require(csv_init(&p, CSV_STRICT | CSV_STRICT_FINI) == 0);
  csv_set_space_func(&p, no_space);
  State s = {0};
  s.dump = dump;
  int ok = 1;
  uint64_t start = now();
  for (size_t round = 0; round < repeats && ok; round++) {
    for (size_t at = 0; at < input.n;) {
      size_t n = input.n - at;
      if (n > chunk)
        n = chunk;
      size_t got = csv_parse(&p, input.p + at, n, field_cb, row_cb, &s);
      at += got;
      s.bytes += got;
      if (got != n) {
        ok = 0;
        break;
      }
    }
  }
  if (ok && csv_fini(&p, field_cb, row_cb, &s) != 0)
    ok = 0;
  uint64_t elapsed = now() - start;
  if (!ok && dump)
    printf("E native libcsv-%d-at-%" PRIu64 "\n", csv_error(&p), s.bytes);
  printf("S %" PRIu64 " %" PRIu64 " %" PRIu64 " %" PRIu64 " %s\n", s.rows,
         s.bytes, s.checksum, elapsed, ok ? "ok" : "error");
  csv_free(&p);
  free(s.data);
  free(s.ends);
}
static void encode(Bytes input, size_t repeats, int dump) {
  size_t count;
  InputRow *rows = decode(input, &count);
  size_t capacity = 2;
  for (size_t i = 0; i < count; i++) {
    size_t bound = 2;
    for (size_t j = 0; j < rows[i].n; j++) {
      require(bound <= CAP - 3);
      require(rows[i].fields[j].n <= (CAP - bound - 3) / 2);
      bound += 2 * rows[i].fields[j].n + 3;
    }
    if (bound > capacity)
      capacity = bound;
  }
  unsigned char *out = alloc(NULL, capacity);
  uint64_t records = 0, bytes = 0, checksum = 0, start = now();
  for (size_t round = 0; round < repeats; round++) {
    for (size_t i = 0; i < count; i++) {
      size_t used = 0;
      InputRow row = rows[i];
      for (size_t j = 0; j < row.n; j++) {
        Bytes f = row.fields[j];
        int quoted = (row.n == 1 && f.n == 0);
        for (size_t k = 0; k < f.n && !quoted; k++)
          if (f.p[k] == '"' || f.p[k] == ',' || f.p[k] == '\r' ||
              f.p[k] == '\n')
            quoted = 1;
        if (j)
          out[used++] = ',';
        if (quoted) {
          size_t n = csv_write(out + used, capacity - used,
                               f.n ? f.p : (const unsigned char *)"", f.n);
          require(n <= capacity - used);
          used += n;
        } else {
          if (f.n)
            memcpy(out + used, f.p, f.n);
          used += f.n;
        }
      }
      out[used++] = '\r';
      out[used++] = '\n';
      if (dump) {
        printf("W ");
        hex(out, used);
        putchar('\n');
      }
      records++;
      bytes += used;
      checksum = (checksum + wire_sig(out, used)) % MOD;
    }
  }
  uint64_t elapsed = now() - start;
  printf("S %" PRIu64 " %" PRIu64 " %" PRIu64 " %" PRIu64 " ok\n", records,
         bytes, checksum, elapsed);
  for (size_t i = 0; i < count; i++)
    free(rows[i].fields);
  free(rows);
  free(out);
}
int main(int argc, char **argv) {
  require(argc == 7 && strcmp(argv[1], "libcsv") == 0);
  Bytes input = load(argv[3]);
  char *end = NULL;
  size_t chunk = strtoul(argv[4], &end, 10);
  require(end && *end == 0);
  size_t repeats = strtoul(argv[5], &end, 10);
  require(end && *end == 0 && repeats >= 1 && repeats <= 1000000);
  int dump = strcmp(argv[6], "1") == 0;
  if (strcmp(argv[2], "parse") == 0) {
    require(chunk > 0);
    parse(input, chunk, repeats, dump);
  } else {
    require(strcmp(argv[2], "write") == 0);
    encode(input, repeats, dump);
  }
  free(input.p);
  return 0;
}
