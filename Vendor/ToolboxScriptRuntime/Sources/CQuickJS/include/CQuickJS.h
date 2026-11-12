#ifndef TOOLBOX_QUICKJS_H
#define TOOLBOX_QUICKJS_H
#include <stddef.h>
#include <stdint.h>
typedef struct TBScriptCancellation TBScriptCancellation;
TBScriptCancellation *tb_script_cancellation_create(void);
int tb_script_is_cancelled(TBScriptCancellation *flag);
void tb_script_cancel(TBScriptCancellation *flag);
void tb_script_cancellation_free(TBScriptCancellation *flag);
// Only application-owned bundle source is executable. request is parsed JSON data.
char *tb_script_run(const char *bundle, size_t bundle_length, const char *extra, size_t extra_length,
 const char *request, size_t request_length, TBScriptCancellation *flag, int *status, size_t *length);
void tb_script_free(char *value);
#endif
