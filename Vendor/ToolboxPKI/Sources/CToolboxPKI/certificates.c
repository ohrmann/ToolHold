#include "internal.h"
static X509_NAME *make_name(const TBPKIField *fields,size_t count){
 if(count>32)return NULL;X509_NAME *name=X509_NAME_new();if(!name)return NULL;
 for(size_t i=0;i<count;i++){size_t n=strlen(fields[i].value);if(n>1024||!X509_NAME_add_entry_by_txt(name,fields[i].oid,MBSTRING_UTF8,(const unsigned char*)fields[i].value,(int)n,-1,0)){X509_NAME_free(name);return NULL;}}return name;
}
static STACK_OF(X509_EXTENSION) *make_extensions(const TBPKISAN *items,size_t count,int profile,int path){
 STACK_OF(X509_EXTENSION) *extensions=sk_X509_EXTENSION_new_null();BASIC_CONSTRAINTS *basic=BASIC_CONSTRAINTS_new();ASN1_BIT_STRING *usage=ASN1_BIT_STRING_new();EXTENDED_KEY_USAGE *eku=NULL;GENERAL_NAMES *names=NULL;int ok=extensions&&basic&&usage;
 if(!ok)goto done;basic->ca=profile==2?0xff:0;
 if(profile==2){basic->pathlen=ASN1_INTEGER_new();ok=basic->pathlen&&ASN1_INTEGER_set(basic->pathlen,path);ASN1_BIT_STRING_set_bit(usage,5,1);ASN1_BIT_STRING_set_bit(usage,6,1);}else{ASN1_BIT_STRING_set_bit(usage,0,1);}
 X509_EXTENSION *x=ok?X509V3_EXT_i2d(NID_basic_constraints,1,basic):NULL;ok=x&&sk_X509_EXTENSION_push(extensions,x);if(!ok){X509_EXTENSION_free(x);goto done;}
 x=X509V3_EXT_i2d(NID_key_usage,1,usage);ok=x&&sk_X509_EXTENSION_push(extensions,x);if(!ok){X509_EXTENSION_free(x);goto done;}
 if(profile!=2){eku=sk_ASN1_OBJECT_new_null();ASN1_OBJECT *oid=OBJ_dup(OBJ_nid2obj(profile==0?NID_server_auth:NID_client_auth));ok=eku&&oid&&sk_ASN1_OBJECT_push(eku,oid);if(!ok){ASN1_OBJECT_free(oid);goto done;}x=X509V3_EXT_i2d(NID_ext_key_usage,0,eku);ok=x&&sk_X509_EXTENSION_push(extensions,x);if(!ok){X509_EXTENSION_free(x);goto done;}}
 if(count){names=sk_GENERAL_NAME_new_null();if(!names){ok=0;goto done;}
  for(size_t i=0;i<count;i++){GENERAL_NAME *g=GENERAL_NAME_new();ASN1_STRING *value=NULL;if(!g){ok=0;goto done;}int type=items[i].type;size_t n=strlen(items[i].value);
   if(type==GEN_IPADD){unsigned char ip[16];int length=inet_pton(AF_INET,items[i].value,ip)==1?4:inet_pton(AF_INET6,items[i].value,ip)==1?16:0;value=ASN1_OCTET_STRING_new();if(!length||!value||!ASN1_STRING_set(value,ip,length)){ASN1_STRING_free(value);GENERAL_NAME_free(g);ok=0;goto done;}}
   else if(type==GEN_DNS||type==GEN_EMAIL||type==GEN_URI){value=ASN1_IA5STRING_new();if(n>1024||!value||!ASN1_STRING_set(value,items[i].value,(int)n)){ASN1_STRING_free(value);GENERAL_NAME_free(g);ok=0;goto done;}}
   else{GENERAL_NAME_free(g);ok=0;goto done;}
   GENERAL_NAME_set0_value(g,type,value);if(!sk_GENERAL_NAME_push(names,g)){GENERAL_NAME_free(g);ok=0;goto done;}
  }
  x=X509V3_EXT_i2d(NID_subject_alt_name,0,names);ok=x&&sk_X509_EXTENSION_push(extensions,x);if(!ok)X509_EXTENSION_free(x);
 }
 done:BASIC_CONSTRAINTS_free(basic);ASN1_BIT_STRING_free(usage);EXTENDED_KEY_USAGE_free(eku);GENERAL_NAMES_free(names);if(!ok){sk_X509_EXTENSION_pop_free(extensions,X509_EXTENSION_free);return NULL;}return extensions;
}
static int sign_init(TBPKI *c,EVP_MD_CTX *md,EVP_PKEY *key){const char *digest=EVP_PKEY_is_a(key,"ED25519")?NULL:EVP_PKEY_is_a(key,"EC")&&EVP_PKEY_get_bits(key)>384?"SHA512":EVP_PKEY_is_a(key,"EC")&&EVP_PKEY_get_bits(key)>256?"SHA384":"SHA256";return EVP_DigestSignInit_ex(md,NULL,digest,c->lib,NULL,key,NULL)>0;}
int tb_pki_generate(TBPKI *c,int key,int csr,const TBPKIField *fields,size_t fields_count,const TBPKISAN *sans,size_t sans_count,int profile,int path,int64_t from,int64_t to,TBPKIBuffer *out){
 if(!tb_pki_key_check(c,key,1)||!tb_alive(c))return 0;
 if(fields_count>32||sans_count>128||profile<0||profile>2||path<0||path>8)return tb_fail(c,1,"Invalid subject or certificate profile");
 if(EVP_PKEY_is_a(c->keys[key],"RSA-PSS"))return tb_fail(c,2,"Restricted RSA-PSS generation is unsupported; inspect or match this key instead");
 X509_NAME *name=make_name(fields,fields_count);STACK_OF(X509_EXTENSION) *extensions=make_extensions(sans,sans_count,profile,path);EVP_MD_CTX *md=EVP_MD_CTX_new();X509 *cert=NULL;X509_REQ *req=NULL;unsigned char *bytes=NULL;int n=0,ok=name&&extensions&&md;
 if(!ok)goto done;
 if(profile==0&&EVP_PKEY_is_a(c->keys[key],"RSA")){ASN1_BIT_STRING *ku=ASN1_BIT_STRING_new();ASN1_BIT_STRING_set_bit(ku,0,1);ASN1_BIT_STRING_set_bit(ku,2,1);X509_EXTENSION *replacement=X509V3_EXT_i2d(NID_key_usage,1,ku);ASN1_BIT_STRING_free(ku);if(!replacement){ok=0;goto done;}X509_EXTENSION *old=sk_X509_EXTENSION_value(extensions,1);sk_X509_EXTENSION_set(extensions,1,replacement);X509_EXTENSION_free(old);}
 if(csr){req=X509_REQ_new_ex(c->lib,NULL);ok=req&&X509_REQ_set_version(req,0)&&X509_REQ_set_subject_name(req,name)&&X509_REQ_set_pubkey(req,c->keys[key])&&X509_REQ_add_extensions(req,extensions)&&sign_init(c,md,c->keys[key])&&X509_REQ_sign_ctx(req,md)>0&&X509_REQ_verify_ex(req,c->keys[key],c->lib,NULL)==1;if(ok)n=i2d_X509_REQ(req,&bytes);}
 else{
  if(from>=to||from<0||to>253402300799LL||to-from>3651LL*86400){ok=0;goto done;}
  unsigned char serial[20];BIGNUM *number=NULL;ASN1_INTEGER *integer=NULL;
  cert=X509_new_ex(c->lib,NULL);ok=cert&&RAND_bytes_ex(c->lib,serial,sizeof(serial),128)==1;
  if(ok){serial[0]=(serial[0]&0x7f)|1;number=BN_bin2bn(serial,sizeof(serial),NULL);integer=number?BN_to_ASN1_INTEGER(number,NULL):NULL;ok=integer&&X509_set_version(cert,2)&&X509_set_serialNumber(cert,integer)&&X509_set_subject_name(cert,name)&&X509_set_issuer_name(cert,name)&&X509_set_pubkey(cert,c->keys[key])&&ASN1_TIME_set(X509_getm_notBefore(cert),(time_t)from)&&ASN1_TIME_set(X509_getm_notAfter(cert),(time_t)to);}
  BN_free(number);ASN1_INTEGER_free(integer);OPENSSL_cleanse(serial,sizeof(serial));
  for(int i=0;ok&&i<sk_X509_EXTENSION_num(extensions);i++)ok=X509_add_ext(cert,sk_X509_EXTENSION_value(extensions,i),-1);
  if(ok){X509V3_CTX extctx;X509V3_set_ctx(&extctx,cert,cert,NULL,NULL,0);X509V3_set_ctx_nodb(&extctx);X509_EXTENSION *ski=X509V3_EXT_conf_nid(NULL,&extctx,NID_subject_key_identifier,"hash");ok=ski&&X509_add_ext(cert,ski,-1);X509_EXTENSION *aki=ok?X509V3_EXT_conf_nid(NULL,&extctx,NID_authority_key_identifier,"keyid:always"):NULL;ok=ok&&aki&&X509_add_ext(cert,aki,-1);X509_EXTENSION_free(ski);X509_EXTENSION_free(aki);}
  ok=ok&&sign_init(c,md,c->keys[key])&&X509_sign_ctx(cert,md)>0&&X509_verify(cert,c->keys[key])==1;if(ok)n=i2d_X509(cert,&bytes);
 }
 ok=ok&&n>0&&tb_alive(c)&&tb_buffer(c,bytes,n,out);
 done:OPENSSL_free(bytes);X509_free(cert);X509_REQ_free(req);X509_NAME_free(name);sk_X509_EXTENSION_pop_free(extensions,X509_EXTENSION_free);EVP_MD_CTX_free(md);return ok||tb_fail(c,c->error_kind==5?5:6,"Certificate/request generation failed");
}
int tb_pki_csr_inspect(TBPKI *c,const unsigned char *data,size_t n,TBPKIBuffer *summary,TBPKIBuffer *public_key){
 if(n>262144){tb_fail(c,3,"CSR exceeds 256 KiB");return -1;}const unsigned char *p=data;X509_REQ *req=X509_REQ_new_ex(c->lib,NULL);BIO *b=NULL;EVP_PKEY *key=NULL;int valid=-1;unsigned char *pub=NULL;
 if(!req||!d2i_X509_REQ(&req,&p,n)||p!=data+n||X509_REQ_get_version(req)!=0){tb_fail(c,1,"Invalid PKCS#10 request or trailing bytes");goto done;}
 key=X509_REQ_get_pubkey(req);b=BIO_new(BIO_s_mem());if(!key||!b){tb_fail(c,2,"Unsupported request public key");goto done;}
 valid=X509_REQ_verify_ex(req,key,c->lib,NULL);if(valid<0){tb_fail(c,2,"Request signature algorithm unsupported");goto done;}
 BIO_printf(b,"Signature: %s\nSubject: ",valid==1?"Valid":"Invalid");X509_NAME_print_ex(b,X509_REQ_get_subject_name(req),0,XN_FLAG_RFC2253);BIO_printf(b,"\nKey: %s (%d bits)\nRequested attributes:\n",EVP_PKEY_get0_type_name(key),EVP_PKEY_get_bits(key));
 int ext_requests=0;
 for(int i=0;i<X509_REQ_get_attr_count(req);i++){X509_ATTRIBUTE *a=X509_REQ_get_attr(req,i);char oid[128];OBJ_obj2txt(oid,sizeof(oid),X509_ATTRIBUTE_get0_object(a),1);int id=OBJ_obj2nid(X509_ATTRIBUTE_get0_object(a));if(id==NID_ext_req||id==NID_ms_ext_req)ext_requests++;BIO_printf(b,"%s%s\n",oid,id==NID_pkcs9_challengePassword?" · sensitive value hidden":"");}
 if(ext_requests>1){tb_fail(c,1,"Conflicting duplicate extension requests");valid=-1;goto done;}
 STACK_OF(X509_EXTENSION) *ext=X509_REQ_get_extensions(req);
 for(int i=0;i<sk_X509_EXTENSION_num(ext);i++){X509_EXTENSION *e=sk_X509_EXTENSION_value(ext,i);for(int j=0;j<i;j++)if(OBJ_cmp(X509_EXTENSION_get_object(e),X509_EXTENSION_get_object(sk_X509_EXTENSION_value(ext,j)))==0){tb_fail(c,1,"Duplicate requested extension");valid=-1;}
  char oid[128];OBJ_obj2txt(oid,sizeof(oid),X509_EXTENSION_get_object(e),1);BIO_printf(b,"Extension %s%s: ",oid,X509_EXTENSION_get_critical(e)?" (critical)":"");if(!X509V3_EXT_print(b,e,0,0))BIO_printf(b,"%d encoded bytes",ASN1_STRING_length(X509_EXTENSION_get_data(e)));BIO_puts(b,"\n");}
 sk_X509_EXTENSION_pop_free(ext,X509_EXTENSION_free);if(valid<0)goto done;
 int length=i2d_PUBKEY(key,&pub);if(length<=0||!tb_buffer(c,pub,length,public_key)||!tb_bio_buffer(c,b,summary)){valid=-1;tb_fail(c,6,"Request presentation failed");}
 done:OPENSSL_free(pub);BIO_free(b);EVP_PKEY_free(key);X509_REQ_free(req);return valid;
}
int tb_pki_schema(TBPKI *c,const unsigned char *data,size_t n,const char *label){
 if(n>262144)return tb_fail(c,3,"Object exceeds 256 KiB");const unsigned char *p=data;int ok=0;
 if(!strcmp(label,"CERTIFICATE")){X509 *x=d2i_X509(NULL,&p,n);ok=x!=NULL;X509_free(x);}
 else if(!strcmp(label,"CERTIFICATE REQUEST")||!strcmp(label,"NEW CERTIFICATE REQUEST")){X509_REQ *x=d2i_X509_REQ(NULL,&p,n);ok=x!=NULL;X509_REQ_free(x);}
 else if(!strcmp(label,"ENCRYPTED PRIVATE KEY")){X509_SIG *x=d2i_X509_SIG(NULL,&p,n);ok=x!=NULL;X509_SIG_free(x);}
 else if(!strcmp(label,"PRIVATE KEY")){PKCS8_PRIV_KEY_INFO *x=d2i_PKCS8_PRIV_KEY_INFO(NULL,&p,n);ok=x!=NULL;PKCS8_PRIV_KEY_INFO_free(x);}
 else if(!strcmp(label,"PUBLIC KEY")){EVP_PKEY *x=d2i_PUBKEY_ex(NULL,&p,n,c->lib,NULL);ok=x!=NULL;EVP_PKEY_free(x);}
 else{int i=tb_pki_key_load(c,data,n,label,"");return i>=0;}
 return (ok&&p==data+n)||tb_fail(c,1,"Object does not match the selected DER schema");
}
int tb_pki_chain(TBPKI *c,int leaf,const int *intermediates,size_t count,const int *roots,size_t roots_count,int policy,const char *host,int64_t at,TBPKIBuffer *report){
 if(!tb_cert_valid(c,leaf)||!roots_count||count+roots_count+1>64){tb_fail(c,1,"Choose a leaf and explicit trusted roots (64 certificates maximum)");return -1;}
 X509_STORE *store=X509_STORE_new();X509_STORE_CTX *ctx=X509_STORE_CTX_new_ex(c->lib,NULL);STACK_OF(X509) *pool=sk_X509_new_null();BIO *b=BIO_new(BIO_s_mem());int valid=-1,ok=store&&ctx&&pool&&b;
 for(size_t i=0;ok&&i<roots_count;i++){if(!tb_cert_valid(c,roots[i])){ok=0;break;}X509 *root=c->certs[roots[i]];EVP_PKEY *pub=X509_get_pubkey(root);ok=pub&&X509_NAME_cmp(X509_get_subject_name(root),X509_get_issuer_name(root))==0&&X509_verify(root,pub)==1&&X509_STORE_add_cert(store,root)==1;EVP_PKEY_free(pub);}
 for(size_t i=0;ok&&i<count;i++)ok=tb_cert_valid(c,intermediates[i])&&sk_X509_push(pool,c->certs[intermediates[i]]);
 if(!ok||!X509_STORE_CTX_init(ctx,store,c->certs[leaf],pool)){tb_fail(c,1,"Invalid root, duplicate anchor, or chain input");goto done;}
 X509_VERIFY_PARAM *param=X509_STORE_CTX_get0_param(ctx);X509_VERIFY_PARAM_set_time(param,(time_t)at);X509_VERIFY_PARAM_set_depth(param,14);X509_VERIFY_PARAM_set_auth_level(param,2);X509_VERIFY_PARAM_set_flags(param,X509_V_FLAG_X509_STRICT|X509_V_FLAG_CHECK_SS_SIGNATURE|X509_V_FLAG_TRUSTED_FIRST);
 if(policy==0||policy==1)X509_VERIFY_PARAM_set_purpose(param,policy==0?X509_PURPOSE_SSL_SERVER:X509_PURPOSE_SSL_CLIENT);
 if(policy==0){unsigned char ip[16];if(!host[0]){tb_fail(c,1,"Enter a TLS hostname or IP address");goto done;}X509_VERIFY_PARAM_set_hostflags(param,X509_CHECK_FLAG_NEVER_CHECK_SUBJECT|X509_CHECK_FLAG_NO_PARTIAL_WILDCARDS);ok=(inet_pton(AF_INET,host,ip)==1||inet_pton(AF_INET6,host,ip)==1)?X509_VERIFY_PARAM_set1_ip_asc(param,host):X509_VERIFY_PARAM_set1_host(param,host,0);if(!ok){tb_fail(c,1,"Invalid TLS host");goto done;}}
 valid=X509_verify_cert(ctx);int error=X509_STORE_CTX_get_error(ctx),depth=X509_STORE_CTX_get_error_depth(ctx);
 BIO_printf(b,"%s\n%s\nError code: %d · chain depth: %d\nTrust: supplied anchors only\nRevocation: not checked (offline)\n",valid==1?"Chain valid under selected policy":"Chain not valid under selected policy",X509_verify_cert_error_string(error),error,depth);
 STACK_OF(X509) *chain=X509_STORE_CTX_get0_chain(ctx);c->chain_count=0;if(sk_X509_num(chain)>16){valid=-1;tb_fail(c,3,"Chain exceeds 16 certificates");goto done;}
 for(int i=0;i<sk_X509_num(chain);i++){for(int j=0;j<c->cert_count;j++)if(X509_cmp(sk_X509_value(chain,i),c->certs[j])==0){c->chain[c->chain_count++]=j;break;}}
for(int i=0;i<sk_X509_num(chain);i++){BIO_printf(b,"%d. ",i+1);X509_NAME_print_ex(b,X509_get_subject_name(sk_X509_value(chain,i)),0,XN_FLAG_RFC2253);BIO_puts(b,"\n");}
 BIO_puts(b,"Unused supplied certificates:\n");int unused=0;for(int j=0;j<c->cert_count;j++){int found=0;for(int i=0;i<sk_X509_num(chain);i++)if(X509_cmp(c->certs[j],sk_X509_value(chain,i))==0)found=1;if(!found){unused++;X509_NAME_print_ex(b,X509_get_subject_name(c->certs[j]),0,XN_FLAG_RFC2253);BIO_puts(b,"\n");}}if(!unused)BIO_puts(b,"None\n");if(sk_X509_num(chain)==1)BIO_puts(b,"Explicit single-certificate trust; this does not make the leaf a CA.\n");
 if(!tb_bio_buffer(c,b,report)){valid=-1;tb_fail(c,6,"Could not produce chain report");}
 done:BIO_free(b);sk_X509_free(pool);X509_STORE_CTX_free(ctx);X509_STORE_free(store);return valid;
}

int tb_pki_chain_count(TBPKI *c){return c->chain_count;}
int tb_pki_chain_certificate(TBPKI *c,int i){return i>=0&&i<c->chain_count?c->chain[i]:-1;}
int tb_pki_cert_hostname(TBPKI *c,int cert,const char *host){if(!tb_cert_valid(c,cert))return 0;unsigned char ip[16];return (inet_pton(AF_INET,host,ip)==1||inet_pton(AF_INET6,host,ip)==1)?X509_check_ip_asc(c->certs[cert],host,0)==1:X509_check_host(c->certs[cert],host,0,X509_CHECK_FLAG_NEVER_CHECK_SUBJECT|X509_CHECK_FLAG_NO_PARTIAL_WILDCARDS,NULL)==1;}
