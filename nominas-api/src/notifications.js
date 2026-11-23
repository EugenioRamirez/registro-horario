'use strict';
const PORTAL='https://empleados.xpecializa.com/';
const htmlMessage=text=>'<div style="font-family:Calibri,Arial,sans-serif;font-size:11pt">'+text.split('\n\n').map(p=>'<p>'+p.replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('\n','<br>').replace(PORTAL,`<a href="${PORTAL}">${PORTAL}</a>`)+'</p>').join('')+'</div>';
function build(to,subject,text){return {to,subject,text,html:htmlMessage(text)};}
function mailFor(n){
 if(!n || !/^[a-z0-9._%+-]+@xpecializa\.com$/i.test(n.destinatario))throw Error('Destinatario no válido');
 const d=n.datos||{}, date=s=>{if(!/^\d{4}-\d{2}-\d{2}$/.test(s||''))throw Error('Fecha no válida');return s.split('-').reverse().join('/');};
 if(n.tipo==='vacaciones'){
  if(!Number.isInteger(d.dias)||d.dias<1)throw Error('Días no válidos');
  return build(n.destinatario,'Vacaciones aprobadas',`Hola,\n\nTu solicitud de vacaciones del ${date(d.inicio)} al ${date(d.fin)} (${d.dias} ${d.dias===1?'día':'días'}) ha sido aprobada.\n\nPuedes consultar el detalle en ${PORTAL}\n\nAdministración · Xpecializa`);
 }
 if(n.tipo==='gastos'){
  if(!Number.isInteger(d.ano)||!Number.isInteger(d.mes)||d.mes<1||d.mes>12||!Number.isFinite(Number(d.total)))throw Error('Datos de gastos no válidos');
  const period=new Intl.DateTimeFormat('es-ES',{month:'long',year:'numeric',timeZone:'UTC'}).format(new Date(Date.UTC(d.ano,d.mes-1,1)));
  const total=new Intl.NumberFormat('es-ES',{style:'currency',currency:'EUR'}).format(Number(d.total));
  return build(n.destinatario,'Nota de gastos aprobada',`Hola,\n\nTu nota de gastos de ${period}, por importe de ${total}, ha sido aprobada y está pendiente de abono.\n\nPuedes consultar su estado en ${PORTAL}\n\nAdministración · Xpecializa`);
 }
 throw Error('Tipo de notificación no válido');
}
async function processOne({claim,send,finish}){
 const n=await claim(); if(!n)return false;
 let message; try{message=mailFor(n);}catch{await finish(n.id,'error');return true;}
 let status;try{status=await send(message);}catch{await finish(n.id,'incierta');return true;}
 await finish(n.id,status===202?'aceptada':status>=400&&status<500?'error':'incierta');return true;
}
module.exports={mailFor,processOne};
