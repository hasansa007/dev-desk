#!/usr/bin/env python3
"""The clickable prototype: Console × Focus, a project strip with its own focus per project, Home, and a working dock."""
import os
import re
from gen2 import d_work, d_findings, d_sessions, d_ideation, d_diagrams
from gen4 import with_strip, e_home, expand_rail

DEST = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "console-focus-prototype.html")


def body(html):
    x = html.split("<x-dc>")[1].split("</x-dc>")[0]
    x = re.sub(r"<helmet>.*?</helmet>", "", x, flags=re.S).replace("{{accent}}", "#7FD19B")
    x = x.replace('<span style="font-weight: 600;">studyhub</span><span style="color: #8E96A3;">~/Developer/studyhub</span>',
                  '<span data-pname style="font-weight: 600;">studyhub</span><span data-ppath style="color: #8E96A3;">~/Developer/studyhub</span>')
    return x


SCREENS = {"Work": d_work(True), "Work+dock": d_work("open"), "Findings": d_findings(), "Sessions": d_sessions(), "Ideation": d_ideation(), "Diagrams": d_diagrams()}
TOGGLE_N = '<button data-railtoggle aria-label="Show labels" title="Show labels (⇧⌘S)" style="width: 44px; height: 32px; border: 0; border-radius: 8px; background: transparent; color: #8E96A3; font-size: 14px;">»</button>'
TOGGLE_W = '<button data-railtoggle aria-label="Hide labels" title="Hide labels (⇧⌘S)" style="height: 32px; display: flex; align-items: center; gap: 10px; padding: 0 10px; border: 0; border-radius: 8px; background: transparent; color: #8E96A3; font-size: 12px; text-align: left;"><span style="width: 20px; text-align: center; font-size: 14px;">«</span><span>Hide labels</span></button>'


def with_toggle(html, btn):
    a = html.index('<button aria-label="Settings"')
    return html[:a] + btn + html[a:]


sections = ""
for k, v in SCREENS.items():
    base = with_strip(v)
    sections += f'<section data-screen="{k}" data-rail="narrow" style="display:none">{body(with_toggle(base, TOGGLE_N))}</section>\n'
    sections += f'<section data-screen="{k}" data-rail="wide" style="display:none">{body(with_toggle(expand_rail(base), TOGGLE_W))}</section>\n'
sections += f'<section data-screen="Home" style="display:none">{body(e_home())}</section>\n'

