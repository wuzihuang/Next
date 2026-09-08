export type ShopLocale = 'en' | 'zh';

export function localeFromPath(pathname: string): ShopLocale | null {
  if (pathname === '/zh' || pathname.startsWith('/zh/')) return 'zh';
  return null;
}

export function localeFromRequest(
  request: Request,
  sessionLocale?: string | null,
): ShopLocale {
  const pathname = new URL(request.url).pathname;
  const fromPath = localeFromPath(pathname);
  if (fromPath) return fromPath;
  if (sessionLocale === 'zh' || sessionLocale === 'en') return sessionLocale;
  const accept = request.headers.get('accept-language') || '';
  if (/(^|,|\s)zh\b/i.test(accept)) return 'zh';
  return 'en';
}

export function pickLocale<T>(locale: ShopLocale, en: T, zh: T): T {
  return locale === 'zh' ? zh : en;
}

export function localeHome(locale: ShopLocale): string {
  return locale === 'zh' ? '/zh' : '/';
}
