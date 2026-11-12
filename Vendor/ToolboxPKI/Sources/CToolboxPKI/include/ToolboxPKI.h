#ifndef TOOLBOX_PKI_H
#define TOOLBOX_PKI_H
#include <stdint.h>
#include <stddef.h>
typedef struct TBPKI TBPKI;
typedef struct { unsigned char *bytes; size_t count; } TBPKIBuffer;
typedef struct { const char *oid; const char *value; } TBPKIField;
typedef struct { int type; const char *value; } TBPKISAN; /* DNS=2, email=1, URI=6, IP=7 */
TBPKI *tb_pki_new(void);
void tb_pki_free(TBPKI *);
void tb_pki_cancel(TBPKI *);
const char *tb_pki_version(void);
const char *tb_pki_error(TBPKI *);
int tb_pki_error_kind(TBPKI *); /* 1 invalid,2 unsupported,3 resource,4 unlock,5 cancelled,6 internal */
void tb_pki_buffer_free(TBPKIBuffer);
/* All input is DER, never paths. Labels are schema hints, never parsed as code. */
int tb_pki_key_load(TBPKI *, const unsigned char *,size_t,const char *label,const char *password);
int tb_pki_key_generate(TBPKI *, const char *algorithm,int bits);
int tb_pki_key_is_private(TBPKI *,int);
int tb_pki_key_bits(TBPKI *,int);
const char *tb_pki_key_algorithm(TBPKI *,int);
int tb_pki_key_details(TBPKI *,int,TBPKIBuffer *);
int tb_pki_key_public(TBPKI *,int,TBPKIBuffer *);
int tb_pki_key_private(TBPKI *,int,const char *password,int unencrypted,TBPKIBuffer *);
int tb_pki_key_check(TBPKI *,int,int require_private);
int tb_pki_cert_load(TBPKI *,const unsigned char *,size_t);
int tb_pki_cert_der(TBPKI *,int,TBPKIBuffer *);
int tb_pki_public_match(TBPKI *,int cert,int key);
int tb_pki_match(TBPKI *,int cert,int key); /* 1match,0mismatch,-1error */
int tb_pki_generate(TBPKI *,int key,int csr,const TBPKIField *,size_t,const TBPKISAN *,size_t,int profile,int path_length,int64_t not_before,int64_t not_after,TBPKIBuffer *);
int tb_pki_csr_inspect(TBPKI *,const unsigned char *,size_t,TBPKIBuffer *summary,TBPKIBuffer *public_key); /* signature:1valid,0invalid,-1error */
int tb_pki_schema(TBPKI *,const unsigned char *,size_t,const char *label);
/* PFX inventory owns all entries. Key/cert indexes refer to this context; -1 = absent. */
int tb_pki_pfx_open(TBPKI *,const unsigned char *,size_t,const char *password,int legacy,int allow_unverified);
int tb_pki_pfx_bag_der(TBPKI *,int,TBPKIBuffer *);
int tb_pki_pfx_info(TBPKI *,TBPKIBuffer *);
int tb_pki_pfx_count(TBPKI *);
int tb_pki_pfx_key(TBPKI *,int);
int tb_pki_pfx_cert(TBPKI *,int);
const char *tb_pki_pfx_description(TBPKI *,int);
int tb_pki_pfx_verified(TBPKI *);
int tb_pki_pfx_rewritable(TBPKI *);
int tb_pki_pfx_create(TBPKI *,int key,int leaf,const int *extra,size_t count,const char *name,const char *password,TBPKIBuffer *);
int tb_pki_pfx_repackage(TBPKI *,const char *password,TBPKIBuffer *);
/* Explicit roots only. No ambient paths or network. */
int tb_pki_chain_count(TBPKI *);
int tb_pki_chain_certificate(TBPKI *,int);
int tb_pki_cert_hostname(TBPKI *,int,const char *);
int tb_pki_chain(TBPKI *,int leaf,const int *intermediates,size_t,const int *roots,size_t,int policy,const char *hostname,int64_t verify_time,TBPKIBuffer *report);
#endif