CSS = """html,body{margin:0;height:100%;background:#08090B;overflow:hidden}button{font:inherit;cursor:pointer}a{color:#7FD19B}
#stage{width:1440px;height:900px;transform-origin:0 0;position:absolute;left:0;top:0;overflow:hidden}
[data-strip] button{transition:border-radius .12s}
.pj{position:relative;width:36px;height:36px;border:0;border-radius:10px;background:#16191E;color:#C9CDD4;font-family:ui-monospace,'SF Mono','Geist Mono',monospace;font-size:11.5px;font-weight:600;display:flex;align-items:center;justify-content:center}
.pj.on{color:#0F1114}.pj:hover{border-radius:14px}
.pj i{position:absolute;left:-10px;top:8px;width:4px;height:20px;border-radius:0 3px 3px 0;background:transparent}.pj.on i{background:#E4E7EB}
.pj em{position:absolute;bottom:-4px;right:-5px;min-width:16px;height:16px;box-sizing:border-box;padding:0 4px;border-radius:8px;border:2px solid #0B0D10;background:#E7C067;color:#0F1114;font:700 10px/12px system-ui;font-style:normal}
.pj u{position:absolute;bottom:-3px;right:-3px;width:10px;height:10px;box-sizing:border-box;border-radius:5px;border:2px solid #0B0D10;background:#7FD19B}
#dock{position:absolute;right:0;bottom:0;font-family:ui-monospace,'SF Mono','Geist Mono',monospace;font-size:12px;color:#E4E7EB;background:#0B0D10;border-top:1px solid #343A44;display:flex;flex-direction:column}
#dock .bar{height:34px;flex-shrink:0;display:flex;align-items:center;gap:4px;padding:0 10px;background:#14171B;border-bottom:1px solid #1E2228;font-size:11.5px}
#dock .bar button{height:24px;padding:0 10px;border:0;border-radius:4px;background:transparent;color:#8E96A3;font-size:11.5px;display:flex;align-items:center;gap:7px;white-space:nowrap}
#dock .bar button.on{background:#1B1F25;color:#E4E7EB}
#dock .bar button.plus{width:24px;height:22px;padding:0;justify-content:center;border:1px solid #343A44;background:#1B1F25;color:#E4E7EB;font-size:14px}
#dock .seg{display:flex;gap:2px;padding:2px;border-radius:5px;background:#0B0D10;margin-left:auto}
#dock .dot{width:6px;height:6px;border-radius:3px;display:inline-block;flex-shrink:0}
#dock .panes{height:216px;display:flex}
#dock .pane{flex:1 1 0;min-width:0;display:flex;flex-direction:column;border-right:1px solid #262B33}
#dock .ph{height:28px;flex-shrink:0;display:flex;align-items:center;gap:8px;padding:0 12px;border-bottom:1px solid #1E2228;font-size:11.5px;color:#C9CDD4;white-space:nowrap;overflow:hidden}
#dock .ph button{margin-left:auto;border:0;background:transparent;color:#8E96A3}
#dock .pb{flex:1;overflow:hidden;padding:9px 12px;line-height:1.5;color:#D7DBE0;white-space:pre-wrap}
#iconmenu{display:none;position:absolute;left:128px;top:50px;width:260px;z-index:12;flex-direction:column;gap:2px;padding:6px;border:1px solid #343A44;border-radius:6px;background:#1B1F25;box-shadow:0 12px 40px rgba(0,0,0,.55);font-size:12px;color:#E4E7EB}
#iconmenu>button{min-height:36px;padding:4px 10px;border:0;border-radius:4px;background:transparent;color:#E4E7EB;text-align:left;font-size:12px}#iconmenu>button:hover{background:#262B33}
#iconmenu small{display:block;font-size:11px;color:#8E96A3;margin-top:2px}#iconmenu .lab{padding:4px 10px 2px;font-size:11px;text-transform:uppercase;letter-spacing:.05em;color:#8E96A3;font-family:ui-monospace,monospace}
#dock .menu{position:absolute;left:0;width:340px;z-index:9;display:flex;flex-direction:column;gap:2px;padding:6px;border:1px solid #343A44;border-radius:6px;background:#1B1F25;box-shadow:0 12px 40px rgba(0,0,0,.55)}
#dock .menu button{height:auto;min-height:42px;width:100%;padding:4px 10px;gap:10px;color:#E4E7EB;text-align:left;font-size:12px;white-space:normal}
#dock .menu button:hover{background:#262B33}
#dock .menu small{display:block;font-size:11px;color:#8E96A3;margin-top:2px}
#dock .menu .lab{padding:4px 10px 2px;font-size:11px;text-transform:uppercase;letter-spacing:.05em;color:#8E96A3}
#dock .menu hr{border:0;height:1px;background:#343A44;margin:4px 2px;width:100%}"""

