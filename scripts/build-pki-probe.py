#!/usr/bin/env python3
"""Build a standalone native probe from an existing app build; no project signing changes.
Usage: --platform macos|ios|ios-device --derived-data /tmp/build --output /tmp/probe.app
Device probes require an appropriate existing provisioning profile/signature before installation.
"""
import argparse,pathlib,subprocess,shutil,plistlib,tempfile
p=argparse.ArgumentParser();p.add_argument('--platform',choices=['macos','ios','ios-device'],required=True);p.add_argument('--derived-data',type=pathlib.Path,required=True);p.add_argument('--output',type=pathlib.Path,required=True);p.add_argument('--sandbox',action='store_true',help='macOS: reproduce app sandbox with outgoing-client entitlement');p.add_argument('--source',type=pathlib.Path);p.add_argument('--bundle-id');a=p.parse_args()
root=pathlib.Path(__file__).resolve().parents[1];device=a.platform=='ios-device';ios=a.platform!='macos';products=a.derived_data/'Build/Products'/('Debug-iphoneos' if device else 'Debug-iphonesimulator' if ios else 'Debug');app=products/'ToolHold.app';bundle=a.output
binary=bundle if ios else bundle/'Contents/MacOS';resource=bundle if ios else bundle/'Contents/Resources';binary.mkdir(parents=True,exist_ok=True)
if ios:
 for file in app.iterdir():
  if file.suffix in ['.json','.txt','.js','.bundle']:
   if file.is_dir():shutil.copytree(file,resource/file.name,dirs_exist_ok=True)
   else:shutil.copy2(file,resource)
else:shutil.copytree(app/'Contents/Resources',resource,dirs_exist_ok=True)
shutil.copy2((app if ios else app/'Contents/MacOS')/'ToolHold.debug.dylib',binary)
info={'CFBundleIdentifier':'local.toolbox.pki-'+('uikit' if ios else 'probe'),'CFBundleName':'PKI Probe','CFBundleExecutable':'Probe','CFBundlePackageType':'APPL','CFBundleVersion':'1','CFBundleShortVersionString':'1'}
if a.bundle_id:info['CFBundleIdentifier']=a.bundle_id
if ios:info.update(MinimumOSVersion='18.6',UIDeviceFamily=[1,2],UILaunchScreen={},UIApplicationSceneManifest={'UIApplicationSupportsMultipleScenes':False},CFBundleSupportedPlatforms=['iPhoneOS' if device else 'iPhoneSimulator'])
(bundle/'Info.plist' if ios else bundle/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
sdk=subprocess.check_output(['xcrun','--sdk','iphoneos' if device else 'iphonesimulator' if ios else 'macosx','--show-sdk-path'],text=True).strip()
cmd=['xcrun','swiftc','-parse-as-library','-g','-sdk',sdk,'-target','arm64-apple-ios18.6' if device else 'arm64-apple-ios18.6-simulator' if ios else 'arm64-apple-macos27.0','-I',str(products),'-F',str(products/'PackageFrameworks')]
for name in ['GeneratedModuleMaps','GeneratedModuleMaps-iphonesimulator','GeneratedModuleMaps-iphoneos']:
 for module in (a.derived_data/'Build/Intermediates.noindex'/name).glob('*.modulemap'):cmd+=['-Xcc','-fmodule-map-file='+str(module)]
for path in ['Vendor/ToolboxYAML/Sources/CYaml/include/module.modulemap','Vendor/ToolboxTOML/Sources/CToml/include/module.modulemap']:cmd+=['-Xcc','-fmodule-map-file='+str(root/path)]
cmd += [str(a.source or root/'Tests/NativeHarness'/('PKIUIKitProbe.swift' if ios else 'PKINativeProbe.swift')),str(binary/'ToolHold.debug.dylib'),'-Xlinker','-rpath','-Xlinker','@executable_path','-o',str(binary/'Probe')]
subprocess.run(cmd,check=True)
sign=['codesign','--force','--deep','--sign','-']
if a.sandbox and not ios:
 with tempfile.NamedTemporaryFile(suffix='.plist') as entitlements:
  entitlements.write(plistlib.dumps({'com.apple.security.app-sandbox':True,'com.apple.security.network.client':True,'com.apple.security.files.user-selected.read-write':True}));entitlements.flush()
  subprocess.run(sign+['--entitlements',entitlements.name,str(bundle)],check=True)
else:subprocess.run(sign+[str(bundle)],check=True)
