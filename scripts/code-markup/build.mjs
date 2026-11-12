import {build} from 'esbuild';
import {writeFile,readFile,mkdir,cp,readdir} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import path from 'node:path';
const root=path.resolve(import.meta.dirname,'../..');
const out=path.join(root,'MyApp/CodeMarkupCore/Resources');
await mkdir(out,{recursive:true});
await mkdir(path.join(root,'ThirdPartyNotices/CodeMarkup'),{recursive:true});
for(const [entry,name] of [['engine.mjs','code-markup.js'],['mjml.mjs','code-mjml.js']]){
 await build({entryPoints:[path.join(import.meta.dirname,entry)],bundle:true,platform:'browser',format:'iife',target:'es2022',minify:true,legalComments:'eof',outfile:path.join(out,name),define:{'process.env.NODE_ENV':'"production"'}});
}
const lock=JSON.parse(await readFile(path.join(import.meta.dirname,'package-lock.json'),'utf8'));
const packages=[];
for(const [key,pkg] of Object.entries(lock.packages)){if(!key)continue;packages.push({path:key,version:pkg.version,license:pkg.license,integrity:pkg.integrity,resolved:pkg.resolved});
 const dir=path.join(import.meta.dirname,key);
 for(const name of await readdir(dir).catch(()=>[])){if(/^licen[cs]e|^copying|^notice/i.test(name)){
  const destination=path.join(root,'ThirdPartyNotices/CodeMarkup',key.replaceAll('/','_')+'_'+name);
  await cp(path.join(dir,name),destination,{recursive:true});
 }}
}
let notices = 'Code & Markup — dependency licenses\n\nQuickJS 2026-06-04\n' + await readFile(path.join(root,'Vendor/ToolboxScriptRuntime/LICENSE'),'utf8');
for(const name of (await readdir(path.join(root,'ThirdPartyNotices/CodeMarkup'))).sort()) {
 if(name==='README.md')continue;
 const content=await readFile(path.join(root,'ThirdPartyNotices/CodeMarkup',name),'utf8').catch(()=>null);
 if(content)notices+='\n\n===== '+name+' =====\n'+content;
}
await writeFile(path.join(out,'code-markup-licenses.txt'),notices);
const bundles={};for(const name of ['code-markup.js','code-mjml.js']){const data=await readFile(path.join(out,name));bundles[name]={bytes:data.length,sha256:createHash('sha256').update(data).digest('hex')};}
await writeFile(path.join(out,'code-markup-manifest.json'),JSON.stringify({date:'2026-10-23',quickjs:'2026-06-04',packages,bundles},null,2));
console.log(bundles);