JS = r"""
const TABS=["Work","Findings","Sessions","Ideation","Diagrams"];
const HOME_ICON='<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M4 11l8-7 8 7M6 10v9h12v-9M10 19v-5h4v5"></path></svg>';
let N=10;
const P={
 "studyhub":{code:"SH",color:"#9CC0FF",path:"~/Developer/studyhub",tab:"Work",open:false,sessions:[
   {id:1,t:"#42 course-list · Codex",dot:"#7FD19B",shown:true,body:"10:49 Verifier finished: 18 unit checks passed.\n11:07 Reviewer flagged a missing cleanup on unmount.\n11:12 Codex patched useScrollRestore.ts\n▍ Implementing · phase 3 of 4"},
   {id:2,t:"#57 exam-recovery · Claude",dot:"#E7C067",wait:true,shown:true,body:"09:58 Claude finished the investigation and wrote the plan.\nWaiting for a decision before implementation continues\n[The run's question appears here.]\n▍"},
   {id:3,t:"zsh",dot:"#5A606A",shown:false,body:"studyhub main ❯ ▍"}],
   resume:[{k:"r1",t:"#66 thumbnail-cache · Claude",title:"#66 Cache lesson thumbnails",sub:"Paused at Planned · feat/66-thumbnail-cache",dot:"#E7C067",body:"feat/66-thumbnail-cache · ~/.devdesk/wt/studyhub-66\nResumed at Planned · phase 2 of 4\n▍"},
           {k:"r2",t:"ideation run",title:"Ideation run",sub:"Was running when Dev Desk last closed",dot:"#5A606A",body:"Running the door again…\n▍"}]},
 "dev-desk":{code:"DS",color:"#F2A7C3",path:"~/Developer/skills/dev-desk",tab:"Findings",open:true,sessions:[
   {id:4,t:"zsh",dot:"#7FD19B",shown:true,body:"dev-desk main ❯ apps/desk/install.sh\n[build output]\n▍"}],resume:[]},
 "studyhub-deploy":{code:"SD",color:"#B8A7F2",path:"~/Developer/studyhub-deploy",tab:"Diagrams",open:false,sessions:[],resume:[]}
};
const S={cur:"studyhub",scope:"project",menu:false,homeOpen:false};
const esc=s=>s.replace(/&/g,"&amp;").replace(/</g,"&lt;");
const proj=()=>P[S.cur];
const isHome=()=>S.cur==="home";
function sessions(){ if(isHome()||S.scope==="all") return Object.entries(P).flatMap(([n,p])=>p.sessions.map(x=>({x,n}))); return proj().sessions.map(x=>({x,n:null})); }
function dockOpen(){return isHome()?S.homeOpen:proj().open;}
function setOpen(v){ if(isHome())S.homeOpen=v; else proj().open=v; }
function renderStrip(){
 let h='<button class="pj'+(isHome()?" on":"")+'" style="'+(isHome()?"background:#7FD19B":"")+'" data-go="home" aria-label="Home" title="Home — what needs you"><i></i>'+HOME_ICON+'</button><div style="height:1px;width:28px;background:#262B33"></div>';
 for(const [n,p] of Object.entries(P)){const need=p.sessions.filter(x=>x.wait).length;
  h+='<button class="pj'+(S.cur===n?" on":"")+'" style="'+(S.cur===n?"background:"+p.color:"color:"+p.color)+'" data-go="'+n+'" aria-label="'+n+'" title="'+n+'"><i></i>'+p.code+(need?'<em>'+need+'</em>':(p.sessions.length?'<u></u>':''))+'</button>';}
 h+='<div style="flex-grow:1"></div><button class="pj" style="background:transparent;border:1px dashed #454A53;color:#8E96A3;font-size:16px" aria-label="Open project" title="Open project">+</button>';
 document.querySelectorAll("[data-strip]").forEach(e=>e.innerHTML=h);
}
function render(){
 const tab=isHome()?"Home":proj().tab;
 const showDock=tab!=="Sessions";
 const key=(tab==="Work"&&dockOpen())?"Work+dock":tab;
 document.querySelectorAll("section[data-screen]").forEach(s=>s.style.display=(s.dataset.screen===key&&(!s.dataset.rail||s.dataset.rail===(S.wide?"wide":"narrow")))?"block":"none");
 document.querySelectorAll("[data-prail]").forEach(e=>e.textContent=isHome()?"":S.cur);
 document.querySelectorAll("[data-dock]").forEach(e=>e.style.visibility="hidden");
 if(!isHome()){document.querySelectorAll("[data-pname]").forEach(e=>e.textContent=S.cur);document.querySelectorAll("[data-ppath]").forEach(e=>e.textContent=proj().path);
  document.querySelectorAll("[data-pcode]").forEach(e=>e.textContent=proj().code);document.querySelectorAll("[data-avatar]").forEach(e=>e.style.background=proj().color);}
 renderIcon();
 renderStrip();
 const d=document.getElementById("dock"); d.style.display=showDock?"flex":"none"; d.style.left=isHome()?"56px":(S.wide?"260px":"120px"); document.getElementById("iconmenu").style.left=S.wide?"268px":"128px"; if(!showDock)return;
 const list=sessions(), open=dockOpen(), all=isHome()||S.scope==="all";
 let bar='<div class="bar"><button data-a="toggle" class="on"><span style="color:#8E96A3">'+(open?"▾":"▸")+'</span>'+(all?"all sessions":"sessions")+' <span style="color:#8E96A3">'+list.length+'</span></button>';
 list.forEach(({x,n})=>{bar+='<button data-a="show" data-id="'+x.id+'" class="'+(open&&x.shown?"on":"")+'"><span class="dot" style="background:'+x.dot+'"></span>'+(n?'<span style="color:#8E96A3">'+n+' ·</span>':'')+esc(x.t)+'</button>';});
 let menu="";
 if(S.menu){
  const res=all?Object.entries(P).flatMap(([n,p])=>p.resume.map(r=>({r,n}))):proj().resume.map(r=>({r,n:S.cur}));
  let top="";
  if(all){top='<div class="lab">New session in</div>'+Object.entries(P).map(([n,p])=>'<button data-a="add" data-p="'+n+'"><span class="dot" style="background:'+(n===S.cur?"#7FD19B":"#5A606A")+'"></span><span style="flex:1"><b>'+n+'</b><small>'+p.path+'</small></span>'+(n===S.cur?'<span style="color:#8E96A3;font-size:11px">⌘T</span>':'')+'</button>').join("");}
  else{top='<button data-a="add" data-p="'+S.cur+'"><span class="dot" style="background:#7FD19B"></span><span style="flex:1"><b>New session</b><small>A login shell at the project root</small></span><span style="color:#8E96A3;font-size:11px">⌘T</span></button>';}
  menu='<div class="menu" style="'+(open?"top:28px":"bottom:30px")+'">'+top+(res.length?'<hr><div class="lab">Resume</div>':'')+res.map(({r,n})=>'<button data-a="resume" data-k="'+r.k+'" data-p="'+n+'"><span class="dot" style="background:'+r.dot+'"></span><span style="flex:1"><b>'+(all?n+" · ":"")+esc(r.title)+'</b><small>'+esc(r.sub)+'</small></span></button>').join("")+'</div>';
 }
 bar+='<span style="position:relative;display:flex"><button class="plus" data-a="menu" aria-label="New session or resume" title="New session or resume">+</button>'+menu+'</span>';
 bar+='</div>';
 let panes="";
 if(open){const sh=list.filter(({x})=>x.shown); panes='<div class="panes">'+(sh.length?sh.map(({x,n})=>'<div class="pane"><div class="ph"><span class="dot" style="background:'+x.dot+'"></span><b>'+(n?n+" · ":"")+esc(x.t)+'</b><button data-a="hide" data-id="'+x.id+'" aria-label="Hide pane">✕</button></div><div class="pb">'+esc(x.body)+'</div></div>').join(""):'<div class="pb" style="color:#8E96A3">Nothing running here. Press + to start a session.</div>')+'</div>';}
 d.innerHTML=bar+panes;
}
function renderIcon(){let m=document.getElementById("iconmenu"); if(!S.icon||isHome()){m.style.display="none";return;}
 m.style.display="flex"; m.innerHTML='<div class="lab">Project icon</div><button data-ic="img">Choose image…<small>PNG or JPG, shown in the strip and here</small></button><div class="lab">Or a colour</div><div style="display:flex;gap:6px;padding:4px 10px 8px">'+["#9CC0FF","#F2A7C3","#B8A7F2","#7FD19B","#F2C79C","#E4E7EB"].map(c=>'<button data-ic="'+c+'" aria-label="Colour '+c+'" style="width:24px;height:24px;border-radius:7px;border:'+(proj().color===c?"2px solid #E4E7EB":"0")+';background:'+c+'"></button>').join("")+'</div><button data-ic="reset">Reset to initials</button>';}
function find(id){for(const p of Object.values(P)){const x=p.sessions.find(x=>x.id===id); if(x)return x;}}
function cap(){const sh=sessions().filter(({x})=>x.shown); if(sh.length>=4) sh[0].x.shown=false;}
document.addEventListener("click",e=>{
 const rt=e.target.closest("[data-railtoggle]"); if(rt){S.wide=!S.wide;render();return;}
 const av=e.target.closest("[data-avatar]"); if(av){S.icon=!S.icon;render();return;}
 const ic=e.target.closest("[data-ic]"); if(ic){if(ic.dataset.ic.startsWith("#"))proj().color=ic.dataset.ic; S.icon=false;render();return;}
 if(S.icon){S.icon=false;render();}
 const go=e.target.closest("[data-go]"); if(go){S.cur=go.dataset.go;S.menu=false;render();return;}
 const nav=e.target.closest("button[aria-label]"); if(nav&&!isHome()&&TABS.includes(nav.getAttribute("aria-label"))){proj().tab=nav.getAttribute("aria-label");S.menu=false;render();return;}
 const b=e.target.closest("#dock [data-a]"); if(!b){if(S.menu){S.menu=false;render();}return;}
 const a=b.dataset.a,id=+b.dataset.id;
 if(a==="menu"){S.menu=!S.menu;render();return;} S.menu=false;
 if(a==="toggle")setOpen(!dockOpen());
 if(a==="scope")S.scope=b.dataset.v;
 if(a==="show"){const x=find(id); if(!dockOpen()){setOpen(true);x.shown=true;}else x.shown=!x.shown;}
 if(a==="hide")find(id).shown=false;
 if(a==="add"){cap();P[b.dataset.p].sessions.push({id:++N,t:"zsh",dot:"#7FD19B",shown:true,body:b.dataset.p+" main ❯ ▍"});setOpen(true);}
 if(a==="resume"){const p=P[b.dataset.p],r=p.resume.find(r=>r.k===b.dataset.k);p.resume=p.resume.filter(x=>x!==r);cap();p.sessions.push({id:++N,t:r.t,dot:"#7FD19B",shown:true,body:r.body});setOpen(true);}
 render();
});
document.addEventListener("keydown",e=>{if(e.target.tagName==="INPUT"||e.target.tagName==="TEXTAREA")return;
 if(/^[1-5]$/.test(e.key)&&!isHome()){proj().tab=TABS[e.key-1];render();}
 if(e.key==="j"){setOpen(!dockOpen());render();}
 if(e.key==="h"){S.cur="home";render();}
 if(e.key==="s"){S.wide=!S.wide;render();}});
function fit(){const k=Math.min(innerWidth/1440,innerHeight/900),st=document.getElementById("stage");st.style.transform="scale("+k+")";st.style.left=((innerWidth-1440*k)/2)+"px";st.style.top=((innerHeight-900*k)/2)+"px";}
addEventListener("resize",fit);fit();render();
"""

html = ('<!doctype html><html lang="en"><head><meta charset="utf-8"><title>Dev Desk — Console × Focus prototype</title>'
        '<link href="https://fonts.googleapis.com/css2?family=Geist+Mono:wght@400;500;600&display=swap" rel="stylesheet">'
        f"<style>{CSS}</style></head><body><div id=\"stage\">{sections}<div id=\"dock\"></div><div id=\"iconmenu\"></div></div><script>{JS}</script></body></html>")
open(DEST, "w", encoding="utf-8").write(html)
print(len(html))
