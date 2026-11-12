#include "internal.h"
static int iterations(TBPKI *c,const ASN1_INTEGER *value){int64_t n=1;if(value&&!ASN1_INTEGER_get_int64(&n,value))return tb_fail(c,3,"Invalid KDF iteration count");if(n<1||n>1000000||c->kdf_work>5000000-n)return tb_fail(c,3,"KDF resource limit reached");c->kdf_work+=(long)n;return 1;}
int tb_pbe_check(TBPKI *c,const X509_ALGOR *alg,int legacy){
 c->error_kind=0;c->error[0]=0;ERR_clear_error();
 const ASN1_OBJECT *oid;int type;const void *value;X509_ALGOR_get0(&oid,&type,&value,alg);int id=OBJ_obj2nid(oid);
 if(type!=V_ASN1_SEQUENCE||!value)return tb_fail(c,2,"Unsupported password protection parameters");const ASN1_STRING *seq=value;const unsigned char *p=ASN1_STRING_get0_data(seq),*end=p+ASN1_STRING_length(seq);int ok=0;
 if(id==NID_pbes2){PBE2PARAM *pbe=d2i_PBE2PARAM(NULL,&p,ASN1_STRING_length(seq));if(!pbe||p!=end){PBE2PARAM_free(pbe);return tb_fail(c,1,"Invalid PBES2 parameters");}
  int cipher=OBJ_obj2nid(pbe->encryption->algorithm);if(cipher!=NID_aes_128_cbc&&cipher!=NID_aes_192_cbc&&cipher!=NID_aes_256_cbc){PBE2PARAM_free(pbe);return tb_fail(c,2,"Supported PBES2 ciphers: AES-128/192/256-CBC");}
  if(OBJ_obj2nid(pbe->keyfunc->algorithm)!=NID_id_pbkdf2||!pbe->keyfunc->parameter||pbe->keyfunc->parameter->type!=V_ASN1_SEQUENCE){PBE2PARAM_free(pbe);return tb_fail(c,2,"Only bounded PBKDF2 is supported");}
  const ASN1_STRING *params=pbe->keyfunc->parameter->value.sequence;p=ASN1_STRING_get0_data(params);end=p+ASN1_STRING_length(params);PBKDF2PARAM *kdf=d2i_PBKDF2PARAM(NULL,&p,ASN1_STRING_length(params));
  if(kdf&&p==end&&kdf->salt&&kdf->salt->type==V_ASN1_OCTET_STRING&&ASN1_STRING_length(kdf->salt->value.octet_string)<=1024){
   int prf=kdf->prf?OBJ_obj2nid(kdf->prf->algorithm):NID_hmacWithSHA1;int64_t length=0;
   ok=(prf==NID_hmacWithSHA1||prf==NID_hmacWithSHA256||prf==NID_hmacWithSHA384||prf==NID_hmacWithSHA512)&&(!kdf->keylength||(ASN1_INTEGER_get_int64(&length,kdf->keylength)&&length==(cipher==NID_aes_128_cbc?16:cipher==NID_aes_192_cbc?24:32)))&&iterations(c,kdf->iter);
  }
  if(ok){int64_t work=0;ASN1_INTEGER_get_int64(&work,kdf->iter);size_t used=strlen(c->protections);snprintf(c->protections+used,sizeof(c->protections)-used,"PBES2 %s / PBKDF2 %s / %lld iterations\n",OBJ_nid2sn(cipher),OBJ_nid2sn(kdf->prf?OBJ_obj2nid(kdf->prf->algorithm):NID_hmacWithSHA1),(long long)work);}
  PBKDF2PARAM_free(kdf);PBE2PARAM_free(pbe);
 }else if(legacy&&(id==NID_pbe_WithSHA1And3_Key_TripleDES_CBC||id==NID_pbe_WithSHA1And2_Key_TripleDES_CBC||id==NID_pbe_WithSHA1And40BitRC2_CBC||id==NID_pbe_WithSHA1And128BitRC2_CBC)){
  PBEPARAM *pbe=d2i_PBEPARAM(NULL,&p,ASN1_STRING_length(seq));ok=pbe&&p==end&&ASN1_STRING_length(pbe->salt)<=1024&&iterations(c,pbe->iter);if(ok){size_t used=strlen(c->protections);snprintf(c->protections+used,sizeof(c->protections)-used,"Legacy protection: %s\n",OBJ_nid2sn(id));}PBEPARAM_free(pbe);
 }else return tb_fail(c,2,"Unsupported protection algorithm; legacy PFX reading requires explicit consent");
 return ok||(c->error_kind?0:tb_fail(c,2,"Unsupported or invalid KDF parameters"));
}
int tb_mac_check_budget(TBPKI *c,const PKCS12 *pfx){const ASN1_OCTET_STRING *mac,*salt;const X509_ALGOR *algorithm;const ASN1_INTEGER *iter;PKCS12_get0_mac(&mac,&algorithm,&salt,&iter,pfx);if(!mac)return 1;int id=OBJ_obj2nid(algorithm->algorithm);return ((id==NID_sha1||id==NID_sha256||id==NID_sha384||id==NID_sha512)&&ASN1_STRING_length(salt)<=1024&&iterations(c,iter))||(c->error_kind?0:tb_fail(c,2,"Unsupported MAC protection profile"));}
static int inventory(TBPKI *c,const STACK_OF(PKCS12_SAFEBAG) *bags,const char *pass,int legacy,int depth){
 if(depth>8)return tb_fail(c,3,"PFX nested safe depth exceeds 8");
 for(int i=0;i<sk_PKCS12_SAFEBAG_num(bags);i++){
  if(!tb_alive(c))return 0;if(c->inventory_count>=TB_MAX_BAGS)return tb_fail(c,3,"PFX contains more than 256 bags");
  const PKCS12_SAFEBAG *bag=sk_PKCS12_SAFEBAG_value(bags,i);int id=PKCS12_SAFEBAG_get_nid(bag),index=c->inventory_count++;c->inventory[index].bag=bag;c->inventory[index].key=-1;c->inventory[index].cert=-1;
  char oid[100];OBJ_obj2txt(oid,sizeof(oid),PKCS12_SAFEBAG_get0_type(bag),1);char *friendly=PKCS12_get_friendlyname((PKCS12_SAFEBAG*)bag);
  const ASN1_TYPE *kid=PKCS12_SAFEBAG_get0_attr(bag,NID_localKeyID);char keyid[129]="";if(kid&&kid->type==V_ASN1_OCTET_STRING){int length=ASN1_STRING_length(kid->value.octet_string);const unsigned char *p=ASN1_STRING_get0_data(kid->value.octet_string);for(int j=0;j<length&&j<64;j++)snprintf(keyid+j*2,3,"%02X",p[j]);}
  snprintf(c->inventory[index].description,1024,"Bag %d · %s\nName: %.400s\nLocal key ID: %s",index+1,oid,friendly?friendly:"(none)",keyid);OPENSSL_free(friendly);
  const STACK_OF(X509_ATTRIBUTE) *attrs=PKCS12_SAFEBAG_get0_attrs(bag);
  int names=0, ids=0; for(int j=0;j<sk_X509_ATTRIBUTE_num(attrs);j++){X509_ATTRIBUTE *a=sk_X509_ATTRIBUTE_value(attrs,j);int nid=OBJ_obj2nid(X509_ATTRIBUTE_get0_object(a));const ASN1_TYPE *v=X509_ATTRIBUTE_get0_type(a,0);if((nid!=NID_friendlyName&&nid!=NID_localKeyID)||X509_ATTRIBUTE_count(a)!=1||!v)c->rewritable=0;else if(nid==NID_friendlyName){if(++names>1||v->type!=V_ASN1_BMPSTRING)c->rewritable=0;}else if(++ids>1||v->type!=V_ASN1_OCTET_STRING)c->rewritable=0;}
  if(id==NID_safeContentsBag){c->rewritable=0;if(!inventory(c,PKCS12_SAFEBAG_get0_safes(bag),pass,legacy,depth+1))return 0;}
  else if(id==NID_certBag&&PKCS12_SAFEBAG_get_bag_nid(bag)==NID_x509Certificate){
   if(c->cert_count>=64)return tb_fail(c,3,"PFX contains more than 64 certificates");X509 *x=PKCS12_SAFEBAG_get1_cert_ex(bag,c->lib,NULL);if(!x)return tb_fail(c,1,"Invalid certificate bag");int length=i2d_X509(x,NULL);if(length<=0||length>262144){X509_free(x);return tb_fail(c,3,"Certificate bag exceeds its size limit");}c->decoded+=(size_t)length;int n=tb_cert_store(c,x);if(n<0)return 0;c->inventory[index].cert=n;
  }else if(id==NID_keyBag||id==NID_pkcs8ShroudedKeyBag){
   if(c->key_count>=16)return tb_fail(c,3,"PFX contains more than 16 keys");PKCS8_PRIV_KEY_INFO *owned=NULL;const PKCS8_PRIV_KEY_INFO *info=NULL;
   if(id==NID_keyBag)info=PKCS12_SAFEBAG_get0_p8inf(bag);
   else{const X509_SIG *encrypted=PKCS12_SAFEBAG_get0_pkcs8(bag);const X509_ALGOR *algorithm;X509_SIG_get0(encrypted,&algorithm,NULL);if(!tb_pbe_check(c,algorithm,legacy))return 0;owned=PKCS12_decrypt_skey_ex(bag,pass,(int)strlen(pass),c->lib,NULL);info=owned;}
   if(!info){PKCS8_PRIV_KEY_INFO_free(owned);return tb_fail(c,4,"Cannot unlock: password incorrect or data damaged");}
   int size=i2d_PKCS8_PRIV_KEY_INFO(info,NULL);if(size<=0||size>65536){PKCS8_PRIV_KEY_INFO_free(owned);return tb_fail(c,3,"Private key bag exceeds 64 KiB");}c->decoded+=(size_t)size;
   EVP_PKEY *key=EVP_PKCS82PKEY_ex(info,c->lib,NULL);PKCS8_PRIV_KEY_INFO_free(owned);if(!key)return tb_fail(c,2,"Unsupported private key bag");if(!tb_algorithm(c,key,0)){EVP_PKEY_free(key);return 0;}int n=tb_key_store(c,key,1);if(n<0)return 0;c->inventory[index].key=n;
  }else c->rewritable=0;
  if(c->decoded>16*1024*1024)return tb_fail(c,3,"PFX decoded content exceeds 16 MiB");
 }
 return 1;
}
int tb_pki_pfx_open(TBPKI *c,const unsigned char *data,size_t size,const char *pass,int legacy,int allow_unverified){
 if(size>8*1024*1024)return tb_fail(c,3,"PFX exceeds 8 MiB");if(c->pfx||c->key_count||c->cert_count)return tb_fail(c,6,"Use a fresh PFX context");
 if(legacy&&!c->legacy)c->legacy=OSSL_PROVIDER_load(c->lib,"legacy");if(legacy&&!c->legacy)return tb_fail(c,2,"Legacy provider unavailable");
 OSSL_LIB_CTX *previous=OSSL_LIB_CTX_set0_default(c->lib);const unsigned char *p=data;int ok=0;STACK_OF(PKCS7) *safes=NULL;c->pfx=d2i_PKCS12(NULL,&p,size);
 if(!c->pfx||p!=data+size){tb_fail(c,1,"Invalid PFX structure or trailing bytes");goto done;}
 if(!tb_mac_check_budget(c,c->pfx))goto done;
 if(PKCS12_mac_present(c->pfx)){
  c->mac_verified=PKCS12_verify_mac(c->pfx,pass,(int)strlen(pass));if(!c->mac_verified&&pass[0]==0)c->mac_verified=PKCS12_verify_mac(c->pfx,NULL,0);
  if(!c->mac_verified){tb_fail(c,4,"Cannot unlock: password incorrect or data damaged");goto done;}
 }else if(!allow_unverified){tb_fail(c,2,"MAC missing: enable Inspect unverified contents explicitly");goto done;}
 safes=PKCS12_unpack_authsafes(c->pfx);if(!safes){tb_fail(c,2,"Unsupported PFX integrity/content profile");goto done;}if(sk_PKCS7_num(safes)>64){tb_fail(c,3,"PFX has too many safes");goto done;}c->rewritable=c->mac_verified;
 for(int i=0;i<sk_PKCS7_num(safes);i++){
  PKCS7 *safe=sk_PKCS7_value(safes,i);STACK_OF(PKCS12_SAFEBAG) *bags=NULL;
  if(PKCS7_type_is_data(safe))bags=PKCS12_unpack_p7data(safe);
  else if(PKCS7_type_is_encrypted(safe)){if(!tb_pbe_check(c,safe->d.encrypted->enc_data->algorithm,legacy))goto done;bags=PKCS12_unpack_p7encdata(safe,pass,(int)strlen(pass));}
  else{tb_fail(c,2,"Unsupported PFX safe content type");goto done;}
  if(!bags){tb_fail(c,4,"Cannot unlock safe: password incorrect or data damaged");goto done;}c->bags[c->bag_stacks++]=bags;
  int decoded_length=ASN1_item_i2d((ASN1_VALUE*)bags,NULL,ASN1_ITEM_rptr(PKCS12_SAFEBAGS));if(decoded_length<0||c->decoded+(size_t)decoded_length>16*1024*1024){tb_fail(c,3,"Decoded PFX exceeds 16 MiB");goto done;}c->decoded+=(size_t)decoded_length;
  if(!inventory(c,bags,pass,legacy,0))goto done;
 }
 ok=tb_alive(c);
 done:sk_PKCS7_pop_free(safes,PKCS7_free);OSSL_LIB_CTX_set0_default(previous);return ok;
}
int tb_pki_pfx_count(TBPKI *c){return c->inventory_count;}
int tb_pki_pfx_key(TBPKI *c,int i){return i>=0&&i<c->inventory_count?c->inventory[i].key:-1;}
int tb_pki_pfx_cert(TBPKI *c,int i){return i>=0&&i<c->inventory_count?c->inventory[i].cert:-1;}
const char *tb_pki_pfx_description(TBPKI *c,int i){return i>=0&&i<c->inventory_count?c->inventory[i].description:"";}
int tb_pki_pfx_verified(TBPKI *c){return c->mac_verified;}
int tb_pki_pfx_rewritable(TBPKI *c){return c->rewritable;}
static int output_pfx(TBPKI *c,PKCS12 *pfx,const char *pass,TBPKIBuffer *out){
 if(!pfx)return tb_fail(c,6,"PFX creation failed");if(!PKCS12_set_mac(pfx,pass,(int)strlen(pass),NULL,16,100000,EVP_sha256())||PKCS12_verify_mac(pfx,pass,(int)strlen(pass))!=1)return tb_fail(c,6,"PFX integrity self-check failed");unsigned char *bytes=NULL;int n=i2d_PKCS12(pfx,&bytes);int ok=n>0&&tb_alive(c)&&tb_buffer(c,bytes,n,out);OPENSSL_clear_free(bytes,n>0?n:0);return ok;
}
int tb_pki_pfx_create(TBPKI *c,int key,int leaf,const int *extras,size_t count,const char *name,const char *pass,TBPKIBuffer *out){
 if(!pass[0])return tb_fail(c,1,"Enter a new PFX password");if(count>64)return tb_fail(c,3,"Too many additional certificates");if(key>=0&&(!tb_pki_key_check(c,key,1)||tb_pki_match(c,leaf,key)!=1))return tb_fail(c,1,"The selected private key must match the leaf certificate");if(leaf>=0&&!tb_cert_valid(c,leaf))return tb_fail(c,1,"Select a leaf certificate");
 STACK_OF(X509) *ca=sk_X509_new_null();if(!ca)return tb_fail(c,6,"Allocation failed");int ok=1;for(size_t i=0;i<count;i++){if(!tb_cert_valid(c,extras[i])||!sk_X509_push(ca,c->certs[extras[i]])){ok=0;break;}}
 OSSL_LIB_CTX *previous=OSSL_LIB_CTX_set0_default(c->lib);PKCS12 *pfx=ok?PKCS12_create_ex(pass,name,key>=0?c->keys[key]:NULL,leaf>=0?c->certs[leaf]:NULL,ca,NID_aes_256_cbc,NID_aes_256_cbc,100000,100000,0,c->lib,NULL):NULL;ok=output_pfx(c,pfx,pass,out);PKCS12_free(pfx);OSSL_LIB_CTX_set0_default(previous);sk_X509_free(ca);return ok;
}
int tb_pki_pfx_repackage(TBPKI *c,const char *pass,TBPKIBuffer *out){
 if(!c->rewritable||!c->mac_verified)return tb_fail(c,2,"Whole-container rewrite is unavailable: unverified, nested or unknown attributes/bags would risk data loss");if(!pass[0])return tb_fail(c,1,"Enter a new PFX password");
 STACK_OF(PKCS12_SAFEBAG) *bags=sk_PKCS12_SAFEBAG_new_null();STACK_OF(PKCS7) *safes=sk_PKCS7_new_null();PKCS12 *pfx=NULL;int ok=bags&&safes,ordinal=0;OSSL_LIB_CTX *previous=OSSL_LIB_CTX_set0_default(c->lib);
 for(int i=0;ok&&i<c->bag_stacks;i++)for(int j=0;ok&&j<sk_PKCS12_SAFEBAG_num(c->bags[i]);j++,ordinal++){
  PKCS12_SAFEBAG *old=sk_PKCS12_SAFEBAG_value(c->bags[i],j),*copy=NULL;int key=c->inventory[ordinal].key;
  if(key>=0){PKCS8_PRIV_KEY_INFO *info=EVP_PKEY2PKCS8(c->keys[key]);if(info)copy=PKCS12_SAFEBAG_create_pkcs8_encrypt_ex(NID_aes_256_cbc,pass,(int)strlen(pass),NULL,16,100000,info,c->lib,NULL);PKCS8_PRIV_KEY_INFO_free(info);
   if(copy){const STACK_OF(X509_ATTRIBUTE) *attrs=PKCS12_SAFEBAG_get0_attrs(old);for(int a=0;ok&&a<sk_X509_ATTRIBUTE_num(attrs);a++){X509_ATTRIBUTE *attr=sk_X509_ATTRIBUTE_value(attrs,a);const ASN1_TYPE *value=X509_ATTRIBUTE_get0_type(attr,0);int nid=OBJ_obj2nid(X509_ATTRIBUTE_get0_object(attr));ok=value&&PKCS12_add1_attr_by_NID(copy,nid,value->type,ASN1_STRING_get0_data(value->value.asn1_string),ASN1_STRING_length(value->value.asn1_string));}}
  }else copy=ASN1_item_dup(ASN1_ITEM_rptr(PKCS12_SAFEBAG),old);
  if(!copy||!ok||!sk_PKCS12_SAFEBAG_push(bags,copy)){PKCS12_SAFEBAG_free(copy);ok=0;}
 }
 if(ok){PKCS7 *safe=PKCS12_pack_p7encdata_ex(NID_aes_256_cbc,pass,(int)strlen(pass),NULL,16,100000,bags,c->lib,NULL);ok=safe&&sk_PKCS7_push(safes,safe);if(!ok)PKCS7_free(safe);}
 if(ok){pfx=PKCS12_init_ex(NID_pkcs7_data,c->lib,NULL);ok=pfx&&PKCS12_pack_authsafes(pfx,safes)&&output_pfx(c,pfx,pass,out);}
 PKCS12_free(pfx);sk_PKCS7_pop_free(safes,PKCS7_free);sk_PKCS12_SAFEBAG_pop_free(bags,PKCS12_SAFEBAG_free);OSSL_LIB_CTX_set0_default(previous);return ok||tb_fail(c,6,"PFX repackage failed");
}

