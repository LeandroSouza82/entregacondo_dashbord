export interface ServiceSample { addressId: string; driverId: string; minutes: number }
export function estimateServiceTimes(addresses: string[], driverId: string, samples: ServiceSample[]) {
 let minutes=0,covered=0,driverSpecific=0;
 for(const address of addresses){
  const valid=samples.filter(s=>s.addressId===address && Number.isFinite(s.minutes) && s.minutes>=0);
  const own=valid.filter(s=>s.driverId===driverId);
  const selected=(own.length?own:valid).slice(0,20);
  if(!selected.length) continue;
  minutes+=selected.reduce((sum,s)=>sum+s.minutes,0)/selected.length;covered++;
  if(own.length)driverSpecific++;
 }
 return {minutes,covered,total:addresses.length,driverSpecific,complete:addresses.length>0 && covered===addresses.length};
}
