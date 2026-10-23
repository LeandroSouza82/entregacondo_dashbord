import { createCheckoutHandler } from '../_shared/subscriptionBilling.ts';
import { billing } from '../_shared/subscriptionBillingAdapter.ts';
Deno.serve(createCheckoutHandler(billing));
