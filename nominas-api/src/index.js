'use strict';
const {app}=require('@azure/functions');
const {DefaultAzureCredential}=require('@azure/identity');
const {BlobServiceClient}=require('@azure/storage-blob');
const {makeHandler}=require('./handler');
const url=process.env.SUPABASE_URL, key=process.env.SUPABASE_PUBLISHABLE_KEY, blobUrl=process.env.NOMINAS_BLOB_SERVICE_URL;
if(!url||!key||!blobUrl)throw Error('Falta configurar el servicio de nóminas.');
const blobClient=new BlobServiceClient(blobUrl,new DefaultAzureCredential()).getContainerClient('nominas');
async function getJson(path,token){const r=await fetch(url+path,{headers:{apikey:key,Authorization:'Bearer '+token,Accept:'application/json'},signal:AbortSignal.timeout(10000)});if(!r.ok)throw Error('Authorization request failed');return r.json();}
const handler=makeHandler({
 lookupUser:token=>getJson('/auth/v1/user',token),
 lookupDocument:async(token,id)=>{const data=await getJson('/rest/v1/nominas_documentos?id=eq.'+encodeURIComponent(id)+'&select=empleado,ano,mes,blob_key,sha256',token);return data.length===1?data[0]:null;},
 readDocument:async key=>{const blob=blobClient.getBlobClient(key),properties=await blob.getProperties();if(properties.contentLength>15*1024*1024)throw Error('PDF too large');return blob.downloadToBuffer();}
});
app.http('descargarNomina',{methods:['GET'],authLevel:'anonymous',route:'nominas/{id}',handler});
