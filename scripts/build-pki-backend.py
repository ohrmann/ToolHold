#!/usr/bin/env python3
"""Offline reproducible Apple libcrypto slices. Requires verified vendored source; never downloads."""
import pathlib,hashlib,tarfile,subprocess,concurrent.futures,os,shutil,argparse,json
root=pathlib.Path(__file__).resolve().parents[1];vendor=root/'Vendor/ToolboxPKI'
version='4.0.3';digest='325b5c806167c13b40b1ffeadfe0248197c00eccc4cf123ec1e28d2d2fd216d9'
p=argparse.ArgumentParser();p.add_argument('--work',default='/tmp/toolbox-pki-build');p.add_argument('--jobs',type=int,default=6);args=p.parse_args()
work=pathlib.Path(args.work);work.mkdir(parents=True,exist_ok=True)
archive=vendor/f'upstream/openssl-{version}.tar.gz';assert hashlib.sha256(archive.read_bytes()).hexdigest()==digest
source=work/f'openssl-{version}'
if not source.exists():subprocess.run(['tar','-xzf',str(archive),'-C',str(work)],check=True)
flags=['no-shared','no-module','no-apps','no-tests','no-autoload-config','no-dso','no-pinshared','no-http','no-sock','no-ssl','no-tls','no-dtls','no-quic','no-docs']
slices=[('mac-arm64','darwin64-arm64-cc','macosx','arm64','-mmacosx-version-min=14.0'),('mac-x86_64','darwin64-x86_64-cc','macosx','x86_64','-mmacosx-version-min=14.0'),('ios-arm64','ios64-xcrun','iphoneos','arm64','-miphoneos-version-min=17.0'),('sim-arm64','iossimulator-arm64-xcrun','iphonesimulator','arm64','-mios-simulator-version-min=17.0'),('sim-x86_64','iossimulator-x86_64-xcrun','iphonesimulator','x86_64','-mios-simulator-version-min=17.0')]
def build(item):
 name,target,sdk,arch,deployment=item;path=work/name;install=work/(name+'-install');path.mkdir(exist_ok=True)
 if (install/'lib/libcrypto.a').exists():return
 env=os.environ.copy();env['CC']='xcrun -sdk '+sdk+' clang';env['CFLAGS']='-O2 -fvisibility=hidden '+deployment;env['SDKROOT']=subprocess.check_output(['xcrun','--sdk',sdk,'--show-sdk-path'],text=True).strip()
 with (work/(name+'.log')).open('w') as log:
  for cmd in [['perl',str(source/'Configure'),target,*flags,'--prefix='+str(install),'--libdir=lib'],['make','-j'+str(args.jobs),'build_libs'],['make','install_dev']]:subprocess.run(cmd,cwd=path,env=env,stdout=log,stderr=subprocess.STDOUT,check=True)
 print('BUILT',name,flush=True)
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:list(pool.map(build,slices))
libraries=[]
for group,names in [('mac',['mac-arm64','mac-x86_64']),('ios',['ios-arm64']),('sim',['sim-arm64','sim-x86_64'])]:
 dst=work/('merged-'+group);dst.mkdir(exist_ok=True);libs=[work/(n+'-install/lib/libcrypto.a') for n in names]
 subprocess.run(['xcrun','lipo','-create',*map(str,libs),'-output',str(dst/'libToolboxCrypto.a')],check=True)
 shutil.copytree(work/(names[0]+'-install/include'),dst/'include',dirs_exist_ok=True)
 (dst/'include/toolbox_crypto_anchor.h').write_text('#define TOOLBOX_CRYPTO_VERSION "'+version+'"\n')
 (dst/'include/module.modulemap').write_text('module ToolboxCrypto { header "toolbox_crypto_anchor.h" export * }\n')
 libraries+=['-library',str(dst/'libToolboxCrypto.a'),'-headers',str(dst/'include')]
output=vendor/'ToolboxCrypto.xcframework'
if output.exists():shutil.rmtree(output)
subprocess.run(['xcodebuild','-create-xcframework',*libraries,'-output',str(output)],check=True)
(vendor/'backend-manifest.json').write_text(json.dumps({'version':version,'sha256':digest,'source':'https://github.com/openssl/openssl/releases/download/openssl-'+version+'/openssl-'+version+'.tar.gz','flags':flags,'slices':[x[0] for x in slices]},indent=2)+'\n')
