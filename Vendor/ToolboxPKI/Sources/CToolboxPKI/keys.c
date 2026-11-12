#include "internal.h"
TBPKI *tb_pki_new(void){
 OPENSSL_init_crypto(OPENSSL_INIT_NO_LOAD_CONFIG,NULL);
 TBPKI *c=OPENSSL_zalloc(sizeof(*c));if(!c)return NULL;
 atomic_init(&c->cancelled,0);c->lib=OSSL_LIB_CTX_new();
 if(c->lib)c->provider=OSSL_PROVIDER_load(c->lib,"default");
 if(!c->provider||RAND_status()!=1){tb_pki_free(c);return NULL;}return c;
}
void tb_pki_free(TBPKI *c){if(!c)return;for(int i=0;i<c->key_count;i++)EVP_PKEY_free(c->keys[i]);for(int i=0;i<c->cert_count;i++)X509_free(c->certs[i]);for(int i=0;i<c->bag_stacks;i++)sk_PKCS12_SAFEBAG_pop_free(c->bags[i],PKCS12_SAFEBAG_free);PKCS12_free(c->pfx);OSSL_PROVIDER_unload(c->legacy);OSSL_PROVIDER_unload(c->provider);OSSL_LIB_CTX_free(c->lib);OPENSSL_clear_free(c,sizeof(*c));}
void tb_pki_cancel(TBPKI *c){if(c)atomic_store(&c->cancelled,1);}
const char *tb_pki_version(void){return OpenSSL_version(OPENSSL_VERSION);}
const char *tb_pki_error(TBPKI *c){return c?c->error:"Crypto backend unavailable";}
int tb_pki_error_kind(TBPKI *c){return c?c->error_kind:6;}
void tb_pki_buffer_free(TBPKIBuffer b){OPENSSL_clear_free(b.bytes,b.count);}
int tb_buffer(TBPKI *c,const unsigned char *p,size_t n,TBPKIBuffer *out){if(n>8*1024*1024)return tb_fail(c,3,"Output exceeds 8 MiB");out->bytes=n?OPENSSL_memdup(p,n):OPENSSL_zalloc(1);out->count=n;return out->bytes!=NULL||tb_fail(c,6,"Allocation failed");}
int tb_bio_buffer(TBPKI *c,BIO *b,TBPKIBuffer *out){char *p=NULL;long n=BIO_get_mem_data(b,&p);return n>=0&&tb_buffer(c,(unsigned char*)p,(size_t)n,out);}
int tb_key_store(TBPKI *c,EVP_PKEY *key,int priv){if(!key)return -1;if(c->key_count==TB_MAX_KEYS){EVP_PKEY_free(key);tb_fail(c,3,"Too many keys");return -1;}int i=c->key_count++;c->keys[i]=key;c->private_keys[i]=priv;return i;}
int tb_cert_store(TBPKI *c,X509 *x){if(!x)return -1;if(c->cert_count==TB_MAX_CERTS){X509_free(x);tb_fail(c,3,"Too many certificates");return -1;}int i=c->cert_count++;c->certs[i]=x;return i;}
int tb_algorithm(TBPKI *c,EVP_PKEY *p,int operation){
 int bits=EVP_PKEY_get_bits(p);
 if(EVP_PKEY_is_a(p,"RSA")||EVP_PKEY_is_a(p,"RSA-PSS")){if(bits>8192||bits<512)return tb_fail(c,3,"RSA key size is outside inspection limits");if(operation&&bits<2048)return tb_fail(c,2,"RSA operations require at least 2048 bits");return 1;}
 if(EVP_PKEY_is_a(p,"ED25519"))return 1;
 if(EVP_PKEY_is_a(p,"EC")){char group[80];size_t n;if(EVP_PKEY_get_group_name(p,group,sizeof(group),&n)&&(!strcmp(group,"prime256v1")||!strcmp(group,"secp384r1")||!strcmp(group,"secp521r1")))return 1;}
 return tb_fail(c,2,"Unsupported key algorithm or named curve");
}
/* Decoder input_structure is a preference, not a strict envelope validator: decoder
   chains can unwrap PKCS#8/SPKI even with "type-specific". Check the legacy ASN.1
   field layout first, then retain the provider's complete key validation below. */
