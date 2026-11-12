/* Public fixtures only. Exercises the application bridge under ASan/UBSan. */
#include "ToolboxPKI.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static unsigned checks=0;
#define CHECK(condition) do { checks++; if(!(condition)){fprintf(stderr,"CHECK_FAILED line=%d\n",__LINE__);return 10;} } while(0)
static int envelope_matrix(void){
 const char *algorithms[]={"P-256","P-384","P-521","Ed25519","RSA","RSA","RSA"};
 const int sizes[]={0,0,0,0,2048,3072,4096};
 const char *labels[]={"CERTIFICATE","CERTIFICATE REQUEST","PUBLIC KEY","PRIVATE KEY","ENCRYPTED PRIVATE KEY","RSA PUBLIC KEY","RSA PRIVATE KEY","EC PRIVATE KEY"};
 for(int a=0;a<7;a++){
  TBPKI *c=tb_pki_new();CHECK(c);int key=tb_pki_key_generate(c,algorithms[a],sizes[a]);CHECK(key>=0);
  TBPKIField field={"CN","public-synthetic.test"};TBPKISAN san={2,"public-synthetic.test"};TBPKIBuffer cert={0};
  CHECK(tb_pki_generate(c,key,0,&field,1,&san,1,0,0,1790000000,1800000000,&cert));
  int certificate=tb_pki_cert_load(c,cert.bytes,cert.count);CHECK(certificate>=0);CHECK(tb_pki_match(c,certificate,key)==1);
  int other=tb_pki_key_generate(c,algorithms[a],sizes[a]);CHECK(other>=0);CHECK(tb_pki_match(c,certificate,other)==0);
  for(int kind=0;kind<3;kind++){
   TBPKIBuffer data={0};const char *label=kind==0?"PUBLIC KEY":kind==1?"PRIVATE KEY":"ENCRYPTED PRIVATE KEY";
   CHECK(kind==0?tb_pki_key_public(c,key,&data):tb_pki_key_private(c,key,"public-test-password",kind==1,&data));
   int matches=0;
   for(int l=0;l<8;l++){TBPKI *probe=tb_pki_new();CHECK(probe);int ok=tb_pki_schema(probe,data.bytes,data.count,labels[l]);matches+=ok!=0;CHECK(!ok||!strcmp(label,labels[l]));tb_pki_free(probe);}
   CHECK(matches==1);
   TBPKI *restored=tb_pki_new();CHECK(restored);int imported=tb_pki_key_load(restored,data.bytes,data.count,label,"public-test-password");CHECK(imported>=0);CHECK(tb_pki_key_check(restored,imported,kind!=0));
   if(kind==2)CHECK(tb_pki_key_load(restored,data.bytes,data.count,label,"wrong-public-password")<0);
   for(int i=0;i<16;i++){size_t length=i<8?(size_t)i:data.count-(size_t)(i-7);CHECK(!tb_pki_schema(restored,data.bytes,length,label));}
   // Bounded mutations may remain valid; acceptance alone is not a sanitizer finding.
   for(int i=0;i<16;i++){size_t offset=((size_t)i*71)%data.count;data.bytes[offset]^=255;tb_pki_key_load(restored,data.bytes,data.count,label,"public-test-password");data.bytes[offset]^=255;}
   tb_pki_free(restored);tb_pki_buffer_free(data);
  }
  tb_pki_buffer_free(cert);tb_pki_free(c);
 }
 printf("PKI_ENVELOPE_MATRIX_PASSED checks=%u bounded_mutations=336 truncations=336\n",checks);return 0;
}
int main(int argc,char **argv){if(argc!=2)return 2;FILE *f=fopen(argv[1],"rb");if(!f)return 3;fseek(f,0,SEEK_END);long n=ftell(f);rewind(f);unsigned char *data=malloc(n);if(fread(data,1,n,f)!=(size_t)n)return 4;fclose(f);
 for(int i=0;i<80;i++){TBPKI *c=tb_pki_new();size_t length=i<40?(size_t)i:(size_t)n;int index=(i*71)%n;unsigned char original=data[index];if(i>=40)data[index]^=255;tb_pki_pfx_open(c,data,length,"fixture",0,0);tb_pki_free(c);data[index]=original;}
 TBPKI *c=tb_pki_new();if(!tb_pki_pfx_open(c,data,n,"fixture",0,0))return 5;TBPKIBuffer out={0};if(!tb_pki_pfx_repackage(c,"changed",&out))return 6;tb_pki_buffer_free(out);tb_pki_free(c);free(data);puts("PKI_BRIDGE_ASAN_UBSAN_PASSED pfx_cases=81");return envelope_matrix();}
