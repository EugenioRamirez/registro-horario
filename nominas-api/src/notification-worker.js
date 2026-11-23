'use strict';
const {processOne}=require('./notifications');
function makeNotificationWorker({supabaseUrl,publishableKey,queueSecret,graphCredential,fetcher=fetch}) {
 if(!/^https:\/\/[a-z0-9-]+\.supabase\.co$/i.test(supabaseUrl||'')||!publishableKey||!queueSecret||!graphCredential)throw Error('Falta configurar el servicio de notificaciones.');
 const rpc=async(name,body)=>{const r=await fetcher(`${supabaseUrl}/rest/v1/rpc/${name}`,{method:'POST',headers:{apikey:publishableKey,Authorization:`Bearer ${publishableKey}`,'Content-Type':'application/json'},body:JSON.stringify(body),signal:AbortSignal.timeout(15000)});if(!r.ok)throw Error('Error en la cola de notificaciones');return r.status===204?null:r.json();};
 const claim=async()=>{const rows=await rpc('portal_notificaciones_tomar',{p_secreto:queueSecret});return rows?.[0]||null;};
 const finish=(id,state)=>rpc('portal_notificaciones_finalizar',{p_id:id,p_estado:state,p_secreto:queueSecret});
 const send=async m=>{const token=await graphCredential.getToken('https://graph.microsoft.com/.default');if(!token?.token)throw Error('Sin credencial de envío');const r=await fetcher('https://graph.microsoft.com/v1.0/users/administracion%40xpecializa.com/sendMail',{method:'POST',headers:{Authorization:`Bearer ${token.token}`,'Content-Type':'application/json'},body:JSON.stringify({message:{subject:m.subject,body:{contentType:'HTML',content:m.html},toRecipients:[{emailAddress:{address:m.to}}]},saveToSentItems:true}),signal:AbortSignal.timeout(20000)});return r.status;};
 return async()=>{for(let i=0;i<20;i++)if(!await processOne({claim,send,finish}))break;};
}
module.exports={makeNotificationWorker};
