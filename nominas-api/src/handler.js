'use strict';
const {createHash}=require('node:crypto');
// La identidad y los permisos se comprueban en cada petición; los nombres de blob nunca son parámetros del cliente.
function makeHandler({lookupUser,lookupDocument,lookupAdminDocument,readDocument}) {
 return async function(request,context){
  const reply=(status,message)=>({status,headers:{'Cache-Control':'no-store','Content-Type':'application/json; charset=utf-8','X-Content-Type-Options':'nosniff'},jsonBody:{error:message}});
  const auth=request.headers.get('authorization')||'';
  if(!/^Bearer [A-Za-z0-9._~-]+$/.test(auth))return reply(401,'Inicia sesión para acceder a tus nóminas.');
  const token=auth.slice(7),id=request.params.id||'';
  if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id))return reply(404,'Documento no encontrado.');
  try{
   const user=await lookupUser(token);
   if(!user?.email||!user.email.toLowerCase().endsWith('@xpecializa.com')||user.app_metadata?.provider!=='azure')return reply(401,'La sesión no es válida.');
   let doc=await lookupDocument(token,id);
   const own=doc?.empleado?.toLowerCase()===user.email.toLowerCase();
   if(!own) doc=lookupAdminDocument ? await lookupAdminDocument(token,id) : null;
   if(!doc||!/^[a-f0-9]{32}\/\d{4}-\d{2}\.pdf$/.test(doc.blob_key)||!/^[a-f0-9]{64}$/.test(doc.sha256||''))return reply(404,'Documento no encontrado.');
   const bytes=await readDocument(doc.blob_key);
   if(!bytes||bytes.length<5||bytes.subarray(0,5).toString('ascii')!=='%PDF-'||createHash('sha256').update(bytes).digest('hex')!==doc.sha256)throw Error('Invalid PDF');
   return {status:200,headers:{'Content-Type':'application/pdf','Content-Disposition':`inline; filename="nomina-${doc.ano}-${String(doc.mes).padStart(2,'0')}.pdf"`,'Cache-Control':'private, no-store, max-age=0','X-Content-Type-Options':'nosniff'},body:bytes};
  }catch(error){context.error('No se pudo atender una petición de nómina.',error?.name||'Error');return reply(503,'No se ha podido obtener el documento.');}
 };
}
module.exports={makeHandler};
