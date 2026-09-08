import {redirect} from 'react-router';
import type {Route} from './+types/blogs.$blogHandle._index';

export async function loader({params}: Route.LoaderArgs) {
  if (params.blogHandle === 'journal') return redirect('/blogs');
  throw new Response(null, {status: 404});
}