static int legacy_key_schema(const unsigned char *data,size_t n,const char *label){
 const unsigned char *p=data;STACK_OF(ASN1_TYPE) *fields=d2i_ASN1_SEQUENCE_ANY(NULL,&p,(long)n);
 if(!fields)return 0;int count=sk_ASN1_TYPE_num(fields),ok=p==data+n;
 if(!strcmp(label,"RSA PUBLIC KEY")){
  ok=ok&&count==2;
  for(int i=0;ok&&i<count;i++)ok=ASN1_TYPE_get(sk_ASN1_TYPE_value(fields,i))==V_ASN1_INTEGER;
 }else if(!strcmp(label,"RSA PRIVATE KEY")){
  ok=ok&&(count==9||count==10);
  for(int i=0;ok&&i<9;i++)ok=ASN1_TYPE_get(sk_ASN1_TYPE_value(fields,i))==V_ASN1_INTEGER;
  if(ok){long version=ASN1_INTEGER_get(sk_ASN1_TYPE_value(fields,0)->value.integer);ok=(version==0&&count==9)||(version==1&&count==10&&ASN1_TYPE_get(sk_ASN1_TYPE_value(fields,9))==V_ASN1_SEQUENCE);}
 }else if(!strcmp(label,"EC PRIVATE KEY")){
  ok=ok&&count>=2&&count<=4&&ASN1_TYPE_get(sk_ASN1_TYPE_value(fields,0))==V_ASN1_INTEGER&&ASN1_INTEGER_get(sk_ASN1_TYPE_value(fields,0)->value.integer)==1&&ASN1_TYPE_get(sk_ASN1_TYPE_value(fields,1))==V_ASN1_OCTET_STRING;
 }else ok=0;
 sk_ASN1_TYPE_pop_free(fields,ASN1_TYPE_free);return ok;
}
int tb_pki_key_load(TBPKI *c,const unsigned char *data,size_t n,const char *label,const char *pass){
 if(!tb_alive(c))return -1;if(n>65536){tb_fail(c,3,"Key exceeds 64 KiB");return -1;}
 const unsigned char *p=data;EVP_PKEY *key=NULL;int priv=strcmp(label,"PUBLIC KEY")&&strcmp(label,"RSA PUBLIC KEY");
 if(!strcmp(label,"ENCRYPTED PRIVATE KEY")){
  X509_SIG *encrypted=d2i_X509_SIG(NULL,&p,(long)n);const X509_ALGOR *alg=NULL;
  if(encrypted)X509_SIG_get0(encrypted,&alg,NULL);
  if(!encrypted||p!=data+n){X509_SIG_free(encrypted);tb_fail(c,1,"Invalid encrypted PKCS#8");return -1;}
  if(!tb_pbe_check(c,alg,0)){X509_SIG_free(encrypted);return -1;}
  PKCS8_PRIV_KEY_INFO *info=PKCS8_decrypt_ex(encrypted,pass,(int)strlen(pass),c->lib,NULL);X509_SIG_free(encrypted);
  if(info){key=EVP_PKCS82PKEY_ex(info,c->lib,NULL);PKCS8_PRIV_KEY_INFO_free(info);}else{tb_fail(c,4,"Cannot unlock: password incorrect or data damaged");return -1;}
 }else if(!strcmp(label,"PRIVATE KEY")){
  PKCS8_PRIV_KEY_INFO *info=d2i_PKCS8_PRIV_KEY_INFO(NULL,&p,(long)n);if(info&&p==data+n)key=EVP_PKCS82PKEY_ex(info,c->lib,NULL);PKCS8_PRIV_KEY_INFO_free(info);
 }else if(!strcmp(label,"PUBLIC KEY")){key=d2i_PUBKEY_ex(NULL,&p,(long)n,c->lib,NULL);}
 else{
  const char *type=!strcmp(label,"EC PRIVATE KEY")?"EC":"RSA";
  if(strcmp(label,"EC PRIVATE KEY")&&strcmp(label,"RSA PRIVATE KEY")&&strcmp(label,"RSA PUBLIC KEY")){tb_fail(c,2,"Unsupported key envelope");return -1;}
  if(!legacy_key_schema(data,n,label)){tb_fail(c,1,"Object does not match the legacy key envelope");return -1;}
  const unsigned char *q=data;size_t remaining=n;
  /* Legacy labels describe type-specific ASN.1, never PKCS#8 or SPKI wrappers.
     An unconstrained decoder also accepts those wrappers and makes auto-detection ambiguous. */
  OSSL_DECODER_CTX *d=OSSL_DECODER_CTX_new_for_pkey(&key,"DER","type-specific",type,priv?EVP_PKEY_KEYPAIR:EVP_PKEY_PUBLIC_KEY,c->lib,NULL);
  if(!d||!OSSL_DECODER_from_data(d,&q,&remaining)||remaining){EVP_PKEY_free(key);key=NULL;}p=data+n;OSSL_DECODER_CTX_free(d);
 }
 if(!key||p!=data+n){EVP_PKEY_free(key);tb_fail(c,1,"Invalid key structure or trailing bytes");return -1;}
 if(!tb_algorithm(c,key,0)){EVP_PKEY_free(key);return -1;}return tb_key_store(c,key,priv);
}
static int keygen_callback(EVP_PKEY_CTX *ctx){TBPKI *c=EVP_PKEY_CTX_get_app_data(ctx);return tb_alive(c);}
int tb_pki_key_generate(TBPKI *c,const char *alg,int bits){
 if(!tb_alive(c))return -1;EVP_PKEY_CTX *p=NULL;EVP_PKEY *key=NULL;int ok=0;
 if(!strcmp(alg,"RSA")){if(bits!=2048&&bits!=3072&&bits!=4096){tb_fail(c,2,"Choose RSA 2048, 3072 or 4096");return -1;}p=EVP_PKEY_CTX_new_from_name(c->lib,"RSA",NULL);if(p&&EVP_PKEY_keygen_init(p)>0&&EVP_PKEY_CTX_set_rsa_keygen_bits(p,bits)>0)ok=1;}
 else if(!strcmp(alg,"P-256")||!strcmp(alg,"P-384")||!strcmp(alg,"P-521")){p=EVP_PKEY_CTX_new_from_name(c->lib,"EC",NULL);if(p&&EVP_PKEY_keygen_init(p)>0&&EVP_PKEY_CTX_set_group_name(p,!strcmp(alg,"P-256")?"prime256v1":!strcmp(alg,"P-384")?"secp384r1":"secp521r1")>0)ok=1;}
 else if(!strcmp(alg,"Ed25519")){p=EVP_PKEY_CTX_new_from_name(c->lib,"ED25519",NULL);if(p&&EVP_PKEY_keygen_init(p)>0)ok=1;}
 if(ok){EVP_PKEY_CTX_set_app_data(p,c);EVP_PKEY_CTX_set_cb(p,keygen_callback);ok=EVP_PKEY_generate(p,&key)>0;}EVP_PKEY_CTX_free(p);
 if(!ok||!tb_alive(c)){EVP_PKEY_free(key);if(c->error_kind!=5)tb_fail(c,6,"Key generation failed");return -1;}return tb_key_store(c,key,1);
}
int tb_pki_key_is_private(TBPKI *c,int i){return tb_key_valid(c,i)&&c->private_keys[i];}
int tb_pki_key_bits(TBPKI *c,int i){return tb_key_valid(c,i)?EVP_PKEY_get_bits(c->keys[i]):0;}
const char *tb_pki_key_algorithm(TBPKI *c,int i){return tb_key_valid(c,i)?EVP_PKEY_get0_type_name(c->keys[i]):"Unknown";}
int tb_pki_key_public(TBPKI *c,int i,TBPKIBuffer *out){if(!tb_key_valid(c,i))return tb_fail(c,1,"Select a key");unsigned char *p=NULL;int n=i2d_PUBKEY(c->keys[i],&p);int ok=n>0&&tb_buffer(c,p,n,out);OPENSSL_free(p);return ok;}
int tb_pki_key_check(TBPKI *c,int i,int priv){
 if(!tb_key_valid(c,i))return tb_fail(c,1,"Select a key");if(priv&&!c->private_keys[i])return tb_fail(c,1,"Not a private key");if(!tb_algorithm(c,c->keys[i],priv))return 0;
 EVP_PKEY_CTX *p=EVP_PKEY_CTX_new_from_pkey(c->lib,c->keys[i],NULL);int ok=p&&EVP_PKEY_public_check(p)>0;
 if(priv)ok=ok&&EVP_PKEY_private_check(p)>0&&EVP_PKEY_pairwise_check(p)>0;EVP_PKEY_CTX_free(p);return ok||tb_fail(c,1,"Key consistency check failed");
}
int tb_pki_key_private(TBPKI *c,int i,const char *pass,int plain,TBPKIBuffer *out){
 if(!tb_pki_key_check(c,i,1)||!tb_alive(c))return 0;if(!plain&&!pass[0])return tb_fail(c,1,"Enter an export password");
 PKCS8_PRIV_KEY_INFO *info=EVP_PKEY2PKCS8(c->keys[i]);if(!info)return tb_fail(c,6,"Cannot encode private key");unsigned char *bytes=NULL;int n=0;
 if(plain)n=i2d_PKCS8_PRIV_KEY_INFO(info,&bytes);
 else{X509_ALGOR *pbe=PKCS5_pbe2_set_iv_ex(EVP_aes_256_cbc(),100000,NULL,16,NULL,NID_hmacWithSHA256,c->lib);X509_SIG *encrypted=pbe?PKCS8_set0_pbe_ex(pass,(int)strlen(pass),info,pbe,c->lib,NULL):NULL;if(!encrypted)X509_ALGOR_free(pbe);if(encrypted)n=i2d_X509_SIG(encrypted,&bytes);X509_SIG_free(encrypted);}
 PKCS8_PRIV_KEY_INFO_free(info);int ok=n>0&&tb_buffer(c,bytes,n,out);OPENSSL_clear_free(bytes,n>0?n:0);return ok||tb_fail(c,6,"Private key export failed");
}
int tb_pki_cert_load(TBPKI *c,const unsigned char *data,size_t n){if(n>262144){tb_fail(c,3,"Certificate exceeds 256 KiB");return -1;}const unsigned char *p=data;X509 *x=X509_new_ex(c->lib,NULL);if(!x||!d2i_X509(&x,&p,n)||p!=data+n){X509_free(x);tb_fail(c,1,"Invalid certificate or trailing bytes");return -1;}return tb_cert_store(c,x);}
int tb_pki_cert_der(TBPKI *c,int i,TBPKIBuffer *out){if(!tb_cert_valid(c,i))return tb_fail(c,1,"Select a certificate");unsigned char *p=NULL;int n=i2d_X509(c->certs[i],&p);int ok=n>0&&tb_buffer(c,p,n,out);OPENSSL_free(p);return ok;}
static const char *digest_name(EVP_PKEY *p){static _Thread_local char restricted[80];size_t length=0;if(EVP_PKEY_is_a(p,"RSA-PSS")&&EVP_PKEY_get_utf8_string_param(p,OSSL_PKEY_PARAM_RSA_DIGEST,restricted,sizeof(restricted),&length)>0)return restricted;return EVP_PKEY_is_a(p,"ED25519")?NULL:(EVP_PKEY_is_a(p,"EC")&&EVP_PKEY_get_bits(p)>384)?"SHA512":(EVP_PKEY_is_a(p,"EC")&&EVP_PKEY_get_bits(p)>256)?"SHA384":"SHA256";}
int tb_pki_public_match(TBPKI *c,int cert,int key){if(!tb_cert_valid(c,cert)||!tb_key_valid(c,key))return 0;EVP_PKEY *p=X509_get_pubkey(c->certs[cert]);int ok=p&&EVP_PKEY_eq(p,c->keys[key])==1;EVP_PKEY_free(p);return ok;}
int tb_pki_match(TBPKI *c,int cert,int key){
 if(!tb_cert_valid(c,cert)||!tb_pki_key_check(c,key,1))return -1;
 EVP_PKEY *pub=X509_get_pubkey(c->certs[cert]);if(!pub){tb_fail(c,2,"Unsupported certificate public key");return -1;}
 int eq=EVP_PKEY_eq(pub,c->keys[key]);if(eq!=1){EVP_PKEY_free(pub);if(eq==0)return 0;tb_fail(c,2,"Key parameters cannot be compared");return -1;}
 unsigned char challenge[64]="Developer Toolbox / PKI key correspondence / v1";
 if(RAND_bytes_ex(c->lib,challenge+48,16,128)!=1){EVP_PKEY_free(pub);tb_fail(c,6,"Secure random generation failed");return -1;}
 EVP_MD_CTX *sign=EVP_MD_CTX_new(),*verify=EVP_MD_CTX_new();unsigned char *sig=NULL;size_t n=0;int ok=sign&&verify;
 ok=ok&&EVP_DigestSignInit_ex(sign,NULL,digest_name(c->keys[key]),c->lib,NULL,c->keys[key],NULL)>0&&EVP_DigestSign(sign,NULL,&n,challenge,sizeof(challenge))>0&&n<=16384;
 if(ok){sig=OPENSSL_malloc(n);ok=sig&&EVP_DigestSign(sign,sig,&n,challenge,sizeof(challenge))>0&&EVP_DigestVerifyInit_ex(verify,NULL,digest_name(pub),c->lib,NULL,pub,NULL)>0&&EVP_DigestVerify(verify,sig,n,challenge,sizeof(challenge))==1;}
 OPENSSL_clear_free(sig,n);EVP_MD_CTX_free(sign);EVP_MD_CTX_free(verify);EVP_PKEY_free(pub);OPENSSL_cleanse(challenge,sizeof(challenge));if(!ok){tb_fail(c,2,"Private-key signing proof failed or parameters are unsupported");return -1;}return 1;
}

