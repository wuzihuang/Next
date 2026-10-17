import {redirect} from 'react-router';

// Payment confirmation lives on Shopify; old local test-order links are retired.
export function loader() {
  return redirect('/cart');
}
