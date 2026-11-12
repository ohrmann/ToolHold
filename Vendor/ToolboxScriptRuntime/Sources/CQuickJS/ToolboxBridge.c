#include "include/CQuickJS.h"
#include "quickjs.h"
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <malloc/malloc.h>
struct TBScriptCancellation { atomic_int cancelled; double deadline; int budget_exceeded; };
static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec+t.tv_nsec/1e9; }
TBScriptCancellation *tb_script_cancellation_create(void) { return calloc(1,sizeof(TBScriptCancellation)); }
int tb_script_is_cancelled(TBScriptCancellation *f) { return f ? atomic_load(&f->cancelled) : 0; }
void tb_script_cancel(TBScriptCancellation *f) { if(f) atomic_store(&f->cancelled,1); }
void tb_script_cancellation_free(TBScriptCancellation *f) { free(f); }
void tb_script_free(char *p) { free(p); }
static int interrupted(JSRuntime *r, void *opaque) { TBScriptCancellation *f=opaque; return atomic_load(&f->cancelled)||f->budget_exceeded||now()>f->deadline; }
// Account for Apple's actual allocation sizes and retain OOM provenance even if a
// JS library catches the original exception and later throws an unrelated error.
static size_t allocation_size(const void *p) { return p ? malloc_size(p) : 0; }
static void *bounded_malloc(JSMallocState *s,size_t size) {
 TBScriptCancellation *f=s->opaque;
 if(size>s->malloc_limit || s->malloc_size>s->malloc_limit-size){f->budget_exceeded=1;return NULL;}
 void *p=malloc(size);if(!p){f->budget_exceeded=1;return NULL;}
 size_t actual=allocation_size(p);
 if(actual>s->malloc_limit || s->malloc_size>s->malloc_limit-actual){free(p);f->budget_exceeded=1;return NULL;}
 s->malloc_count++;s->malloc_size+=actual;return p;
}
static void bounded_free(JSMallocState *s,void *p) {
 if(!p)return;s->malloc_count--;s->malloc_size-=allocation_size(p);free(p);
}
static void *bounded_realloc(JSMallocState *s,void *p,size_t size) {
 if(!p)return bounded_malloc(s,size);
 if(!size){bounded_free(s,p);return NULL;}
 size_t old=allocation_size(p);TBScriptCancellation *f=s->opaque;
 if(size>s->malloc_limit || s->malloc_size-old>s->malloc_limit-size){f->budget_exceeded=1;return NULL;}
 void *q=realloc(p,size);if(!q){f->budget_exceeded=1;return NULL;}
 s->malloc_size+=allocation_size(q)-old;
 if(s->malloc_size>s->malloc_limit)f->budget_exceeded=1;
 return q;
}
static const JSMallocFunctions allocations={bounded_malloc,bounded_free,bounded_realloc,allocation_size};
static JSValue evaluate(JSContext *ctx,const char *source,size_t length,const char *name) {
 char *copy=malloc(length+1);if(!copy)return JS_ThrowOutOfMemory(ctx);
 memcpy(copy,source,length);copy[length]=0;JSValue value=JS_Eval(ctx,copy,length,name,JS_EVAL_TYPE_GLOBAL);free(copy);return value;
}
char *tb_script_run(const char *bundle,size_t bl,const char *extra,size_t el,const char *request,size_t rl,TBScriptCancellation *flag,int *status,size_t *length) {
 *status=3; *length=0; char *out=NULL; flag->budget_exceeded=0; JSRuntime *rt=JS_NewRuntime2(&allocations,flag); if(!rt)return NULL;
 JS_SetMemoryLimit(rt,128*1024*1024); JS_SetMaxStackSize(rt,1024*1024);
 flag->deadline=now()+10; JS_SetInterruptHandler(rt,interrupted,flag);
 JSContext *ctx=JS_NewContext(rt); if(!ctx){JS_FreeRuntime(rt);return NULL;}
 JSValue loaded=evaluate(ctx,bundle,bl,"bundled-code-markup");
 if(JS_IsException(loaded)){JS_FreeValue(ctx,loaded);goto done;} JS_FreeValue(ctx,loaded);
 if(el){loaded=evaluate(ctx,extra,el,"bundled-mjml");if(JS_IsException(loaded)){JS_FreeValue(ctx,loaded);goto done;}JS_FreeValue(ctx,loaded);}
 flag->deadline=now()+(el?10:5);
 char *jsonInput=malloc(rl+1);if(!jsonInput)goto done;memcpy(jsonInput,request,rl);jsonInput[rl]=0;
 JSValue arg=JS_ParseJSON(ctx,jsonInput,rl,"request");free(jsonInput);
 if(JS_IsException(arg)){JS_FreeValue(ctx,arg);goto done;}
 JSValue global=JS_GetGlobalObject(ctx), fn=JS_GetPropertyStr(ctx,global,"ToolboxMarkup");
 JSValue result=JS_Call(ctx,fn,JS_UNDEFINED,1,&arg);
 JS_FreeValue(ctx,arg);JS_FreeValue(ctx,fn);JS_FreeValue(ctx,global);
 if(JS_IsException(result)){JS_FreeValue(ctx,result);goto done;}
 if(JS_PromiseState(ctx,result)>=0){
  while(JS_PromiseState(ctx,result)==JS_PROMISE_PENDING){JSContext *jobctx=NULL;if(interrupted(rt,flag)||JS_ExecutePendingJob(rt,&jobctx)<=0){JS_FreeValue(ctx,result);goto done;}}
  JSValue settled=JS_PromiseResult(ctx,result); int rejected=JS_PromiseState(ctx,result)==JS_PROMISE_REJECTED;JS_FreeValue(ctx,result);result=settled;
  if(rejected){JS_FreeValue(ctx,result);goto done;}
 }
 JSValue json=JS_JSONStringify(ctx,result,JS_UNDEFINED,JS_UNDEFINED);JS_FreeValue(ctx,result);
 if(!JS_IsException(json)){
  size_t n=0;const char *str=JS_ToCStringLen(ctx,&n,json);
  if(str&&n<=8*1024*1024){out=malloc(n+1);if(out){memcpy(out,str,n);out[n]=0;*length=n;*status=0;}}
  if(str)JS_FreeCString(ctx,str);
 }JS_FreeValue(ctx,json);
 done:
 if(atomic_load(&flag->cancelled))*status=1;else if(now()>flag->deadline)*status=2;else if(flag->budget_exceeded)*status=4;
 // Do not expose or log engine exceptions: these can contain working source.
 JS_FreeContext(ctx);JS_FreeRuntime(rt);return out;
}
