#ifndef TOOLBOX_REGEX_H
#define TOOLBOX_REGEX_H
#include <stdint.h>
#include <stddef.h>
typedef struct TRCancel TRCancel;
TRCancel *tr_cancel_create(void);
void tr_cancel_request(TRCancel *);
void tr_cancel_free(TRCancel *);
typedef struct {
 int status; /* 0 success, 1 syntax, 2 resource, 3 cancelled, 4 failure */
 size_t error_offset;
 uint16_t message[256];
 size_t message_length;
 size_t count, groups;
 size_t *ranges; /* [match][group including zero][start,end], SIZE_MAX = unmatched */
 uint16_t *names; /* flat [129][129], C-owned */
} TRResult;
/* flags: i=1, m=2, s=4, x=8; literal=16, first=32 */
TRResult *tr_run(const uint16_t *, size_t, const uint16_t *, size_t, unsigned, unsigned, TRCancel *);
void tr_result_free(TRResult *);
const char *tr_version(void);
#endif
