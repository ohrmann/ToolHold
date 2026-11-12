/* Development-only synthetic multi-identity fixtures; never linked into the app. */
#include <openssl/pem.h>
#include <openssl/pkcs12.h>
#include <stdio.h>
#include <stdlib.h>
static EVP_PKEY *key(const char *file){FILE *f=fopen(file,"rb");if(!f)exit(2);EVP_PKEY *k=PEM_read_PrivateKey(f,NULL,NULL,NULL);fclose(f);if(!k)exit(3);return k;}
static X509 *cert(const char *file){FILE *f=fopen(file,"rb");if(!f)exit(4);X509 *x=PEM_read_X509(f,NULL,NULL,NULL);fclose(f);if(!x)exit(5);return x;}
int main(void){
 EVP_PKEY *keys[2]={key("leaf-key.pem"),key("root-key.pem")};X509 *certs[2]={cert("leaf.pem"),cert("root.pem")};
 for(int mode=0;mode<5;mode++){
  STACK_OF(PKCS12_SAFEBAG) *bags=NULL;
  for(int i=0;i<2;i++){unsigned char id=(unsigned char)i;PKCS12_SAFEBAG *k=PKCS12_add_key_ex(&bags,keys[i],0,100000,NID_aes_256_cbc,"fixture",NULL,NULL),*x=PKCS12_add_cert(&bags,certs[i]);if(!k||!x)exit(6);PKCS12_add_localkeyid(k,&id,1);PKCS12_add_localkeyid(x,&id,1);PKCS12_add_friendlyname_utf8(k,i?"PUBLIC ROOT":"PUBLIC LEAF",-1);if(mode==1&&i==0)PKCS12_add1_attr_by_txt(k,"1.2.3.4",V_ASN1_UTF8STRING,(unsigned char*)"unknown metadata",16);
   if(mode==4&&i==0){ X509_ATTRIBUTE *duplicate=X509_ATTRIBUTE_create_by_NID(NULL,NID_friendlyName,MBSTRING_ASC,(unsigned char*)"second-name",-1);sk_X509_ATTRIBUTE_push((STACK_OF(X509_ATTRIBUTE)*)PKCS12_SAFEBAG_get0_attrs(k),duplicate); }
  }
  STACK_OF(PKCS7) *safes=NULL;if(!PKCS12_add_safe_ex(&safes,bags,NID_aes_256_cbc,100000,"fixture",NULL,NULL))exit(7);
  PKCS12 *p=PKCS12_add_safes_ex(safes,NID_pkcs7_data,NULL,NULL);if(!p)exit(8);
  if(mode!=2&&!PKCS12_set_mac(p,"fixture",-1,NULL,16,mode==3?1000001:100000,EVP_sha256()))exit(9);
  const char *names[]={"multiple.p12","unknown-attribute.p12","no-mac.p12","excessive-kdf.p12","duplicate-attribute.p12"};FILE *f=fopen(names[mode],"wb");if(!f||!i2d_PKCS12_fp(f,p))exit(10);fclose(f);PKCS12_free(p);sk_PKCS7_pop_free(safes,PKCS7_free);sk_PKCS12_SAFEBAG_pop_free(bags,PKCS12_SAFEBAG_free);
 }
 for(int i=0;i<2;i++){EVP_PKEY_free(keys[i]);X509_free(certs[i]);}return 0;
}
