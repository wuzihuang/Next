import {Form, Link} from 'react-router';
import {ProductCard} from './CatalogView';
import type {CatalogProduct} from '~/lib/catalog';
import type {ShopLocale} from '~/lib/locale';
import {localeHome, pickLocale} from '~/lib/locale';
import type {PolicyPage} from '~/lib/policies';
import type {JournalArticle, SitePage} from '~/lib/sitePages';
import {JOURNAL} from '~/lib/sitePages';
import {shopCopy} from '~/lib/shopCopy';

export function PolicyView({
  locale,
  policy,
}: {
  locale: ShopLocale;
  policy: PolicyPage;
}) {
  const t = shopCopy(locale);
  return (
    <article className="shop-page shop-prose">
      <Link className="shop-text-btn" prefetch="intent" to="/policies">
        ← {t.pages.back}
      </Link>
      <h1>{pickLocale(locale, policy.title.en, policy.title.zh)}</h1>
      <p className="shop-hint">{policy.updated}</p>
      {policy.sections.map((section) => (
        <section key={section.heading.en}>
          <h2>{pickLocale(locale, section.heading.en, section.heading.zh)}</h2>
          {pickLocale(locale, section.body.en, section.body.zh).map((para) => (
            <p key={para}>{para}</p>
          ))}
        </section>
      ))}
    </article>
  );
}

export function PolicyIndexView({
  locale,
  policies,
}: {
  locale: ShopLocale;
  policies: PolicyPage[];
}) {
  const t = shopCopy(locale);
  return (
    <div className="shop-page">
      <h1>{t.footer.legal}</h1>
      <ul className="shop-link-list">
        {policies.map((policy) => (
          <li key={policy.handle}>
            <Link prefetch="intent" to={`/policies/${policy.handle}`}>
              {pickLocale(locale, policy.title.en, policy.title.zh)}
            </Link>
          </li>
        ))}
      </ul>
    </div>
  );
}

export function ContentPageView({
  locale,
  page,
}: {
  locale: ShopLocale;
  page: SitePage;
}) {
  return (
    <article className="shop-page shop-prose">
      {page.image ? (
        <div className="shop-page-hero" style={{backgroundImage: `url(${page.image})`}} />
      ) : null}
      <p className="shop-kicker">
        {pickLocale(locale, page.kicker.en, page.kicker.zh)}
      </p>
      <h1>{pickLocale(locale, page.title.en, page.title.zh)}</h1>
      <p className="shop-lede">{pickLocale(locale, page.lede.en, page.lede.zh)}</p>
      {page.sections.map((section) => (
        <section key={section.heading.en}>
          <h2>{pickLocale(locale, section.heading.en, section.heading.zh)}</h2>
          {pickLocale(locale, section.body.en, section.body.zh).map((para) => (
            <p key={para}>{para}</p>
          ))}
        </section>
      ))}
    </article>
  );
}

export function JournalIndexView({locale}: {locale: ShopLocale}) {
  const t = shopCopy(locale);
  return (
    <div className="shop-page">
      <h1>{t.footer.journal}</h1>
      <div className="shop-grid">
        {JOURNAL.map((article) => (
          <Link
            className="shop-card"
            key={article.handle}
            prefetch="intent"
            to={`/blogs/journal/${article.handle}`}
          >
            <div
              className="shop-card-media"
              style={{backgroundImage: `url(${article.image})`}}
            />
            <div className="shop-card-copy">
              <span>{article.date}</span>
              <strong>{pickLocale(locale, article.title.en, article.title.zh)}</strong>
              <em>{pickLocale(locale, article.lede.en, article.lede.zh)}</em>
            </div>
          </Link>
        ))}
      </div>
    </div>
  );
}

export function JournalArticleView({
  locale,
  article,
}: {
  locale: ShopLocale;
  article: JournalArticle;
}) {
  const t = shopCopy(locale);
  return (
    <article className="shop-page shop-prose">
      <Link className="shop-text-btn" prefetch="intent" to="/blogs">
        ← {t.footer.journal}
      </Link>
      <div
        className="shop-page-hero"
        style={{backgroundImage: `url(${article.image})`}}
      />
      <p className="shop-hint">{article.date}</p>
      <h1>{pickLocale(locale, article.title.en, article.title.zh)}</h1>
      <p className="shop-lede">{pickLocale(locale, article.lede.en, article.lede.zh)}</p>
      {pickLocale(locale, article.body.en, article.body.zh).map((para) => (
        <p key={para}>{para}</p>
      ))}
    </article>
  );
}

export function SearchView({
  locale,
  term,
  products,
}: {
  locale: ShopLocale;
  term: string;
  products: CatalogProduct[];
}) {
  const t = shopCopy(locale);
  return (
    <div className="shop-page">
      <h1>{t.search.title}</h1>
      <Form className="shop-search" method="get">
        <input
          defaultValue={term}
          name="q"
          placeholder={t.search.placeholder}
          type="search"
        />
        <button className="lp-pill" type="submit">
          {t.search.submit}
        </button>
      </Form>
      {term && products.length === 0 ? (
        <p className="shop-lede">{t.search.empty}</p>
      ) : (
        <div className="shop-grid">
          {products.map((product) => (
            <ProductCard key={product.handle} locale={locale} product={product} />
          ))}
        </div>
      )}
    </div>
  );
}

export function NotFoundView({locale}: {locale: ShopLocale}) {
  const t = shopCopy(locale);
  return (
    <div className="shop-page shop-notfound">
      <h1>{t.notFound.title}</h1>
      <p className="shop-lede">{t.notFound.lede}</p>
      <div className="pdp-actions">
        <Link className="lp-pill lp-pill-lime" prefetch="intent" to="/collections/all">
          {t.notFound.shop}
        </Link>
        <Link className="lp-pill" prefetch="intent" to={localeHome(locale)}>
          {t.notFound.home}
        </Link>
      </div>
    </div>
  );
}
