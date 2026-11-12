import * as sql from 'sql-formatter';
import * as prettier from 'prettier/standalone';
import htmlPlugin from 'prettier/plugins/html';
import cssPlugin from 'prettier/plugins/postcss';
import yamlPlugin from 'prettier/plugins/yaml';
import * as YAML from 'yaml';
import {minify} from 'terser';
import * as html from 'parse5';
import * as css from 'css-tree';
import {Marked} from 'marked';

const limit=4*1024*1024;
class Issue extends Error {constructor(message,status='unsupported',offset=null,length=0){super(message);this.status=status;this.offset=offset;this.length=length;}}
const fail=(message,status='unsupported',offset=null)=>{throw new Issue(message,status,offset);};
const size=s=>{if(s.length>limit||new TextEncoderPolyfill().encode(s).length>limit)fail('Output exceeds the 4 MiB limit.','resourceLimit');return s;};
// A byte count, not an exposed host API or lossy decoder.
class TextEncoderPolyfill {encode(s){let length=0;for(const c of s){const n=c.codePointAt(0);length+=n<128?1:n<2048?2:n<65536?3:4;}return {length};}}
function issue(e,source){
 let offset=Number.isInteger(e.offset)?e.offset:Number.isInteger(e.pos)?e.pos:Array.isArray(e.pos)?e.pos[0]:null;
 let line=e.line??e.lineNumber??e.loc?.start?.line??null;
 let column=e.col!=null?e.col+1:e.loc?.start?.column??null;
 if(e.location?.start){offset=e.location.start.offset;line=e.location.start.line;column=e.location.start.column;}
 if(offset!=null&&(offset<0||offset>source.length))offset=null;
 return {message:String(e.message||'Unable to process input.').slice(0,400),offset,length:offset==null?0:Math.min(e.length||0,source.length-offset),line,column,severity:'error'};
}
function options(r){return {tabWidth:r.indent||2,plugins:[htmlPlugin,cssPlugin,yamlPlugin],embeddedLanguageFormatting:'off',endOfLine:'auto'};}
function parseHTML(source,r,errors=[]){
 const opts={sourceCodeLocationInfo:true,scriptingEnabled:false,onParseError:e=>errors.push(e)};
 if(r.document)return html.parse(source,opts);
 const context=html.defaultTreeAdapter.createElement(r.fragmentContext||'body','http://www.w3.org/1999/xhtml',[]);
 return html.parseFragment(context,source,opts);
}
function walkHTML(root,visit){const work=[[root,0]];let count=0;while(work.length){const [n,d]=work.pop();if(d>128||++count>50000)fail('HTML structure exceeds the preview/processing budget.','resourceLimit');visit(n,d);for(const c of [...(n.childNodes||[]),...(n.content?[n.content]:[])].reverse())work.push([c,d+1]);}}
function htmlFingerprint(root){const a=[];walkHTML(root,(n,d)=>a.push([d,n.nodeName,n.namespaceURI||'',n.value??n.data??'',n.name||'',(n.attrs||[]).map(x=>[x.namespace||'',x.prefix||'',x.name,x.value])]));return JSON.stringify(a);}
function edits(source,changes){for(const e of changes.sort((a,b)=>b.start-a.start)){source=source.slice(0,e.start)+e.value+source.slice(e.end);}return source;}
function compactTag(tag){ // quotes and their whitespace remain exact
 let out='',quote='',space=false;
 for(const c of tag){if(quote){out+=c;if(c===quote)quote='';continue;}if(c==='"'||c==="'"){if(space&&out&&!/[<=]$/.test(out))out+=' ';space=false;quote=c;out+=c;continue;}
 if(/[\t\r\n ]/.test(c)){space=true;continue;}
 if(space&&out&&!/[<=]$/.test(out)&&c!=='>'&&c!=='=')out+=' ';space=false;out+=c;
 }return out;
}
async function htmlFormat(r,notices){
 const errors=[],before=parseHTML(r.source,r,errors);
 if(errors.some(e=>e.code==='duplicate-attribute'))fail('Duplicate attributes cannot be reformatted without data loss.','unsupported',errors.find(e=>e.code==='duplicate-attribute').startOffset);
 const significant=errors.filter(e=>e.code!=='missing-doctype');
 if(significant.length)fail('HTML parser recovery is required: '+significant[0].code,'unsupported',significant[0].startOffset);
 let output;
 if(r.operation==='minify'){
  const changes=[];walkHTML(before,n=>{const loc=n.sourceCodeLocation;for(const part of [loc?.startTag,loc?.endTag])if(part)changes.push({start:part.startOffset,end:part.endOffset,value:compactTag(r.source.slice(part.startOffset,part.endOffset))});});
  output=edits(r.source,changes);
 }else output=await prettier.format(r.source,{...options(r),parser:'html',htmlWhitespaceSensitivity:r.relaxedHTML?'ignore':'strict'});
 const protectedNodes=root=>{const nodes=[];walkHTML(root,n=>{if(['pre','textarea','script','style'].includes(n.tagName)&&n.sourceCodeLocation?.endTag)nodes.push(n);});return nodes;};
 const original=protectedNodes(before),formatted=protectedNodes(parseHTML(output,r));
 if(original.length!==formatted.length)fail('Formatting changed a protected HTML region.');
 const restore=[];for(let i=0;i<original.length;i++){const a=original[i],b=formatted[i];if(a.tagName!==b.tagName)fail('Formatting changed a protected HTML region.');restore.push({start:b.sourceCodeLocation.startTag.endOffset,end:b.sourceCodeLocation.endTag.startOffset,value:r.source.slice(a.sourceCodeLocation.startTag.endOffset,a.sourceCodeLocation.endTag.startOffset)});}
 output=edits(output,restore);
 output=output.replace(/[ \t\r\n]*$/,r.source.match(/[ \t\r\n]*$/)[0]);
 if(!r.relaxedHTML&&htmlFingerprint(before)!==htmlFingerprint(parseHTML(output,r)))fail('Formatting would change HTML text or structure. Input was preserved.');
 if(r.relaxedHTML)notices.push('Layout whitespace may change under author CSS.');
 if(output===r.source)notices.push(r.operation==='minify'?'No safe size reduction.':'Already formatted.');
 return output;
}
function yamlDocs(source){
 const docs=YAML.parseAllDocuments(source,{version:'1.2',schema:'core',strict:true,uniqueKeys:true,keepSourceTokens:true,intAsBigInt:true,prettyErrors:false});
 for(const doc of docs){
  if(doc.directives?.yaml?.version!=='1.2')fail('Only YAML 1.2 Core is supported.','unsupported',0);
  if(doc.errors.length){const e=doc.errors[0];e.offset=e.pos?.[0];e.length=Math.max(0,(e.pos?.[1]||0)-(e.pos?.[0]||0));throw e;}
  const anchors=new Set();
  function check(n,depth=0){if(!n)return;if(depth>128)fail('YAML nesting limit reached.','resourceLimit');
   if(YAML.isAlias(n)){if(!anchors.has(n.source))fail('Alias has no preceding anchor: '+n.source,'invalid',n.range?.[0]);return;}
   if(n.anchor)anchors.add(n.anchor);
   if(YAML.isCollection(n))for(const item of n.items){if(YAML.isPair(item)){check(item.key,depth+1);check(item.value,depth+1);}else check(item,depth+1);}
  }check(doc.contents);
 }return docs;
}
function yamlFingerprint(docs){
 function node(n){if(!n)return null;if(YAML.isAlias(n))return ['alias',n.source];if(YAML.isPair(n))return ['pair',node(n.key),node(n.value)];
 const meta=[n.tag||'',n.anchor||'',n.commentBefore||'',n.comment||''];
 if(YAML.isCollection(n))return [YAML.isMap(n)?'map':'seq',...meta,n.items.map(node)];
 // Numeric raw scalar is intentionally used even for non-finite values.
 return ['scalar',...meta,typeof n.value,typeof n.value==='string'?n.value:n.source??String(n.value)];
 }return JSON.stringify(docs.map(d=>[d.directives?.yaml,node(d.contents),d.commentBefore||'',d.comment||'']));
}
function cssParse(source){let recovery=false;const tree=css.parse(source,{positions:true,parseCustomProperty:false,onParseError:()=>{recovery=true;}});return {tree,recovery};}
function cssFingerprint(tree){let copy=css.toPlainObject(tree);function clean(n){if(Array.isArray(n))return n.map(clean);if(n&&typeof n==='object'){const r={};for(const k of Object.keys(n))if(k!=='loc')r[k]=clean(n[k]);return r;}return n;}return JSON.stringify(clean(copy));}
async function cssFormat(r,notices){
 const {tree,recovery}=cssParse(r.source);if(recovery)fail('Unsupported CSS syntax; parser recovery would be required.');
 // Preserve comments and custom values through exact source ranges for compact output.
 if(r.operation==='minify'){
  const changes=[];css.walk(tree,n=>{if(n.type==='Declaration'&&n.loc){const raw=r.source.slice(n.loc.start.offset,n.loc.end.offset);if(raw.includes('/*')||n.property.startsWith('--'))return;
   changes.push({start:n.loc.start.offset,end:n.loc.end.offset,value:css.generate(n)});
  }});let output=edits(r.source,changes);
  if(!r.source.includes('/*')){
   const custom=[];css.walk(tree,n=>{if(n.type==='Declaration'&&n.property.startsWith('--'))custom.push(r.source.slice(n.loc.start.offset,n.loc.end.offset));});
   output=css.generate(tree);const restore=[];let index=0;css.walk(cssParse(output).tree,n=>{if(n.type==='Declaration'&&n.property.startsWith('--'))restore.push({start:n.loc.start.offset,end:n.loc.end.offset,value:custom[index++]});});output=edits(output,restore);
  }
  if(cssFingerprint(tree)!==cssFingerprint(cssParse(output).tree))fail('Compact output would change CSS tokens.');
  if(output===r.source)notices.push('No safe size reduction.');return output;
 }
 const output=await prettier.format(r.source,{...options(r),parser:'css'});
 // Prettier normalizes harmless number/string spellings; protected custom values and declaration order remain checked.
 const collect=(source)=>{const entries=[];css.walk(cssParse(source).tree,n=>{if(n.type==='Declaration')entries.push([n.property,n.important,n.property.startsWith('--')?source.slice(n.value.loc.start.offset,n.value.loc.end.offset):css.generate(n.value)]);});return JSON.stringify(entries);};
 if(collect(output)!==collect(r.source))fail('Formatting would alter a CSS value. Input was preserved.');return output;
}

