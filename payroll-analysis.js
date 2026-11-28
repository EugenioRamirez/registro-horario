'use strict';
// This module is shared by the administrator's browser and the local tests.
(function(root){
  const months={ENE:1,ENERO:1,FEB:2,FEBRERO:2,MAR:3,MARZO:3,ABR:4,ABRIL:4,MAY:5,MAYO:5,JUN:6,JUNIO:6,JUL:7,JULIO:7,AGO:8,AGOSTO:8,SEP:9,SEPT:9,SEPTIEMBRE:9,SET:9,OCT:10,OCTUBRE:10,NOV:11,NOVIEMBRE:11,DIC:12,DICIEMBRE:12};
  function normalize(value){return String(value||'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toUpperCase();}
  function identifiers(text){return [...new Set((normalize(text).match(/\b(?:[XYZ]\s*\d{7}|\d{8})\s*[A-Z]\b/g)||[]).map(x=>x.replace(/\s/g,'')))];}
  function period(text,year,month){
    const t=normalize(text),start=t.indexOf('PERIODO');
    if(start<0)return 'unknown';
    const area=t.slice(start,start+350).split(/CUANTIA|DEVENGOS|DEDUCCIONES/)[0];
    const re=/\b(\d{1,2})\s+(ENERO|FEBRERO|MARZO|ABRIL|MAYO|JUNIO|JULIO|AGOSTO|SEPTIEMBRE|OCTUBRE|NOVIEMBRE|DICIEMBRE|SEPT|ENE|FEB|MAR|ABR|MAY|JUN|JUL|AGO|SEP|SET|OCT|NOV|DIC)\s+(\d{4}|\d{2})\b/g;
    const dates=[...area.matchAll(re)].map(m=>({day:Number(m[1]),month:months[m[2]],year:m[3].length===2?2000+Number(m[3]):Number(m[3])}));
    if(dates.length!==2)return 'unknown';
    if(dates.some(d=>d.day<1||d.day>31||new Date(Date.UTC(d.year,d.month-1,d.day)).getUTCDate()!==d.day))return 'unknown';
    if(Date.UTC(dates[0].year,dates[0].month-1,dates[0].day)>Date.UTC(dates[1].year,dates[1].month-1,dates[1].day))return 'unknown';
    return dates.every(d=>d.year===year&&d.month===month)?'matching':'conflict';
  }
  function analysePage(text,employees,year,month){
    const found=identifiers(text),matches=employees.filter(e=>found.includes(normalize(e.dni_nie).replace(/[^A-Z0-9]/g,'')));
    return {email:found.length===1&&matches.length===1?String(matches[0].email).toLowerCase():'',period:period(text,year,month),hasHeader:normalize(text).includes('PERIODO'),idsFound:found.length};
  }
  function assess(groups,existing){
    const counts=new Map();for(const g of groups)if(g.email)counts.set(g.email,(counts.get(g.email)||0)+1);
    return groups.map(g=>{
      let status='Preparada',eligible=true;
      if(g.published){status='Publicada';eligible=false;}
      else if(!g.email){status='Identificación no concluyente';eligible=false;}
      else if(g.period==='conflict'){status='Período distinto';eligible=false;}
      else if(g.period!=='matching'){status='Período no reconocido';eligible=false;}
      else if(existing.has(g.email)){status='Ya existe una nómina';eligible=false;}
      else if(counts.get(g.email)!==1){status='Asignación duplicada';eligible=false;}
      else if(g.tooLarge){status='Documento demasiado grande';eligible=false;}
      return {...g,status,eligible};
    });
  }
  const api={normalize,identifiers,period,analysePage,assess};
  if(typeof module!=='undefined'&&module.exports)module.exports=api;
  else root.PayrollAnalysis=api;
})(typeof window==='undefined'?globalThis:window);
