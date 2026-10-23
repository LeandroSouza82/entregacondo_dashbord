import test from 'node:test';
import assert from 'node:assert/strict';
import {estimateServiceTimes} from '../src/features/routes/services/serviceTimeEstimates.ts';
test('prefers this driver at each address and falls back to real local samples',()=>{
 const result=estimateServiceTimes(['a','b'],'driver',[{addressId:'a',driverId:'driver',minutes:2},{addressId:'a',driverId:'other',minutes:20},{addressId:'b',driverId:'other',minutes:3}]);
 assert.deepEqual(result,{minutes:5,covered:2,total:2,driverSpecific:1,complete:true});
});
test('missing or invalid samples never fabricate a complete journey',()=>{
 const result=estimateServiceTimes(['a','b'],'driver',[{addressId:'a',driverId:'driver',minutes:NaN}]);
 assert.equal(result.complete,false);assert.equal(result.covered,0);assert.equal(result.minutes,0);
});