int tb_pki_key_details(TBPKI *c,int i,TBPKIBuffer *out){if(!tb_key_valid(c,i))return tb_fail(c,1,"Select a key");EVP_PKEY *key=c->keys[i];BIO *bio=BIO_new(BIO_s_mem());if(!bio)return tb_fail(c,6,"Allocation failed");if(EVP_PKEY_is_a(key,"EC")){char name[100];size_t n;if(EVP_PKEY_get_group_name(key,name,sizeof(name),&n))BIO_printf(bio,"Named curve: %s\n",name);}if(EVP_PKEY_is_a(key,"RSA")||EVP_PKEY_is_a(key,"RSA-PSS")){BIGNUM *e=NULL;if(EVP_PKEY_get_bn_param(key,OSSL_PKEY_PARAM_RSA_E,&e)){char *decimal=BN_bn2dec(e);if(decimal)BIO_printf(bio,"Public exponent: %.256s\n",decimal);OPENSSL_free(decimal);BN_free(e);}if(EVP_PKEY_is_a(key,"RSA-PSS")){char digest[80],mgf[80];size_t n;int salt;if(EVP_PKEY_get_utf8_string_param(key,OSSL_PKEY_PARAM_RSA_DIGEST,digest,sizeof(digest),&n)>0)BIO_printf(bio,"PSS digest constraint: %s\n",digest);if(EVP_PKEY_get_utf8_string_param(key,OSSL_PKEY_PARAM_RSA_MGF1_DIGEST,mgf,sizeof(mgf),&n)>0)BIO_printf(bio,"PSS MGF1 constraint: %s\n",mgf);if(EVP_PKEY_get_int_param(key,OSSL_PKEY_PARAM_RSA_PSS_SALTLEN,&salt)>0)BIO_printf(bio,"PSS minimum salt: %d bytes\n",salt);}}int ok=tb_bio_buffer(c,bio,out);BIO_free(bio);return ok;}
