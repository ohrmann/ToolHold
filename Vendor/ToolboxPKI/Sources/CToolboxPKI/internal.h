#include "ToolboxPKI.h"
#include <openssl/evp.h>
#include <openssl/x509.h>
#include <openssl/x509v3.h>
#include <openssl/pkcs12.h>
#include <openssl/provider.h>
#include <openssl/core_names.h>
#include <openssl/decoder.h>
#include <openssl/rand.h>
#include <openssl/err.h>
#include <openssl/buffer.h>
#include <stdatomic.h>
#include <string.h>
#include <limits.h>
#include <arpa/inet.h>
#define TB_MAX_KEYS 32
#define TB_MAX_CERTS 128
#define TB_MAX_BAGS 256
struct TBPKI {
 OSSL_LIB_CTX *lib;
 OSSL_PROVIDER *provider,*legacy;
 EVP_PKEY *keys[TB_MAX_KEYS]; int private_keys[TB_MAX_KEYS],key_count;
 X509 *certs[TB_MAX_CERTS]; int cert_count;int chain[16],chain_count;
 int error_kind;char error[256];atomic_int cancelled;
 PKCS12 *pfx;STACK_OF(PKCS12_SAFEBAG) *bags[64];int bag_stacks;
 struct {const PKCS12_SAFEBAG *bag;int key,cert;char description[1024];} inventory[TB_MAX_BAGS];int inventory_count,mac_verified,rewritable;
 long kdf_work;size_t decoded;char protections[4096];
};
static inline int tb_fail(TBPKI *c,int kind,const char *text){c->error_kind=kind;snprintf(c->error,sizeof(c->error),"%s",text);ERR_clear_error();return 0;}
static inline int tb_alive(TBPKI *c){return !atomic_load(&c->cancelled) || tb_fail(c,5,"Cancelled");}
static inline int tb_key_valid(TBPKI *c,int i){return i>=0&&i<c->key_count;}
static inline int tb_cert_valid(TBPKI *c,int i){return i>=0&&i<c->cert_count;}
int tb_key_store(TBPKI *,EVP_PKEY *,int);
int tb_cert_store(TBPKI *,X509 *);
int tb_buffer(TBPKI *,const unsigned char *,size_t,TBPKIBuffer *);
int tb_bio_buffer(TBPKI *,BIO *,TBPKIBuffer *);
int tb_algorithm(TBPKI *,EVP_PKEY *,int);
int tb_pbe_check(TBPKI *,const X509_ALGOR *,int);
int tb_mac_check_budget(TBPKI *,const PKCS12 *);
