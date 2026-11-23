'use strict';
const {app}=require('@azure/functions');
const {DefaultAzureCredential}=require('@azure/identity');
const {BlobServiceClient}=require('@azure/storage-blob');
const {makeHandler}=require('./handler');
const {makeUploadHandler}=require('./upload-handler');
const url=process.env.SUPABASE_URL, key=process.env.SUPABASE_PUBLISHABLE_KEY, blobUrl=process.env.NOMINAS_BLOB_SERVICE_URL;
if(!url||!key||!blobUrl)throw Error('Falta configurar el servicio de nóminas.');
const blobClient=new BlobServiceClient(blobUrl,new DefaultAzureCredential()).getContainerClient('nominas');
async function getJson(path,token){const r=await fetch(url+path,{headers:{apikey:key,Authorization:'Bearer '+token,Accept:'application/json'},signal:AbortSignal.timeout(10000)});if(!r.ok)throw Error('Authorization request failed');return r.json();}
const handler=makeHandler({
 lookupUser:token=>getJson('/auth/v1/user',token),
 lookupDocument:async(token,id)=>{const data=await getJson('/rest/v1/nominas_documentos?id=eq.'+encodeURIComponent(id)+'&select=empleado,ano,mes,blob_key,sha256',token);return data.length===1?data[0]:null;},
 lookupAdminDocument:async(token,id)=>{try{const data=await rpc('nominas_admin_documento',token,{p_id:id});return data.length===1?data[0]:null;}catch{return null;}},
 readDocument:async key=>{const blob=blobClient.getBlobClient(key),properties=await blob.getProperties();if(properties.contentLength>15*1024*1024)throw Error('PDF too large');return blob.downloadToBuffer();}
});
app.http('descargarNomina',{methods:['GET'],authLevel:'anonymous',route:'nominas/{id}',handler});
async function rpc(name,token,args){const r=await fetch(url+'/rest/v1/rpc/'+name,{method:'POST',headers:{apikey:key,Authorization:'Bearer '+token,'Content-Type':'application/json'},body:JSON.stringify(args),signal:AbortSignal.timeout(10000)});if(!r.ok)throw Error('Database request failed');return r.json();}
const uploadHandler=makeUploadHandler({
 lookupUser:token=>getJson('/auth/v1/user',token),
 isManager:async(token,email)=>(await getJson('/rest/v1/empleados_gestores?email=eq.'+encodeURIComponent(email)+'&select=email',token)).length===1,
 lookupEmployee:async(token,email)=>(await getJson('/rest/v1/empleados_fichas?email=eq.'+encodeURIComponent(email)+'&select=email',token)).length===1,
 findPeriod:async(token,email,year,month)=>(await rpc('nominas_periodos',token,{p_ano:year,p_mes:month})).some(row=>row.empleado===email),
 writeDocument:async(key,bytes)=>blobClient.getBlockBlobClient(key).uploadData(bytes,{conditions:{ifNoneMatch:'*'},blobHTTPHeaders:{blobContentType:'application/pdf',blobCacheControl:'private, no-store'}}),
 registerDocument:(token,args)=>rpc('nominas_registrar',token,args)
});
app.http('publicarNomina',{methods:['POST'],authLevel:'anonymous',route:'nominas',handler:uploadHandler});

// Solo se habilita tras configurar el acceso restringido al buzón de Administración.
if(process.env.NOTIFICACIONES_ENABLED==='true'){
 const {makeNotificationWorker}=require('./notification-worker');
 const work=makeNotificationWorker({supabaseUrl:url,publishableKey:key,queueSecret:process.env.NOTIFICACIONES_QUEUE_SECRET,graphCredential:new DefaultAzureCredential()});
 app.timer('notificacionesAprobadas',{schedule:'0 * * * * *',handler:async(_timer,context)=>{try{await work();}catch(error){context.error('No se ha podido procesar la cola de notificaciones.',error?.name||'Error');}}});
}