const tags=new Set('html head body title style div span p a br hr h1 h2 h3 h4 h5 h6 article aside main section header footer nav address blockquote pre code em strong b i u s del ins mark small sub sup abbr cite q time ul ol li dl dt dd table thead tbody tfoot tr td th caption colgroup col img picture figure figcaption details summary button label input textarea select option optgroup fieldset legend form center font'.split(' '));
const attributes=new Set('id class title lang dir role aria-label aria-hidden colspan rowspan scope headers align valign width height bgcolor border cellpadding cellspacing color face size start reversed type value checked selected placeholder disabled alt name open'.split(' '));
const cssFunctions=new Set('rgb rgba hsl hsla hwb lab lch oklab oklch color color-mix calc min max clamp var env linear-gradient radial-gradient conic-gradient repeating-linear-gradient repeating-radial-gradient translate translatex translatey translatez translate3d scale scalex scaley scale3d rotate rotatex rotatey rotatez matrix matrix3d skew perspective cubic-bezier steps counter counters attr format local fit-content minmax repeat'.split(' '));
const rules=new Set(['media','supports','container','layer','keyframes','-webkit-keyframes']);
// Only an explicit, snapshot-scoped action enables HTTPS subresources. Never allow
// credentials, relative URLs, data documents or script schemes through this gate.
const remoteURL=s=>/^https:\/\/[^\s/?#@\\]+(?:[/?#][^\s\\]*)?$/i.test(s);
function safeCSS(source,inline,notices,external=false){
 try{
 const tree=css.parse(source,{context:inline?'declarationList':'stylesheet',parseCustomProperty:true});
 css.walk(tree,{enter(n,item,list){
  if(n.type==='Raw'){if(list)list.remove(item);notices.add('Unparsed CSS blocked.');return css.walk.skip;}
  if(n.type==='Atrule'&&!rules.has(n.name.toLowerCase())){
   let allowed=external&&n.name.toLowerCase()==='font-face';
   if(external&&n.name.toLowerCase()==='import'&&n.prelude){
    const first=n.prelude.children?.first;
    allowed=!!first&&['Url','String'].includes(first.type)&&remoteURL(first.value);
   }
   if(!allowed){if(list)list.remove(item);notices.add('External or unsupported CSS rules blocked.');return css.walk.skip;}
  }
  if(n.type==='Declaration'){
   let unsafe=/^(behavior|-moz-binding|(?:-webkit-)?animation.*|(?:-webkit-)?transition.*)$/i.test(n.property)||(!external&&/^src$/i.test(n.property))||n.property.includes('\\');
   css.walk(n.value,x=>{if(x.type==='Url'&&!(external&&remoteURL(x.value))||x.type==='Raw'||(x.type==='Function'&&!cssFunctions.has(x.name.toLowerCase()))||x.type==='String'&&/^(?:https?:|data:|file:|\/\/)/i.test(x.value))unsafe=true;});
   if(unsafe){list.remove(item);notices.add('Resource-loading or unsupported CSS values blocked.');return css.walk.skip;}
  }
 }});return css.generate(tree);
 }catch{notices.add('Unparseable CSS blocked.');return '';}
}
const escape=s=>String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
function preview(source,r){
 const external=r.allowsExternalResources===true;
 if(r.tool==='preview'&&!r.document){
  const fragments=parseHTML(source,r);const serialized=html.serialize(fragments);
  const wrappers={body:['',''],table:['<table>','</table>'],tbody:['<table><tbody>','</tbody></table>'],tr:['<table><tbody><tr>','</tr></tbody></table>'],select:['<select>','</select>']};
  const w=wrappers[r.fragmentContext||'body']||wrappers.body;source='<html><head></head><body>'+w[0]+serialized+w[1]+'</body></html>';
 }
 const errors=[],root=html.parse(source,{scriptingEnabled:false,onParseError:e=>errors.push(e)});
 const notices=new Set(),images=[];let count=0;
 const render=(n,depth=0)=>{
  if(n.tagName && (++count>50000||depth>128))fail('Preview structure limit reached.','resourceLimit');
  if(n.nodeName==='#text')return escape(n.value);
  if(n.nodeName==='#comment'||n.nodeName==='#documentType')return '';
  if(n.nodeName==='#document')return (n.childNodes||[]).map(x=>render(x,depth)).join('');
  const tag=n.tagName;
  if(external&&tag==='link'&&n.namespaceURI==='http://www.w3.org/1999/xhtml'){
   const attrs=Object.fromEntries((n.attrs||[]).map(a=>[a.name,a.value]));
   if(attrs.rel?.toLowerCase()==='stylesheet'&&remoteURL(attrs.href||''))
    return '<link rel="stylesheet" href="'+escape(attrs.href)+'" referrerpolicy="no-referrer">';
  }
  if(!tags.has(tag)||n.namespaceURI!=='http://www.w3.org/1999/xhtml'){notices.add('Active, external or unsupported HTML elements blocked.');return '';}
  if(tag==='style'){
   const text=(n.childNodes||[]).map(x=>x.value||'').join('');const clean=safeCSS(text,false,notices,external);
   // CSS serialization can contain literal </style inside a string. Never permit a raw-text escape.
   return '<style>'+clean.replace(/</g,'\\3c ')+'</style>';
  }
  let attrs='';let sourceRef='';
  for(const a of n.attrs||[]){
   if(a.namespace||a.prefix){notices.add('Foreign attributes blocked.');continue;}
   if(a.name==='style'){const value=safeCSS(a.value,true,notices,external);if(value)attrs+=' style="'+escape(value)+'"';}
   else if(tag==='img'&&a.name==='src')sourceRef=a.value;
   else if(a.name==='href'&&tag==='a'&&/^#[A-Za-z0-9_.:-]*$/.test(a.value))attrs+=' href="'+escape(a.value)+'"';
   else if(attributes.has(a.name)&&!['open'].includes(a.name))attrs+=' '+a.name+'="'+escape(a.value)+'"';
   else notices.add('Links, event handlers and resource attributes blocked.');
  }
  if(tag==='img'&&sourceRef){
   if(external&&remoteURL(sourceRef)){attrs+=' src="'+escape(sourceRef)+'" referrerpolicy="no-referrer"';}
   else if(images.length>=16){notices.add('Additional images blocked (16-image limit).');}
   else{const id='image'+images.length;images.push({id,reference:sourceRef});attrs+=' src="toolbox-preview://'+r.nonce+'/'+id+'"';}
  }
  if(['input','textarea','select','button'].includes(tag))attrs+=' disabled="disabled"';
  const children=(n.childNodes||[]).map(x=>render(x,depth+1)).join('');
  if(['img','br','hr','col','input'].includes(tag))return '<'+tag+attrs+'>';
  return '<'+tag+attrs+'>'+children+'</'+tag+'>';
 };
 let document=render(root);
 const network=external?' https:':'';
 const head='<meta name="viewport" content="width=device-width, initial-scale=1"><meta name="referrer" content="no-referrer"><meta http-equiv="Content-Security-Policy" content="default-src \'none\'; script-src \'none\'; connect-src \'none\'; object-src \'none\'; frame-src \'none\'; base-uri \'none\'; form-action \'none\'; style-src \'unsafe-inline\''+network+'; img-src toolbox-preview:'+network+'; font-src '+(external?'https:':"'none'")+'; media-src \'none\'">';
 if(external)notices.add('External HTTPS images, stylesheets and fonts may contact their servers. Permission resets when Input changes. Scripts, frames and navigation remain blocked.');
 document=document.replace('<head>','<head>'+head+'<style>html,body{overflow-anchor:none!important}</style>');
 if(errors.some(e=>e.code!=='missing-doctype'))notices.add('HTML parser recovery was used for preview.');
 return {preview:size('<!doctype html>'+document),images,notices:[...notices]};
}

function maskSQL(source){
 let out='',i=0;
 while(i<source.length){const start=i,c=source[i];
  if(source.startsWith('--',i)){while(i<source.length&&source[i]!=='\n')i++;}
  else if(source.startsWith('/*',i)){i+=2;let depth=1;while(i<source.length&&depth){if(source.startsWith('/*',i)){depth++;i+=2;}else if(source.startsWith('*/',i)){depth--;i+=2;}else i++;}}
  else if(c==="'"||c==='"'||c==='`'||c==='['){const end=c==='['?']':c;i++;while(i<source.length){if(source[i]==='\\'){i+=2;continue;}if(source[i++]===end){if(source[i]===end){i++;continue;}break;}}}
  else if(c==='$'){const m=source.slice(i).match(/^\$(?:[A-Za-z_][A-Za-z0-9_]*)?\$/);if(m){const end=source.indexOf(m[0],i+m[0].length);i=end<0?source.length:end+m[0].length;}else{out+=c;i++;continue;}}
  else {out+=c;i++;continue;}
  out+=' '.repeat(Math.min(source.length,i)-start);
 }return out;
}

async function process(r){
 const notices=[],diagnostics=[];let output='';
 if(!r.source)return {status:'ready',notices,diagnostics};
 if(r.source.length>262144)fail('Input exceeds 262144 UTF-16 units.','resourceLimit');
 switch(r.tool){
 case 'sql':{
  // Only lexical tokens outside quotes/comments are examined for unsupported batch grammar.
  const clean=maskSQL(r.source);
  if(/\bDELIMITER\b|\bCREATE\s+(?:OR\s+REPLACE\s+)?(?:PROCEDURE|FUNCTION)\b/i.test(clean))fail('Stored procedures and custom DELIMITER are not supported by this formatter.');
  output=sql.format(r.source,{language:r.dialect||'sql',tabWidth:r.indent||2,keywordCase:r.keywordCase||'preserve'});break;
 }
 case 'yaml':{
  const docs=yamlDocs(r.source);for(const d of docs)for(const w of d.warnings)diagnostics.push({...issue(w,r.source),severity:'warning'});
  if(r.operation==='validate')return {status:diagnostics.length?'successWithWarnings':'success',diagnostics,notices};
  output=await prettier.format(r.source,{...options(r),parser:'yaml'});
  if(yamlFingerprint(docs)!==yamlFingerprint(yamlDocs(output)))fail('Formatting would change YAML scalar spelling, comments or structure. Input was preserved.');break;
 }
 case 'html':output=await htmlFormat(r,notices);break;
 case 'css':output=await cssFormat(r,notices);break;
 case 'javascript':{
  const result=await minify(r.source,{compress:false,mangle:false,module:!!r.module,keep_fnames:true,keep_classnames:true,format:{beautify:r.operation!=='minify',comments:'all',indent_level:r.indent||2}});output=result.code;
  // A second parser check does not execute code.
  const ast=async source=>(await minify(source,{compress:false,mangle:false,module:!!r.module,format:{spidermonkey:true,code:false}})).ast;
  const normalize=n=>{if(Array.isArray(n))return n.filter(x=>x?.type!=='EmptyStatement').map(normalize);if(n&&typeof n==='object'){const v={};for(const k of Object.keys(n))if(!['loc','start','end','raw'].includes(k))v[k]=normalize(n[k]);return v;}return Object.is(n,-0)?['negative-zero']:n;};
  if(JSON.stringify(normalize(await ast(r.source)))!==JSON.stringify(normalize(await ast(output))))fail('Printing would change JavaScript structure. Input was preserved.');break;
 }
 case 'markdown':{
  output=new Marked({gfm:r.gfm!==false,breaks:false}).parse(r.source);
  output='<html><head><style>'+markdownCSS+'</style></head><body>'+output+'</body></html>';break;
 }
 case 'preview':output=r.source;break;
 case 'mjml':{
  // XML-like MJML is parsed as XML by its compiler, never executed. HTML scanner identifies actual include tags outside comments/raw text.
  const root=html.parseFragment(r.source,{scriptingEnabled:false});walkHTML(root,n=>{if(n.tagName==='mj-include')fail('mj-include is not supported. Paste the complete MJML document.','unsupported',n.sourceCodeLocation?.startOffset);});
  const value=await globalThis.ToolboxMJML(r.source,{validationLevel:'strict',ignoreIncludes:true,useMjmlConfigOptions:false,fonts:{},minify:false,keepComments:true});
  output=value.html;for(const e of value.errors||[])diagnostics.push({message:e.message,line:e.line||null,column:null,offset:null,length:0,severity:'warning'});break;
 }
 default:fail('Unknown operation.');
 }
 size(output);
 const result={status:diagnostics.length?'successWithWarnings':'success',output,notices,diagnostics};
 if(['markdown','preview','mjml'].includes(r.tool)){
  try{Object.assign(result,preview(output,r));if(r.tool==='markdown')result.output=result.preview.replace(/<meta http-equiv="Content-Security-Policy"[^>]*>/,'');}
  catch(e){if(e.status==='resourceLimit'){result.notices.push(e.message);result.preview=null;}else throw e;}
 }
 return result;
}
const markdownCSS=':root{color-scheme:light dark}body{font:16px -apple-system,sans-serif;line-height:1.55;margin:24px;overflow-wrap:anywhere}pre{overflow:auto;padding:12px;background:#80808018}code{font-family:ui-monospace,monospace}table{border-collapse:collapse}td,th{border:1px solid #888;padding:6px}img{max-width:100%}blockquote{border-left:3px solid #888;padding-left:12px}';
globalThis.ToolboxMarkup=async r=>{try{return await process(r);}catch(e){return {status:e.status||(['InternalError','RangeError'].includes(e.name)?'resourceLimit':e.name==='TypeError'?'engineUnavailable':'invalid'),output:null,preview:null,notices:[],diagnostics:(Array.isArray(e.errors)?e.errors.slice(0,100):[e]).map(x=>issue(x,r.source))};}};
