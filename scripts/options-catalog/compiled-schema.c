#include <stdio.h>
#include <stdlib.h>
static void js(const char *s) {
  if (!s) { fputs("null", stdout); return; }
  putchar('"');
  for (const unsigned char *p=(const unsigned char *)s; *p; p++) {
    if (*p=='"' || *p=='\\') { putchar('\\'); putchar(*p); }
    else if (*p<32) printf("\\u%04x", *p);
    else putchar(*p);
  }
  putchar('"');
}
int main(void) {
  printf("{\"integer_profile\":{\"int_bits\":%zu,\"short_bits\":%zu,\"uint_max\":%u},\"options\":[", sizeof(int)*8, sizeof(short)*8, UINT_MAX);
  size_t count=sizeof(options_table)/sizeof(options_table[0]);
  if (count>4096 || options_table[count-1].name!=NULL) return 4;
  for (size_t i=0; i<count-1; i++) {
    const struct options_table_entry *o=&options_table[i];
    if (i) putchar(',');
    fputs("{\"name\":",stdout); js(o->name);
    printf(",\"type\":%d,\"scope\":%d,\"flags\":%d,\"minimum\":%u,\"maximum\":%u,\"choices\":",o->type,o->scope,o->flags,o->minimum,o->maximum);
    if (!o->choices) fputs("null",stdout);
    else { putchar('['); for (size_t n=0; o->choices[n]; n++) { if(n)putchar(','); js(o->choices[n]); } putchar(']'); }
    fputs(",\"alternative_name\":",stdout); js(o->alternative_name);
    fputs(",\"separator\":",stdout); js(o->separator);
    fputs(",\"pattern\":",stdout); js(o->pattern);
    fputs(",\"text\":",stdout); js(o->text);
    fputs(",\"unit\":",stdout); js(o->unit);
    putchar('}');
  }
  fputs("],\"aliases\":[",stdout);
  for (size_t i=0; options_other_names[i].from; i++) {
    if(i)putchar(','); putchar('['); js(options_other_names[i].from); putchar(','); js(options_other_names[i].to); putchar(']');
  }
  fputs("]}\n",stdout);
  return 0;
}
