import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const source=fs.readFileSync('public/site/interesse.js','utf8').replace(/^import .*;\n/,'');
const values={nome:'Motorista Exemplo',email:'exemplo@example.invalid',cidade:'Palhoça',uf:'SC',veiculo:'moto',website:''};
const status={dataset:{},textContent:''},button={disabled:false,textContent:''};
let callback, valid=false, requests=[],responseMode='error';
const stateOptions=[];
const form={elements:{uf:{add:o=>stateOptions.push(o)},consentimento:{checked:false}},reportValidity:()=>valid,
 querySelector:()=>button,addEventListener:(_name,cb)=>callback=cb,reset:()=>{form.elements.consentimento.checked=false;}};
class FormDataMock { [Symbol.iterator](){return Object.entries(values)[Symbol.iterator]();} }
vm.runInNewContext(source,{
 document:{querySelector:selector=>selector==='#interest-form'?form:status},Option:class{constructor(text,value){this.text=text;this.value=value;}},
 apiUrl:'https://backend.example.invalid',publicKey:'public-test-key',FormData:FormDataMock,AbortSignal,TypeError,
 fetch:async(url,options)=>{requests.push({url,...options});return {ok:responseMode==='success',json:async()=>({message:responseMode==='success'?'Interesse registrado.':'Não foi possível salvar agora.'})};},
});
assert.equal(stateOptions.length,27);
const submit=()=>callback({preventDefault(){}});
await submit();assert.equal(requests.length,0,'invalid form does not send');
valid=true;form.elements.consentimento.checked=true;
await submit();assert.equal(button.disabled,false,'failure allows retry');assert.equal(status.dataset.error,'true');
assert.equal(JSON.parse(requests[0].body).consentimento,true);
responseMode='success';await Promise.all([submit(),submit()]);assert.equal(requests.length,2,'pending submit is not duplicated');
assert.equal(button.disabled,true);assert.equal(status.textContent,'Interesse registrado.');assert.equal(form.elements.consentimento.checked,false);
await submit();assert.equal(requests.length,2,'success is not submitted again');
console.log('PASS: form validation gate, 27 states, explicit consent payload, failure retry, duplicate-click protection and successful confirmation.');
