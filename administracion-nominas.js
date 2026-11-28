'use strict';
const payroll={file:null,groups:[],employees:[],existing:new Set(),year:new Date().getFullYear(),month:new Date().getMonth()+1,busy:false,generation:0};
const payrollAPI='https://xp-nominas-api-cfghh3dxdca2agh8.westeurope-01.azurewebsites.net';

function adminPayrollRender(){
  const c=admEl('admin-content');
  if(payroll.busy){c.innerHTML='<p class="admin-message">Publicación en curso. Espera a que termine.</p>';return;}
  let years='';for(let y=new Date().getFullYear()-3;y<=new Date().getFullYear()+1;y++)years+=`<option value="${y}" ${payroll.year===y?'selected':''}>${y}</option>`;
  c.innerHTML=`<section class="payroll-screen"><h2>Carga mensual de nóminas</h2><p class="admin-message">Selecciona el periodo y el PDF conjunto. Revisarás el resultado antes de publicar.</p><div class="admin-toolbar payroll-toolbar"><label>Mes<select id="payroll-month">${MESES.map((m,i)=>`<option value="${i+1}" ${payroll.month===i+1?'selected':''}>${m}</option>`).join('')}</select></label><label>Año<select id="payroll-year">${years}</select></label><label class="payroll-file-label">PDF conjunto<input id="payroll-file" type="file" accept="application/pdf,.pdf"></label></div><p id="payroll-message" class="admin-message" role="status" aria-live="polite"></p><div id="payroll-preview"></div></section>`;
  admEl('payroll-file').addEventListener('change',payrollChoose);
  admEl('payroll-year').addEventListener('change',e=>{payroll.year=Number(e.target.value);payrollReset();});
  admEl('payroll-month').addEventListener('change',e=>{payroll.month=Number(e.target.value);payrollReset();});
  payrollReset();
}
function payrollReset(keepFile=false){
  payroll.generation++;for(const g of payroll.groups)if(g.url)URL.revokeObjectURL(g.url);
  payroll.file=null;payroll.groups=[];payroll.existing=new Set();
  const f=admEl('payroll-file');if(f&&!keepFile)f.value='';const p=admEl('payroll-preview');if(p)p.replaceChildren();const m=admEl('payroll-message');if(m)m.textContent='';
}
async function payrollLoadPdfLib(){if(window.PDFLib)return;await new Promise((resolve,reject)=>{const script=document.createElement('script');script.src='vendor/pdf-lib.min.js';script.onload=resolve;script.onerror=()=>reject(Error('No se ha podido cargar el lector de documentos.'));document.head.append(script);});}
async function payrollCheckExisting(){const {data,error}=await portalAuth.rpc('nominas_periodos',{p_ano:payroll.year,p_mes:payroll.month});if(error)throw error;payroll.existing=new Set((data||[]).map(x=>String(x.empleado).toLowerCase()));}
async function payrollChoose(e){
  const file=e.target.files?.[0];if(!file)return;payrollReset(true);const generation=payroll.generation, message=admEl('payroll-message');
  if(file.size>30*1024*1024){message.textContent='El archivo supera los 30 MB.';return;}
  message.textContent='Analizando el PDF…';
  try{
    const [employees,pdfjs]=await Promise.all([admRows(()=>portalAuth.from('empleados_fichas').select('email,nombre,dni_nie').order('email')),import('./vendor/pdf.min.mjs'),payrollLoadPdfLib()]);
    if(generation!==payroll.generation)return;
    payroll.employees=employees.filter(x=>x.email&&x.nombre&&(x.nombre||'').trim().toLocaleUpperCase('es')!=='PRUEBA TEMPORAL NO REAL');
    const bytes=new Uint8Array(await file.arrayBuffer()), pdf=await PDFLib.PDFDocument.load(bytes.slice());
    pdfjs.GlobalWorkerOptions.workerSrc='vendor/pdf.worker.min.mjs';const reader=await pdfjs.getDocument({data:bytes.slice()}).promise;
    if(!reader.numPages||reader.numPages>300)throw Error('El PDF debe tener entre 1 y 300 páginas.');
    const groups=[];
    for(let page=1;page<=reader.numPages;page++){
      const p=await reader.getPage(page),text=(await p.getTextContent()).items.map(x=>x.str||'').join(' '),found=PayrollAnalysis.analysePage(text,payroll.employees,payroll.year,payroll.month),last=groups[groups.length-1];
      // A continuation is joined only when its identifier independently matches the preceding page.
      if(found.email&&last&&found.email===last.email&&!found.hasHeader&&last.pages.at(-1)===page-1){last.pages.push(page);}
      else groups.push({...found,pages:[page],published:false});
    }
    for(const group of groups){
      const out=await PDFLib.PDFDocument.create(),pages=await out.copyPages(pdf,group.pages.map(n=>n-1));pages.forEach(page=>out.addPage(page));group.bytes=await out.save();group.tooLarge=group.bytes.length>15*1024*1024;group.url=URL.createObjectURL(new Blob([group.bytes],{type:'application/pdf'}));
    }
    if(generation!==payroll.generation){groups.forEach(g=>URL.revokeObjectURL(g.url));return;}
    payroll.file=file;payroll.groups=groups;await payrollCheckExisting();if(generation!==payroll.generation)return;
    message.textContent=`${reader.numPages} páginas analizadas. No se ha publicado ningún documento.`;payrollDraw();
  }catch(err){if(generation===payroll.generation){message.textContent='No se ha podido analizar el PDF. Comprueba que no esté protegido o dañado y vuelve a intentarlo.';console.error('PDF no procesado:',err.message);}}
}
function payrollDraw(){
  const p=admEl('payroll-preview');if(!p||!payroll.groups.length)return;
  const assessed=PayrollAnalysis.assess(payroll.groups,payroll.existing),ready=assessed.filter(g=>g.eligible).length,issues=assessed.filter(g=>!g.eligible&&!g.published).length,published=assessed.filter(g=>g.published).length;
  const rows=assessed.map(g=>{const person=payroll.employees.find(e=>e.email===g.email),kind=g.eligible?'ready':g.published?'published':'issue';return `<tr><td>${admSafe(person?.nombre||'Sin identificar')}</td><td>${g.pages.length===1?'Página':'Páginas'} ${g.pages.join(', ')}</td><td><span class="payroll-status payroll-${kind}">${admSafe(g.status)}</span></td><td><a class="admin-link" href="${admSafe(g.url)}" target="_blank" rel="noopener">Ver PDF<span class="emp-sr"> de ${admSafe(person?.nombre||'página '+g.pages[0])}</span></a></td></tr>`;}).join('');
  p.innerHTML=`<div class="payroll-file-summary"><strong>${admSafe(payroll.file.name)}</strong><span>${payroll.groups.reduce((n,g)=>n+g.pages.length,0)} páginas · Periodo seleccionado: ${admSafe(MESES[payroll.month-1])} ${payroll.year}</span></div><div class="payroll-heading"><div><h3>Resultado de la revisión</h3><p class="admin-message">Asignación automática por DNI/NIE y comprobación del periodo.</p></div></div><div class="payroll-summary"><span><strong>${assessed.length}</strong> documentos detectados</span><span><strong>${ready}</strong> preparados</span><span><strong>${issues}</strong> incidencias</span>${published?`<span><strong>${published}</strong> publicados</span>`:''}</div><div class="admin-table-wrap payroll-table-wrap"><table class="admin-table"><thead><tr><th>Empleado</th><th>Documento</th><th>Resultado</th><th>Revisión</th></tr></thead><tbody>${rows}</tbody></table></div><div class="payroll-footer"><p class="admin-message">Solo se publicarán las nóminas preparadas. Las incidencias permanecerán sin publicar.</p><button id="payroll-publish" type="button" class="vac-btn" ${ready&&!payroll.busy?'':'disabled'}>Publicar ${ready} nómina${ready===1?'':'s'}</button></div>`;
  admEl('payroll-publish').addEventListener('click',payrollPublish);
}
function payrollBase64(bytes){let s='';for(let i=0;i<bytes.length;i+=0x8000)s+=String.fromCharCode(...bytes.subarray(i,i+0x8000));return btoa(s);}
async function payrollPublish(){
  if(payroll.busy)return;payroll.busy=true;['payroll-year','payroll-month','payroll-file'].forEach(id=>{if(admEl(id))admEl(id).disabled=true;});payrollDraw();
  const message=admEl('payroll-message');let done=0;
  try{
    await payrollCheckExisting();const {data:{session}}=await portalAuth.auth.getSession();if(!session?.access_token)throw Error('Inicia sesión de nuevo.');
    const ready=PayrollAnalysis.assess(payroll.groups,payroll.existing).filter(g=>g.eligible);
    for(const group of ready){
      const res=await fetch(payrollAPI+'/api/nominas',{method:'POST',headers:{'Content-Type':'application/json',Authorization:'Bearer '+session.access_token},body:JSON.stringify({empleado:group.email,ano:payroll.year,mes:payroll.month,pdf:payrollBase64(group.bytes)}),cache:'no-store'});
      const payload=await res.json().catch(()=>({}));if(!res.ok)throw Error(payload.error||'No se ha podido publicar un documento.');
      payroll.groups.find(g=>g.pages[0]===group.pages[0]).published=true;done++;
    }
    await payrollCheckExisting();message.textContent=done?`${done} nómina${done===1?' publicada':'s publicadas'}. Revisa las incidencias restantes.`:'No hay nóminas nuevas listas para publicar.';
  }catch(err){message.textContent=`${done} publicada${done===1?'':'s'}. ${err.message} Comprueba el resultado antes de reintentar.`;}
  finally{payroll.busy=false;['payroll-year','payroll-month','payroll-file'].forEach(id=>{if(admEl(id))admEl(id).disabled=false;});payrollDraw();}
}
