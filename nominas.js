'use strict';
const nominaEl = id => document.getElementById(id);
const nominaMeses = ['Enero','Febrero','Marzo','Abril','Mayo','Junio','Julio','Agosto','Septiembre','Octubre','Noviembre','Diciembre'];
const NOMINAS_API_URL = 'https://xp-nominas-api-cfghh3dxdca2agh8.westeurope-01.azurewebsites.net';

async function cargarNominas() {
  const list = nominaEl('nominas-list'), message = nominaEl('nominas-message');
  list.replaceChildren();
  message.textContent = 'Cargando tus nóminas...';
  try {
    const {data:{session},error} = await portalAuth.auth.getSession();
    if (error || !session?.user?.email) throw Error('Sesión no disponible');
    const {data,error:dbError} = await portalAuth.from('nominas_documentos').select('id,ano,mes').order('ano',{ascending:false}).order('mes',{ascending:false});
    if (dbError) throw dbError;
    if (!data.length) { message.textContent = 'Todavía no tienes nóminas disponibles.'; return; }
    message.textContent = '';
    for (const row of data) {
      const wrapper = document.createElement('div');
      wrapper.className = 'vac-entry';
      const text = document.createElement('div'), link = document.createElement('a'), sub = document.createElement('small');
      link.href = '#';
      link.className = 'nomina-link';
      link.textContent = nominaMeses[row.mes - 1] + ' ' + row.ano;
      link.setAttribute('aria-label', 'Abrir nómina de ' + link.textContent + ' en una pestaña nueva');
      link.addEventListener('click', event => { event.preventDefault(); abrirNomina(row.id, link); });
      sub.textContent = 'Documento PDF · Se abre en una pestaña nueva';
      text.append(link, sub);
      wrapper.append(text);
      list.append(wrapper);
    }
  } catch (e) { message.textContent = 'No se han podido cargar tus nóminas.'; }
}

async function abrirNomina(id, link, message = nominaEl('nominas-message')) {
  // La pestaña se abre en respuesta al clic para que el navegador no la bloquee.
  const viewer = window.open('about:blank', '_blank');
  if (!viewer) { message.textContent = 'Permite las ventanas emergentes para abrir la nómina.'; return; }
  viewer.opener = null;
  link.setAttribute('aria-busy','true');
  message.textContent = '';
  try {
    const {data:{session}} = await portalAuth.auth.getSession();
    if (!session?.access_token) throw Error('Sesión no disponible');
    const res = await fetch(NOMINAS_API_URL + '/api/nominas/' + encodeURIComponent(id), {
      headers:{Authorization:'Bearer ' + session.access_token}, cache:'no-store'
    });
    if (!res.ok || !(res.headers.get('content-type') || '').includes('application/pdf')) throw Error('Documento no disponible');
    const blob = await res.blob();
    const local = URL.createObjectURL(blob);
    viewer.location.replace(local);
    if(typeof portalAuditar==='function')portalAuditar('Nómina abierta','Nóminas');
    setTimeout(() => URL.revokeObjectURL(local), 600000);
  } catch (e) {
    viewer.close();
    message.textContent = 'No se ha podido abrir la nómina. Vuelve a intentarlo o contacta con administración.';
  } finally { link.removeAttribute('aria-busy'); }
}
