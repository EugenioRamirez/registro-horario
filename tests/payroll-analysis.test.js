'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {identifiers,period,analysePage,assess}=require('../payroll-analysis.js');
const emp=[{email:'one@xpecializa.com',dni_nie:'12345678Z'},{email:'two@xpecializa.com',dni_nie:'X1234567L'}];
const valid='TRABAJADOR/A D.N.I. 12345678Z PERIODO MENS 01 NOV 26 a 30 NOV 26 CUANTIA';
test('identifica por documento y reconoce el periodo abreviado del PDF real',()=>{
  assert.deepEqual(identifiers(valid),['12345678Z']);
  assert.deepEqual(analysePage(valid,emp,2026,11),{email:'one@xpecializa.com',period:'matching',hasHeader:true,idsFound:1});
  assert.equal(period(valid,2026,12),'conflict');
});
test('bloquea documentos ambiguos, períodos incompletos o incorrectos y nombres sin identidad',()=>{
  assert.equal(analysePage(valid+' X1234567L',emp,2026,11).email,'');
  assert.equal(analysePage('TRABAJADOR/A María Pérez PERIODO 01 NOV 26 a 30 NOV 26',emp,2026,11).email,'');
  assert.equal(period('PERIODO 01 NOV 26',2026,11),'unknown');
  assert.equal(period('PERIODO 01 NOV 26 a 31 NOV 26',2026,11),'unknown');
  assert.equal(period('PERIODO 30 NOV 26 a 01 NOV 26',2026,11),'unknown');
});
test('solo permite publicar coincidencias únicas con periodo correcto y sin documento existente',()=>{
  const groups=[{email:emp[0].email,period:'matching'},{email:emp[1].email,period:'unknown'},{email:'',period:'matching'},{email:'three@xpecializa.com',period:'conflict'},{email:'four@xpecializa.com',period:'matching'},{email:'five@xpecializa.com',period:'matching'},{email:'five@xpecializa.com',period:'matching'}];
  const results=assess(groups,new Set(['four@xpecializa.com']));
  assert.deepEqual(results.map(x=>x.eligible),[true,false,false,false,false,false,false]);
  assert.equal(results[1].status,'Período no reconocido');
  assert.equal(results[3].status,'Período distinto');
  assert.equal(results[4].status,'Ya existe una nómina');
  assert.equal(results[5].status,'Asignación duplicada');
  assert.equal(assess([{...groups[0],published:true}],new Set())[0].eligible,false);
});
