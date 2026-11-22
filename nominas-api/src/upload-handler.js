'use strict';
const {createHash,randomBytes}=require('node:crypto');
function makeUploadHandler({lookupUser,isManager,lookupEmployee,findPeriod,writeDocument,registerDocument}) {
 return async function(request,context){
  const reply=(status,message)=>({status,headers:{'Cache-Control':'no-store','Content-Type':'application/json; charset=utf-8','X-Content-Type-Options':'nosniff'},jsonBody:{error:message}});
  const auth=request.headers.get('authorization')||'';
  if(!/^Bearer [A-Za-z0-9._~-]+$/.test(auth))return reply(401,'Inicia sesión para gestionar nóminas.');
  const token=auth.slice(7);
  try{
   const user=await lookupUser(token);
   if(!user?.email||!user.email.toLowerCase().endsWith('@xpecializa.com')||user.app_metadata?.provider!=='azure')return reply(401,'La sesión no es válida.');
   if(!await isManager(token,user.email.toLowerCase()))return reply(403,'No tienes permiso para gestionar nóminas.');
   const body=await request.json();
   const email=String(body.empleado||'').trim().toLowerCase(), year=body.ano, month=body.mes, raw=body.pdf;
   if(!/^[a-z0-9.!#$%&'*+/=?^_`{|}~-]+@xpecializa\.com$/.test(email)||!Number.isInteger(year)||year<2000||year>2100||!Number.isInteger(month)||month<1||month>12||typeof raw!=='string'||raw.length>20*1024*1024||raw.length%4!==0||/[^A-Za-z0-9+\/=]/.test(raw)||/=/.test(raw.slice(0,-2)))return reply(400,'Los datos del documento no son válidos.');
   const bytes=Buffer.from(raw,'base64');
   if(bytes.length<5||bytes.length>15*1024*1024||bytes.subarray(0,5).toString('ascii')!=='%PDF-')return reply(400,'Selecciona un PDF válido de hasta 15 MB.');
   if(!await lookupEmployee(token,email))return reply(400,'El empleado no está en la plantilla.');
   if(await findPeriod(token,email,year,month))return reply(409,'Ya existe una nómina para este empleado y mes.');
   const key=`${randomBytes(16).toString('hex')}/${year}-${String(month).padStart(2,'0')}.pdf`;
   const digest=createHash('sha256').update(bytes).digest('hex');
   await writeDocument(key,bytes);
   await registerDocument(token,{p_empleado:email,p_ano:year,p_mes:month,p_blob_key:key,p_sha256:digest});
   return {status:201,headers:{'Cache-Control':'no-store','Content-Type':'application/json; charset=utf-8','X-Content-Type-Options':'nosniff'},jsonBody:{ok:true}};
  }catch(error){context.error('No se pudo publicar una nómina.',error?.name||'Error');return reply(503,'No se ha podido publicar la nómina. Revisa si ya figura en el portal antes de reintentar.');}
 };
}
module.exports={makeUploadHandler};