int tb_pki_pfx_bag_der(TBPKI *c,int i,TBPKIBuffer *out){if(i<0||i>=c->inventory_count||c->inventory[i].cert<0)return tb_fail(c,1,"Select a certificate bag");unsigned char *p=NULL;int n=i2d_PKCS12_SAFEBAG(c->inventory[i].bag,&p);int ok=n>0&&tb_buffer(c,p,n,out);OPENSSL_free(p);return ok;}

int tb_pki_pfx_info(TBPKI *c,TBPKIBuffer *out){if(!c->pfx)return tb_fail(c,1,"Open a PFX first");BIO *bio=BIO_new(BIO_s_mem());if(!bio)return tb_fail(c,6,"Allocation failed");if(PKCS12_mac_present(c->pfx)){const ASN1_OCTET_STRING *mac,*salt;const X509_ALGOR *a;const ASN1_INTEGER *iter;PKCS12_get0_mac(&mac,&a,&salt,&iter,c->pfx);int64_t n=1;if(iter)ASN1_INTEGER_get_int64(&n,iter);BIO_printf(bio,"MAC: %s / %lld iterations\n",OBJ_nid2sn(OBJ_obj2nid(a->algorithm)),(long long)n);}else BIO_puts(bio,"MAC: absent\n");BIO_printf(bio,"%sKDF work: %ld iterations total\nDecoded budget usage: %zu bytes\n",c->protections,c->kdf_work,c->decoded);int ok=tb_bio_buffer(c,bio,out);BIO_free(bio);return ok;}
