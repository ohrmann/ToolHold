#include "CRegex.h"
#define PCRE2_CODE_UNIT_WIDTH 16
#include "PCRE2Bridge.h"
#include <stdlib.h>
#include <stdatomic.h>
#include <time.h>
#include <string.h>
#include <stdbool.h>
struct TRCancel { atomic_bool cancelled; };
TRCancel *tr_cancel_create(void) { TRCancel *c=calloc(1,sizeof(*c)); if(c)atomic_init(&c->cancelled,false);return c; }
void tr_cancel_request(TRCancel *c){ if(c)atomic_store(&c->cancelled,true); }
void tr_cancel_free(TRCancel *c){free(c);}
const char *tr_version(void){return "PCRE2 10.49 · Unicode 17";}
typedef struct { TRCancel *cancel; double deadline; size_t used; int reason; } Budget;
typedef union { max_align_t alignment; size_t size; } Header;
static double now(void){struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return t.tv_sec+t.tv_nsec/1e9;}
static int stopped(Budget *b){if(b->cancel && atomic_load(&b->cancel->cancelled)){b->reason=3;return 1;}if(now()>b->deadline){b->reason=2;return 1;}return b->reason!=0;}
static void *allocate(PCRE2_SIZE n,void *ctx){Budget*b=ctx;if(stopped(b)||n>32*1024*1024-b->used||n>SIZE_MAX-sizeof(Header)){if(!b->reason)b->reason=2;return NULL;}Header*h=malloc(n+sizeof(Header));if(!h){b->reason=2;return NULL;}h->size=n;b->used+=n;return h+1;}
static void release(void*p,void*ctx){if(!p)return;Header*h=(Header*)p-1;((Budget*)ctx)->used-=h->size;free(h);}
static int callout(pcre2_callout_block *block,void*ctx){(void)block;return stopped(ctx)?PCRE2_ERROR_CALLOUT:0;}
static int guard_compile(uint32_t depth,void*ctx){return depth>128||stopped(ctx);}
static void message(TRResult*r,const char*s){size_t i=0;while(s[i]&&i<255){r->message[i]=(uint8_t)s[i];i++;}r->message_length=i;}
TRResult *tr_run(const uint16_t *pattern,size_t plen,const uint16_t *text,size_t length,unsigned flags,unsigned milliseconds,TRCancel*cancel){
 TRResult*r=calloc(1,sizeof(*r));if(!r)return NULL;
 if(plen>((flags&16)?98304:8192)||length>262144){r->status=2;message(r,"Input or pattern limit reached.");return r;}
 Budget b={cancel,now()+milliseconds/1000.0,0,0};
 pcre2_general_context*g=pcre2_general_context_create(allocate,release,&b);
 pcre2_compile_context*c=g?pcre2_compile_context_create(g):NULL;
 pcre2_match_context*m=g?pcre2_match_context_create(g):NULL;
 pcre2_code*code=NULL;pcre2_match_data*data=NULL;
 if(!c||!m){r->status=2;goto done;}
 pcre2_set_max_pattern_length(c,(flags&16)?98304:8192);pcre2_set_max_pattern_compiled_length(c,1024*1024);
 pcre2_set_parens_nest_limit(c,128);pcre2_set_compile_recursion_guard(c,guard_compile,&b);
 pcre2_set_newline(c,PCRE2_NEWLINE_ANYCRLF);
 unsigned options=PCRE2_UTF|PCRE2_UCP|PCRE2_NEVER_BACKSLASH_C|PCRE2_AUTO_CALLOUT;
 if(flags&1)options|=PCRE2_CASELESS;if(flags&2)options|=PCRE2_MULTILINE;if(flags&4)options|=PCRE2_DOTALL;if(flags&8)options|=PCRE2_EXTENDED;
 /* Literal input is escaped by Swift, preserving identical matching/resource controls. */
 int err=0;size_t error=0;code=pcre2_compile(pattern,plen,options,&err,&error,c);
 if(!code){r->status=b.reason?b.reason:((err==PCRE2_ERROR_PARENTHESES_NEST_TOO_DEEP||err==PCRE2_ERROR_PATTERN_TOO_LARGE||err==PCRE2_ERROR_HEAP_FAILED||err==PCRE2_ERROR_PARENTHESES_STACK_CHECK||err==PCRE2_ERROR_PATTERN_TOO_COMPLICATED)?2:1);r->error_offset=error;int n=pcre2_get_error_message(err,r->message,256);r->message_length=n>0?(size_t)n:0;goto done;}
 uint32_t groups=0;pcre2_pattern_info(code,PCRE2_INFO_CAPTURECOUNT,&groups);r->groups=groups;
 if(groups>128){r->status=2;message(r,"More than 128 capture groups.");goto done;}
 uint32_t nc=0,entry=0;PCRE2_SPTR table=NULL;pcre2_pattern_info(code,PCRE2_INFO_NAMECOUNT,&nc);pcre2_pattern_info(code,PCRE2_INFO_NAMEENTRYSIZE,&entry);pcre2_pattern_info(code,PCRE2_INFO_NAMETABLE,&table);
 r->names=calloc(129*129,sizeof(uint16_t));if(!r->names){r->status=2;goto done;}
 for(uint32_t i=0;i<nc;i++){const uint16_t*p=table+i*entry;size_t group=p[0];if(group<=128){for(size_t j=1;j<entry&&j<=128&&p[j];j++)r->names[group*129+j-1]=p[j];}}
 pcre2_set_match_limit(m,1000000);pcre2_set_depth_limit(m,256);pcre2_set_heap_limit(m,8192);pcre2_set_callout(m,callout,&b);
 data=pcre2_match_data_create_from_pattern(code,g);r->ranges=malloc(250000*2*sizeof(size_t));
 if(!data||!r->ranges){r->status=2;goto done;}
 size_t start=0;uint32_t next=0;
 for(;;){
  if(stopped(&b)){r->status=b.reason;break;}
  int rc=pcre2_match(code,text,length,start,next,data,m);
  if(rc==PCRE2_ERROR_NOMATCH){if(!pcre2_next_match(data,&start,&next))break;continue;}
  if(rc<0){r->status=b.reason?b.reason:2;message(r,"Regular expression resource limit reached.");break;}
  if(r->count>=10000||(r->count+1)*(groups+1)>250000){r->status=2;message(r,"Match or capture result limit reached; no complete result.");break;}
  size_t*v=pcre2_get_ovector_pointer(data);memcpy(r->ranges+r->count*(groups+1)*2,v,(groups+1)*2*sizeof(size_t));r->count++;
  if(flags&32)break;
  if(!pcre2_next_match(data,&start,&next))break;
 }
 done:
 if(b.reason)r->status=b.reason;
 if(r->status==2&&!r->message_length)message(r,"Regular expression resource limit reached.");
 if(r->status==3)message(r,"Cancelled.");
 if(r->status){r->count=0;free(r->ranges);r->ranges=NULL;}
 if(data)pcre2_match_data_free(data);if(code)pcre2_code_free(code);if(m)pcre2_match_context_free(m);if(c)pcre2_compile_context_free(c);if(g)pcre2_general_context_free(g);
 return r;
}
void tr_result_free(TRResult*r){if(r){free(r->ranges);free(r->names);free(r);}}
