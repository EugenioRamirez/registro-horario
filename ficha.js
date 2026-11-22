'use strict';
const fichaEl=id=>document.getElementById(id);
const fichaSafe=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const fichaKeys=['email','nombre','fecha_alta','categoria','dni_nie','fecha_nacimiento','num_seguridad_social','direccion_via','direccion_numero','direccion_piso','codigo_postal','localidad','provincia','pais','movil','correo_personal','iban'];
let fichaEditando=false;
function fichaFecha(s){return s?s.split('-').reverse().join('/'):'Sin registrar';}
function fichaOculta(s){return s?'•••• '+s.slice(-4):'Sin registrar';}
function fichaDomicilio(p){if(!p)return 'Sin registrar';const clean=v=>String(v??'').trim();const street=[clean(p.direccion_via),clean(p.direccion_numero)].filter(Boolean).join(' ');const streetPart=[street,clean(p.direccion_piso)].filter(Boolean).join(', ');const town=[clean(p.codigo_postal),clean(p.localidad)].filter(Boolean).join(' ');const province=clean(p.provincia),country=clean(p.pais);const place=[town,province&&province.toLocaleLowerCase('es')!==clean(p.localidad).toLocaleLowerCase('es')?province:'',country].filter(Boolean).join(', ');return [streetPart,place].filter(Boolean).join(' · ')||'Sin registrar';}
async function cargarFicha(){
 const message=fichaEl('ficha-message');try{
  const {data:{session},error:sessionError}=await portalAuth.auth.getSession();
  if(sessionError||!session?.user?.email)throw Error('Inicia sesión con tu cuenta corporativa.');
  const email=session.user.email.toLowerCase();
  const [profile,manager]=await Promise.all([portalAuth.from('empleados_fichas').select(fichaKeys.join(',')).eq('email',email).maybeSingle(),portalAuth.from('empleados_gestores').select('email').eq('email',email).maybeSingle()]);
  if(profile.error)throw profile.error;if(manager.error)throw manager.error;const p=profile.data;
  for(const key of ['email','categoria','dni_nie','fecha_nacimiento','num_seguridad_social','fecha_alta','movil','correo_personal','iban']){let val=key==='email'?email:p?.[key];if(['fecha_alta','fecha_nacimiento'].includes(key))val=fichaFecha(val);else if(['iban','num_seguridad_social'].includes(key))val=fichaOculta(val);fichaEl('ficha-'+key).textContent=val||'Sin registrar';}fichaEl('ficha-domicilio').textContent=fichaDomicilio(p);
  fichaEl('ficha-heading').textContent=p?.nombre||'Mi ficha';fichaEl('ficha-subheading').textContent=p?.categoria||'Datos del empleado';
  message.textContent=p?'':'Tu ficha todavía no está configurada. Contacta con administración.';fichaEl('ficha-gestion').hidden=!manager.data;
  if(manager.data){const {data,error}=await portalAuth.from('empleados_fichas').select('email,nombre,fecha_alta,categoria').order('nombre');if(error)throw error;
   fichaEl('ficha-list').innerHTML=data.length?data.map(r=>`<div class="vac-entry"><div><strong>${fichaSafe(r.nombre)}</strong><small>${fichaSafe(r.email)} · ${fichaSafe(r.categoria||'Categoría sin registrar')} · Alta: ${fichaSafe(fichaFecha(r.fecha_alta))}</small></div><button type="button" class="vac-btn vac-secondary" data-ficha-email="${fichaSafe(r.email)}">Editar</button></div>`).join(''):'<p class="vac-hint">No hay fichas registradas.</p>';
  }
 }catch(err){message.textContent='No se ha podido cargar la ficha: '+err.message;}
}
fichaEl('ficha-form').addEventListener('submit',async e=>{e.preventDefault();const btn=e.submitter;btn.disabled=true;try{const values=Object.fromEntries(fichaKeys.map(k=>[k,fichaEl('ficha-edit-'+k).value]));const {error}=await portalAuth.rpc('empleados_guardar_ficha',{p_datos:values,p_actualizar:fichaEditando});if(error)throw error;e.target.reset();await cargarFicha();fichaEl('ficha-message').textContent='Ficha guardada.';}catch(err){fichaEl('ficha-message').textContent=err.message;}finally{btn.disabled=false;}});
fichaEl('ficha-list').addEventListener('click',async e=>{const button=e.target.closest('[data-ficha-email]');if(!button)return;button.disabled=true;try{const {data:r,error}=await portalAuth.from('empleados_fichas').select(fichaKeys.join(',')).eq('email',button.dataset.fichaEmail).single();if(error)throw error;fichaEditando=true;fichaEl('ficha-edit-email').readOnly=true;for(const key of fichaKeys)fichaEl('ficha-edit-'+key).value=r[key]||'';fichaEl('ficha-edit-nombre').focus();}catch(err){fichaEl('ficha-message').textContent='No se ha podido abrir la ficha: '+err.message;}finally{button.disabled=false;}});
fichaEl('ficha-form').addEventListener('reset',()=>{fichaEditando=false;fichaEl('ficha-edit-email').readOnly=false;});
