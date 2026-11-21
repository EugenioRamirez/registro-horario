'use strict';
const fichaEl=id=>document.getElementById(id);
const fichaSafe=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const fichaFields='email,nombre,fecha_alta,puesto,domicilio,movil,iban,reconocimiento';
let fichaEditando=false;
const fichaDecision={pendiente:'Pendiente de registrar',acepta:'Acepta',renuncia:'Renuncia'};
async function cargarFicha(){
 const message=fichaEl('ficha-message');try{
  const {data:{session},error:sessionError}=await portalAuth.auth.getSession();
  if(sessionError||!session?.user?.email)throw Error('Inicia sesión con tu cuenta corporativa.');
  const email=session.user.email.toLowerCase();
  const [profile,manager]=await Promise.all([portalAuth.from('empleados_fichas').select(fichaFields).eq('email',email).maybeSingle(),portalAuth.from('empleados_gestores').select('email').eq('email',email).maybeSingle()]);
  if(profile.error)throw profile.error;if(manager.error)throw manager.error;const p=profile.data;
  fichaEl('ficha-email').textContent=email;fichaEl('ficha-name').textContent=p?.nombre||'Pendiente de configurar';
  fichaEl('ficha-date').textContent=p?.fecha_alta?p.fecha_alta.split('-').reverse().join('/'):'Pendiente de configurar';
  for(const key of ['puesto','domicilio','movil','iban'])fichaEl('ficha-'+key).textContent=p?.[key]||'Sin registrar';
  fichaEl('ficha-reconocimiento').textContent=fichaDecision[p?.reconocimiento]||'Pendiente de registrar';
  message.textContent=p?'':'Tu ficha todavía no está configurada. Contacta con administración.';
  fichaEl('ficha-gestion').hidden=!manager.data;
  if(manager.data){const {data,error}=await portalAuth.from('empleados_fichas').select('email,nombre,fecha_alta,puesto').order('nombre');if(error)throw error;
   fichaEl('ficha-list').innerHTML=data.length?data.map(r=>`<div class="vac-entry"><div><strong>${fichaSafe(r.nombre)}</strong><small>${fichaSafe(r.email)} · ${fichaSafe(r.puesto||'Puesto sin registrar')} · Alta: ${fichaSafe(r.fecha_alta.split('-').reverse().join('/'))}</small></div><button type="button" class="vac-btn vac-secondary" data-ficha-email="${fichaSafe(r.email)}">Editar</button></div>`).join(''):'<p class="vac-hint">No hay fichas registradas.</p>';
  }
 }catch(err){message.textContent='No se ha podido cargar la ficha: '+err.message;}
}
fichaEl('ficha-form').addEventListener('submit',async e=>{e.preventDefault();const btn=e.submitter;btn.disabled=true;try{const {error}=await portalAuth.rpc('empleados_guardar_ficha',{p_email:fichaEl('ficha-edit-email').value,p_nombre:fichaEl('ficha-edit-name').value,p_fecha_alta:fichaEl('ficha-edit-date').value,p_puesto:fichaEl('ficha-edit-puesto').value,p_domicilio:fichaEl('ficha-edit-domicilio').value,p_movil:fichaEl('ficha-edit-movil').value,p_iban:fichaEl('ficha-edit-iban').value,p_reconocimiento:fichaEl('ficha-edit-reconocimiento').value,p_actualizar:fichaEditando});if(error)throw error;e.target.reset();await cargarFicha();fichaEl('ficha-message').textContent='Ficha guardada.';}catch(err){fichaEl('ficha-message').textContent=err.message;}finally{btn.disabled=false;}});
fichaEl('ficha-list').addEventListener('click',async e=>{const button=e.target.closest('[data-ficha-email]');if(!button)return;button.disabled=true;try{const {data:r,error}=await portalAuth.from('empleados_fichas').select(fichaFields).eq('email',button.dataset.fichaEmail).single();if(error)throw error;fichaEditando=true;fichaEl('ficha-edit-email').readOnly=true;fichaEl('ficha-edit-email').value=r.email;fichaEl('ficha-edit-name').value=r.nombre;fichaEl('ficha-edit-date').value=r.fecha_alta;for(const key of ['puesto','domicilio','movil','iban'])fichaEl('ficha-edit-'+key).value=r[key]||'';fichaEl('ficha-edit-reconocimiento').value=r.reconocimiento;fichaEl('ficha-edit-name').focus();}catch(err){fichaEl('ficha-message').textContent='No se ha podido abrir la ficha: '+err.message;}finally{button.disabled=false;}});

fichaEl('ficha-form').addEventListener('reset',()=>{fichaEditando=false;fichaEl('ficha-edit-email').readOnly=false;});
