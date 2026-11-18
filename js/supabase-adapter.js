/* CONTROL 360 · Adaptador Supabase
   Reemplaza la base de datos / identidad / archivos de Claude por Supabase:
   - Autenticación real (correo + contraseña personal, enlace de invitación/recuperación)
   - Base de datos compartida (tabla public.docs) con RLS por perfil
   - Archivos en Storage (bucket privado "comprobantes")
   Si config.js no está configurado, no hace nada y la app corre en modo local (demo). */
(function(){
  var cfg=window.CONTROL360||{};
  var initHref=location.hash+location.search;
  if(!cfg.SUPABASE_URL||!cfg.SUPABASE_ANON_KEY||/TU-PROYECTO|PEGUE/.test(cfg.SUPABASE_URL+cfg.SUPABASE_ANON_KEY)||!window.supabase){return;}
  var sb=window.supabase.createClient(cfg.SUPABASE_URL,cfg.SUPABASE_ANON_KEY,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true}});
  var session=null,recovery=/type=(invite|recovery)/.test(initHref),resolved=false,resolveReady;
  var ready=new Promise(function(r){resolveReady=r;});

  /* ── pantalla de acceso ── */
  var css='#c360-auth{position:fixed;inset:0;z-index:99999;background:#0f1d24;display:flex;align-items:center;justify-content:center;font-family:system-ui,Segoe UI,Arial,sans-serif;padding:16px}'+
  '#c360-auth .c{background:#fff;border-radius:14px;padding:28px;width:100%;max-width:380px;box-shadow:0 20px 60px rgba(0,0,0,.4)}'+
  '#c360-auth h1{margin:0 0 4px;font-size:22px;color:#0f1d24}#c360-auth p{margin:0 0 16px;color:#5b6b73;font-size:14px}'+
  '#c360-auth label{display:block;font-size:13px;font-weight:600;margin:12px 0 4px;color:#25363e}'+
  '#c360-auth input{width:100%;box-sizing:border-box;padding:10px 12px;border:1px solid #c5d0d5;border-radius:8px;font-size:15px}'+
  '#c360-auth button{width:100%;margin-top:16px;padding:11px;border:0;border-radius:8px;background:#0b6e8a;color:#fff;font-size:15px;font-weight:600;cursor:pointer}'+
  '#c360-auth button.l{background:none;color:#0b6e8a;font-weight:500;margin-top:8px;font-size:13px}'+
  '#c360-auth .e{color:#b3261e;font-size:13px;margin-top:10px;min-height:16px}#c360-auth .o{color:#1b7a43;font-size:13px;margin-top:10px}';
  var st=document.createElement('style');st.textContent=css;document.head.appendChild(st);
  var ov=document.createElement('div');ov.id='c360-auth';ov.style.display='none';
  document.addEventListener('DOMContentLoaded',function(){document.body.appendChild(ov);});
  if(document.body)document.body.appendChild(ov);
  function E(t){return String(t==null?'':t).replace(/[&<>"]/g,function(c){return{'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c];});}
  function msg(t,ok){var m=ov.querySelector('.m');if(m){m.className=ok?'o m':'e m';m.textContent=t||'';}}
  function showLogin(){
    ov.style.display='flex';
    ov.innerHTML='<div class="c"><h1>CONTROL 360</h1><p>Inicie sesión con su usuario (correo) y contraseña.</p>'+
    '<label for="a-m">Usuario (correo)</label><input id="a-m" type="email" autocomplete="username">'+
    '<label for="a-p">Contraseña</label><input id="a-p" type="password" autocomplete="current-password">'+
    '<button id="a-go">Entrar</button><p style="margin:14px 0 0;font-size:12px">¿Olvidó su contraseña? Solicite a Sistemas que restablezca su acceso.</p><div class="m e"></div></div>';
    var go=function(){var m=ov.querySelector('#a-m').value.trim().toLowerCase(),p=ov.querySelector('#a-p').value;
      if(!m||!p){msg('Capture su correo y contraseña.');return;}
      msg('Verificando…',true);
      sb.auth.signInWithPassword({email:m,password:p}).then(function(r){
        if(r.error){msg('Correo o contraseña incorrectos.');return;}
        session=r.data.session;check();
      });};
    ov.querySelector('#a-go').onclick=go;
    ov.querySelector('#a-p').onkeydown=function(e){if(e.key==='Enter')go();};
  }
  function showSetPwd(){
    ov.style.display='flex';
    ov.innerHTML='<div class="c"><h1>Cree su contraseña</h1><p>Es su primer ingreso (o su acceso fue restablecido). Defina una contraseña personal para continuar (mínimo 10 caracteres, con letras y números).</p>'+
    '<label for="a-1">Nueva contraseña</label><input id="a-1" type="password" autocomplete="new-password">'+
    '<label for="a-2">Confirmar contraseña</label><input id="a-2" type="password" autocomplete="new-password">'+
    '<button id="a-go">Guardar y entrar</button><div class="m e"></div></div>';
    ov.querySelector('#a-go').onclick=function(){
      var a=ov.querySelector('#a-1').value,b=ov.querySelector('#a-2').value;
      if(a.length<10||!/[A-Za-z]/.test(a)||!/[0-9]/.test(a)){msg('Use al menos 10 caracteres, con letras y números.');return;}
      if(a!==b){msg('Las contraseñas no coinciden.');return;}
      sb.auth.updateUser({password:a,data:{must_change:false}}).then(function(r){
        if(r.error){msg('No se pudo guardar: '+r.error.message);return;}
        recovery=false;session=null;history.replaceState(null,'',location.pathname);
        sb.auth.getSession().then(function(x){session=x.data.session;check();});
      });};
  }
  function needPwd(){var m=session&&session.user&&session.user.user_metadata;return recovery||!!(m&&m.must_change);}
  function check(){
    if(!session){showLogin();return;}
    if(needPwd()){showSetPwd();return;}
    ov.style.display='none';ov.innerHTML='';
    if(!resolved){resolved=true;addLogout();resolveReady();}
  }
  function addLogout(){
    try{var w=document.getElementById('role-wrap')||document.querySelector('.role');if(!w)return;
      var b=document.createElement('button');b.textContent='Cerrar sesión';b.style.cssText='margin-left:10px;padding:6px 10px;border-radius:8px;border:1px solid #c5d0d5;background:#fff;cursor:pointer;font-size:13px';
      b.onclick=function(){sb.auth.signOut().then(function(){location.reload();});};w.appendChild(b);
      var re=document.createElement('style');re.textContent='#role-wrap{display:flex!important;align-items:center}#role-wrap label,#role-wrap #role-sel{display:none}';document.head.appendChild(re);
    }catch(e){}
  }
  sb.auth.onAuthStateChange(function(ev,s){
    session=s;
    if(ev==='PASSWORD_RECOVERY')recovery=true;
    if(ev==='SIGNED_OUT'&&resolved){location.reload();return;}
    if(!resolved)check();
  });
  sb.auth.getSession().then(function(r){session=r.data.session;if(!resolved)check();});

  /* ── base de datos (colecciones → tabla docs) ── */
  var PAGE=1000;
  function clean(v){return JSON.parse(JSON.stringify(v));}
  function snap(rows){var docs=rows.map(function(x){return{id:x.id,data:function(){return x.data;}};});return{docs:docs,forEach:function(f){docs.forEach(f);}};}
  function mk(n,filters,ord,lim){
    function fetchRows(){
      var out=[];
      function page(from){
        var q=sb.from('docs').select('id,data').eq('coll',n);
        filters.forEach(function(f){q=q.eq('data->>'+f[0],String(f[1]));});
        if(ord)q=q.order('data->'+ord[0],{ascending:ord[1]!=='desc'});else q=q.order('id');
        var to=lim?Math.min(lim,from+PAGE)-1:from+PAGE-1;
        return q.range(from,to).then(function(r){
          if(r.error)throw r.error;
          out=out.concat(r.data||[]);
          if(r.data&&r.data.length===to-from+1&&(!lim||out.length<lim))return page(from+PAGE);
          return out;
        });
      }
      return page(0);
    }
    return{
      where:function(f,op,v){if(op!=='==')throw new Error('Operador no soportado');return mk(n,filters.concat([[f,v]]),ord,lim);},
      orderBy:function(f,d){return mk(n,filters,[f,d||'asc'],lim);},
      limit:function(k){return mk(n,filters,ord,k);},
      get:function(){return fetchRows().then(snap);},
      onSnapshot:function(ok,err){
        var dead=false,t=null;
        var run=function(){fetchRows().then(function(r){if(!dead)ok(snap(r));}).catch(function(e){if(!dead&&err)err(e);});};
        run();
        var ch=sb.channel('c360-'+n+'-'+Math.random().toString(36).slice(2))
          .on('postgres_changes',{event:'*',schema:'public',table:'docs',filter:'coll=eq.'+n},function(){clearTimeout(t);t=setTimeout(run,250);})
          .subscribe();
        return function(){dead=true;clearTimeout(t);sb.removeChannel(ch);};
      },
      doc:function(id){
        id=String(id);
        return{
          set:async function(v){
            var data=clean(v);
            var u=await sb.from('docs').update({data:data,updated_at:new Date().toISOString()}).eq('coll',n).eq('id',id).select('id');
            if(u.error)throw u.error;
            if(u.data&&u.data.length)return;
            var i=await sb.from('docs').insert({coll:n,id:id,data:data});
            if(i.error)throw i.error;
          },
          delete:async function(){
            var d=await sb.from('docs').delete().eq('coll',n).eq('id',id).select('id');
            if(d.error)throw d.error;
            if(!d.data||!d.data.length)throw new Error('Sin permiso para eliminar este documento');
          },
          update:async function(patch){
            var g=await sb.from('docs').select('data').eq('coll',n).eq('id',id).maybeSingle();
            if(g.error)throw g.error;
            if(!g.data)throw new Error('El documento no existe');
            var data=Object.assign({},g.data.data,clean(patch));
            var u=await sb.from('docs').update({data:data,updated_at:new Date().toISOString()}).eq('coll',n).eq('id',id).select('id');
            if(u.error)throw u.error;
            if(!u.data||!u.data.length)throw new Error('Sin permiso para modificar este documento');
          }
        };
      }
    };
  }
  var dbApi={collection:function(n){return mk(n,[],null,null);}};

  /* ── identidad ── */
  var userApi={
    id:async function(){return session.user.id;},
    me:async function(){var m=session.user.user_metadata||{};return{email:session.user.email,name:m.nombre||''};},
    isOwner:function(){return false;},
    profiles:async function(ids){
      var out={};if(!ids||!ids.length)return out;
      var r=await sb.from('docs').select('data').eq('coll','usuarios').in('data->>uid',ids);
      (r.data||[]).forEach(function(x){if(x.data&&x.data.uid)out[x.data.uid]={name:x.data.nombre||x.data.email||''};});
      return out;
    }
  };

  /* ── archivos ── */
  var assetsApi={upload:async function(file){
    var safe=String(file.name||'archivo').replace(/[^\w.\-]+/g,'_');
    var path=session.user.id+'/'+Date.now()+'-'+safe;
    var up=await sb.storage.from('comprobantes').upload(path,file,{contentType:file.type||'application/octet-stream'});
    if(up.error)throw up.error;
    var s=await sb.storage.from('comprobantes').createSignedUrl(path,60*60*24*365);
    if(s.error)throw s.error;
    return{id:path,url:s.data.signedUrl};
  }};

  function gestionar(accion,email,nombre,password){
    return sb.functions.invoke('gestionar-usuario',{body:{accion:accion,email:email,nombre:nombre,password:password}}).then(function(r){
      if(r.error){
        var c=r.error.context;
        if(c&&c.json)return c.json().then(function(b){throw new Error((b&&b.error)||r.error.message);},function(){throw r.error;});
        throw r.error;
      }
      if(r.data&&r.data.error)throw new Error(r.data.error);
    });
  }
  function tempPwd(){
    var a='ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789',b=new Uint32Array(12),o='';
    crypto.getRandomValues(b);for(var i=0;i<12;i++)o+=a[b[i]%a.length];
    return o+'7';
  }
  /* descargas (PDF / Excel / CSV / comprobantes) */
  var downloadsApi={save:async function(o){
    var blob=o.data instanceof Blob?o.data:new Blob([o.data]);
    var u=URL.createObjectURL(blob),a=document.createElement('a');
    a.href=u;a.download=o.filename||'archivo';document.body.appendChild(a);a.click();
    setTimeout(function(){a.remove();URL.revokeObjectURL(u);},4000);
  }};
  window.C360={
    tempPwd:tempPwd,
    crear:function(email,nombre,pwd){return gestionar('crear',email,nombre,pwd);},
    reset:function(email,nombre,pwd){return gestionar('reset',email,nombre,pwd);}
  };
  window.claude={use:async function(name){
    await ready;
    if(name==='db')return dbApi;
    if(name==='user')return userApi;
    if(name==='assets')return assetsApi;
    if(name==='downloads')return downloadsApi;
    return null;
  }};
})();
