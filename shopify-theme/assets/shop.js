function bootShop() {
  const root = document.getElementById('nb-shop');
  const catalogNode = document.getElementById('nb-catalog');
  if (!root || !catalogNode) return;

  const catalog = JSON.parse(catalogNode.textContent);
  const pricing = window.NextBodyCart;
  const locale = root.dataset.locale === 'zh' ? 'zh' : 'en';
  const copy = locale === 'zh' ? ZH : EN;

  function pick(value) {
    if (!value) return '';
    if (typeof value === 'string') return value;
    return locale === 'zh' ? value.zh : value.en;
  }

  const money = pricing.formatMoney;

  function cartInput(bag) {
    return {
      lines: (Array.isArray(bag.lines) ? bag.lines : []).map((line) => ({
        variantId: line?.variantId,
        quantity: line?.qty,
      })),
      discountCode: bag.discountCode,
    };
  }

  function storedLines(quote) {
    return quote.lines.map(({line, product}) => ({
      handle: product.handle,
      variantId: line.variantId,
      qty: line.quantity,
    }));
  }

  function writeCart(bag, cart) {
    bag.lines = storedLines(pricing.quoteCart(cart, catalog.products));
    bag.discountCode = cart.discountCode || '';
    writeBag(bag);
  }

  function readBag() {
    try {
      const raw = JSON.parse(localStorage.getItem('nb_theme_shop') || '{}');
      const lines = storedLines(pricing.quoteCart(cartInput(raw), catalog.products));
      return {
        lines,
        discountCode: raw.discountCode || '',
        orders: Array.isArray(raw.orders) ? raw.orders : [],
        account: raw.account || null,
      };
    } catch {
      return {lines: [], discountCode: '', orders: [], account: null};
    }
  }

  function writeBag(bag) {
    localStorage.setItem('nb_theme_shop', JSON.stringify(bag));
  }

  function findProduct(handle) {
    return catalog.products.find((item) => item.handle === handle);
  }

  function findVariant(product, variantId) {
    const resolved = pricing.canonicalVariantId(variantId);
    return product.variants.find((item) => item.id === resolved) || product.variants[0];
  }

  function findVariantByOptions(product, selected) {
    return (
      product.variants.find((variant) =>
        product.options.every((option) => variant.options[option.id] === selected[option.id]),
      ) || product.variants[0]
    );
  }

  function totals(bag) {
    const quote = pricing.quoteCart(cartInput(bag), catalog.products);
    return {
      ...quote,
      rows: quote.lines.map(({line, product, variant}) => ({
        line: {handle: product.handle, variantId: line.variantId, qty: line.quantity},
        product,
        variant,
      })),
      count: quote.quantity,
    };
  }

  function langQuery(extra) {
    const params = new URLSearchParams(extra || '');
    if (locale === 'zh') params.set('lang', 'zh');
    const text = params.toString();
    return text ? '?' + text : '';
  }

  function shopLink(path, extra) {
    return path + langQuery(extra);
  }

  function route() {
    const url = new URL(location.href);
    const path = url.pathname.replace(/\/+$/, '') || '/';
    const product =
      url.searchParams.get('product') ||
      (path.startsWith('/products/') ? path.split('/')[2] : '');
    const page =
      url.searchParams.get('page') ||
      (path.startsWith('/policies/') ? path.split('/')[2] : '') ||
      (path.startsWith('/pages/') && path !== '/pages/zh' ? path.split('/')[2] : '');
    if (path === '/cart' && url.searchParams.get('complete')) {
      return {name: 'complete', order: url.searchParams.get('order') || ''};
    }
    if (path === '/cart' && url.searchParams.has('checkout')) return {name: 'checkout'};
    if (path === '/cart') return {name: 'cart'};
    if (path === '/search') return {name: 'search', q: url.searchParams.get('q') || ''};
    if (product) return {name: 'pdp', handle: product};
    if (page) return {name: 'page', handle: page};
    return {name: 'catalog'};
  }

  function addLine(variantId, qty, redirectTo) {
    const bag = readBag();
    writeCart(bag, pricing.addLine(cartInput(bag), variantId, qty));
    if (redirectTo) location.assign(redirectTo);
    else render();
  }

  function header(count) {
    const home = locale === 'zh' ? '/pages/zh' : '/';
    return (
      '<header class="lp-nav shop-nav">' +
      '<a class="lp-wordmark" href="' +
      home +
      '"><span class="lp-wordmark-name">NEXTBODY</span><span class="lp-pip"></span></a>' +
      '<nav class="lp-nav-mid" aria-label="Primary">' +
      '<a class="lp-nav-link" href="' +
      home +
      '#band">' +
      copy.nav.band +
      '</a>' +
      '<a class="lp-nav-link" href="' +
      shopLink('/collections/all') +
      '">' +
      copy.nav.shop +
      '</a>' +
      '<a class="lp-nav-link" href="' +
      shopLink('/collections/all', 'page=science') +
      '">' +
      copy.nav.science +
      '</a></nav>' +
      '<div class="lp-nav-end">' +
      '<div class="lp-langs"><a class="lp-lang' +
      (locale === 'en' ? ' is-on' : '') +
      '" href="' +
      location.pathname +
      location.search.replace(/([?&])lang=zh/, '').replace(/^\?&/, '?') +
      '">EN</a><span class="lp-lang-rule"></span><a class="lp-lang' +
      (locale === 'zh' ? ' is-on' : '') +
      '" href="' +
      (location.search.includes('lang=zh')
        ? location.pathname + location.search
        : location.pathname +
          (location.search ? location.search + '&lang=zh' : '?lang=zh')) +
      '">中文</a></div>' +
      '<a class="shop-cart-link" href="' +
      shopLink('/cart') +
      '">' +
      copy.nav.cart +
      '<b>' +
      count +
      '</b></a>' +
      '<a class="lp-pill" href="' +
      shopLink('/collections/all', 'product=hoop') +
      '">' +
      copy.nav.getHoop +
      '</a></div></header>'
    );
  }

  function footer() {
    const home = locale === 'zh' ? '/pages/zh' : '/';
    return (
      '<div class="shop-foot-wrap"><footer class="lp-foot shop-foot">' +
      '<div class="lp-foot-brand"><p class="lp-wordmark"><span class="lp-wordmark-name">NEXTBODY</span><span class="lp-pip"></span></p><p>' +
      copy.footer.tag +
      '</p></div><div class="lp-foot-cols">' +
      '<nav class="lp-foot-col"><b>' +
      copy.footer.product +
      '</b><a href="' +
      home +
      '#band">' +
      copy.footer.band +
      '</a><a href="' +
      shopLink('/collections/all') +
      '">' +
      copy.footer.shop +
      '</a><a href="' +
      shopLink('/collections/all', 'page=science') +
      '">' +
      copy.footer.science +
      '</a></nav>' +
      '<nav class="lp-foot-col"><b>' +
      copy.footer.support +
      '</b><a href="' +
      shopLink('/collections/all', 'page=faq') +
      '">' +
      copy.footer.faq +
      '</a><a href="' +
      shopLink('/collections/all', 'page=about') +
      '">' +
      copy.footer.about +
      '</a><a href="' +
      shopLink('/collections/all', 'page=contact') +
      '">' +
      copy.footer.contact +
      '</a></nav>' +
      '<nav class="lp-foot-col"><b>' +
      copy.footer.legal +
      '</b><a href="' +
      shopLink('/collections/all', 'page=privacy-policy') +
      '">' +
      copy.footer.privacy +
      '</a><a href="' +
      shopLink('/collections/all', 'page=refund-policy') +
      '">' +
      copy.footer.refund +
      '</a><a href="' +
      shopLink('/collections/all', 'page=shipping-policy') +
      '">' +
      copy.footer.shipping +
      '</a><a href="' +
      shopLink('/collections/all', 'page=terms-of-service') +
      '">' +
      copy.footer.terms +
      '</a></nav></div></footer>' +
      '<div class="lp-legal"><span>' +
      copy.footer.disclaimer +
      '</span><span>' +
      copy.footer.copy +
      '</span></div></div>'
    );
  }

  function card(product) {
    const image = product.variants[0].image;
    return (
      '<a class="shop-card" href="' +
      shopLink('/collections/all', 'product=' + product.handle) +
      '"><div class="shop-card-media"><img alt="" src="' +
      image +
      '"></div><div class="shop-card-copy"><span>' +
      pick(product.kicker) +
      '</span><strong>' +
      pick(product.title) +
      '</strong><em>' +
      copy.shop.from +
      ' ' +
      money(product.price) +
      '</em></div></a>'
    );
  }

  function renderCatalog() {
    return renderPdp('hoop');
  }

  function selectedFromUrl(product) {
    const url = new URL(location.href);
    const selected = {};
    product.options.forEach((option) => {
      const value = url.searchParams.get(option.id);
      selected[option.id] = option.values.some((item) => item.id === value)
        ? value
        : option.values[0].id;
    });
    return selected;
  }

  function optionHref(product, selected, key, value) {
    const next = Object.assign({}, selected, {[key]: value});
    const params = new URLSearchParams({product: product.handle});
    Object.keys(next).forEach((id) => params.set(id, next[id]));
    return shopLink('/collections/all', params.toString());
  }

  function renderPdp(handle) {
    const product = findProduct(handle);
    if (!product) {
      return (
        '<div class="shop-page shop-notfound"><h1>404</h1><p class="shop-lede">' +
        copy.shop.empty +
        '</p><a class="kit-btn kit-btn-lime" href="' +
        shopLink('/collections/all') +
        '">' +
        copy.cart.continue +
        '</a></div>'
      );
    }
    const selected = selectedFromUrl(product);
    const variant = findVariantByOptions(product, selected);
    const images = variant.images.length ? variant.images : [variant.image];
    const url = new URL(location.href);
    const active = url.searchParams.get('img') || images[0];
    const thumbs = images
      .map((image) => {
        return (
          '<button class="' +
          (image === active ? 'is-on' : '') +
          '" data-img="' +
          image +
          '" type="button"><img alt="" src="' +
          image +
          '"></button>'
        );
      })
      .join('');
    const options = product.options
      .map((option) => {
        const swatches = option.values
          .map((value) => {
            return (
              '<button class="' +
              (selected[option.id] === value.id ? 'is-on' : '') +
              '" data-option="' +
              option.id +
              '" data-value="' +
              value.id +
              '" type="button"><i class="kit-dot kit-dot-' +
              value.id +
              '"></i>' +
              pick(value.label) +
              '</button>'
            );
          })
          .join('');
        return (
          '<fieldset class="kit-option"><legend>' +
          pick(option.name) +
          '</legend><div class="kit-swatches">' +
          swatches +
          '</div></fieldset>'
        );
      })
      .join('');
    const facts = product.facts
      .map((fact) => {
        return (
          '<div><strong>' + pick(fact.value) + '</strong><span>' + pick(fact.label) + '</span></div>'
        );
      })
      .join('');
    const includes = (pick(product.includes) || [])
      .map((item) => '<li>' + item + '</li>')
      .join('');
    return (
      '<div class="shop-page shop-pdp kit-page" data-variant="' +
      variant.id +
      '"><section class="kit"><div class="kit-well"><img alt="" class="kit-hero" src="' +
      active +
      '"><div class="kit-thumbs">' +
      thumbs +
      '</div></div><aside class="kit-box"><p class="kit-eye">' +
      pick(product.kicker) +
      '</p><h1 class="kit-title">' +
      pick(product.title) +
      '</h1><p class="kit-price"><span class="kit-price-mark">$</span>' +
      product.price +
      '</p><p class="kit-lede">' +
      pick(product.lede) +
      '</p><form class="kit-form" id="pdp-cart" data-variant="' +
      variant.id +
      '">' +
      options +
      '<div class="kit-include"><p>' +
      copy.product.inBox +
      '</p><ul>' +
      includes +
      '</ul></div><div class="kit-actions"><button class="kit-btn" type="submit" data-intent="add">' +
      copy.product.add +
      '</button><button class="kit-btn kit-btn-lime" type="submit" data-intent="buy">' +
      copy.product.buy +
      '</button></div></form><p class="kit-ship"><b>' +
      copy.product.shipping +
      '</b><span>' +
      copy.product.shippingNote +
      '</span></p><div class="kit-facts">' +
      facts +
      '</div><div class="kit-body">' +
      pick(product.description)
        .map((para) => '<p>' + para + '</p>')
        .join('') +
      '<p class="kit-legal">' +
      copy.product.legal +
      '</p></div></aside></section><div class="kit-dock"><p><span>' +
      pick(product.title) +
      '</span><strong>$' +
      product.price +
      '</strong></p><button class="kit-btn" form="pdp-cart" type="submit" data-intent="add">' +
      copy.product.add +
      '</button><button class="kit-btn kit-btn-lime" form="pdp-cart" type="submit" data-intent="buy">' +
      copy.product.buy +
      '</button></div></div>'
    );
  }

  function renderLines(rows) {
    return rows
      .map((row) => {
        const optionLabel = Object.values(row.variant.options)
          .map((id) => {
            const option = row.product.options.find((item) =>
              item.values.some((value) => value.id === id),
            );
            const value = option && option.values.find((item) => item.id === id);
            return value ? pick(value.label) : id;
          })
          .join(' · ');
        return (
          '<li class="shop-line"><div class="shop-line-media"><img alt="" src="' +
          row.variant.image +
          '"></div><div class="shop-line-copy"><strong>' +
          pick(row.product.title) +
          '</strong><span>' +
          optionLabel +
          '</span><em>' +
          money(row.product.price) +
          '</em><div class="shop-line-ops"><select data-qty="' +
          row.variant.id +
          '">' +
          [1, 2, 3, 4, 5, 6, 7, 8, 9]
            .map((n) => {
              return (
                '<option value="' +
                n +
                '"' +
                (n === row.line.qty ? ' selected' : '') +
                '>' +
                n +
                '</option>'
              );
            })
            .join('') +
          '</select><button class="shop-text-btn" data-remove="' +
          row.variant.id +
          '" type="button">' +
          copy.cart.remove +
          '</button></div></div></li>'
        );
      })
      .join('');
  }

  function summary(bag, math, extra) {
    return (
      '<aside class="shop-summary"><form class="shop-code" id="discount-form"><label>' +
      copy.cart.code +
      '<div><input name="code" value="' +
      bag.discountCode +
      '" placeholder="' +
      copy.cart.codeHint +
      '"><button class="lp-pill" type="submit">' +
      copy.cart.apply +
      '</button></div></label></form><dl><div><dt>' +
      copy.cart.subtotal +
      '</dt><dd>' +
      money(math.subtotal) +
      '</dd></div>' +
      (math.discount
        ? '<div><dt>' + copy.cart.discount + '</dt><dd>−' + money(math.discount) + '</dd></div>'
        : '') +
      '<div><dt>' +
      copy.cart.shipping +
      '</dt><dd>' +
      (math.shipping === 0 ? copy.cart.shippingFree : money(math.shipping)) +
      '</dd></div><div class="is-total"><dt>' +
      copy.cart.total +
      '</dt><dd>' +
      money(math.total) +
      '</dd></div></dl>' +
      extra +
      '</aside>'
    );
  }

  function renderCart() {
    const bag = readBag();
    const math = totals(bag);
    if (!math.rows.length) {
      return (
        '<div class="shop-page shop-empty-block"><h1>' +
        copy.cart.title +
        '</h1><p class="shop-lede">' +
        copy.cart.empty +
        '</p><a class="lp-pill lp-pill-lime" href="' +
        shopLink('/collections/all', 'product=hoop') +
        '">' +
        copy.cart.continue +
        '</a></div>'
      );
    }
    return (
      '<div class="shop-page shop-cart"><h1>' +
      copy.cart.title +
      '</h1><div class="shop-cart-grid"><ul class="shop-lines">' +
      renderLines(math.rows) +
      '</ul>' +
      summary(
        bag,
        math,
        '<a class="lp-pill lp-pill-lime shop-place" href="' +
          shopLink('/cart', 'checkout=1') +
          '">' +
          copy.cart.checkout +
          '</a>',
      ) +
      '</div></div>'
    );
  }

  function accountDefaults(bag) {
    return (
      bag.account || {
        email: 'test@nextbody.ai',
        name: 'Test Buyer',
        address1: '100 Market Street',
        city: 'San Francisco',
        region: 'CA',
        zip: '94105',
        country: 'US',
        card: '4242 4242 4242 4242',
        expiry: '12 / 29',
        cvc: '123',
      }
    );
  }

  function renderCheckout() {
    const bag = readBag();
    const math = totals(bag);
    if (!math.rows.length) {
      return renderCart();
    }
    const account = accountDefaults(bag);
    const mini = math.rows
      .map((row) => {
        return (
          '<li><div class="shop-mini-media"><img alt="" src="' +
          row.variant.image +
          '"></div><div><strong>' +
          pick(row.product.title) +
          '</strong><span>× ' +
          row.line.qty +
          '</span></div><b>' +
          money(row.product.price * row.line.qty) +
          '</b></li>'
        );
      })
      .join('');
    return (
      '<div class="shop-page shop-checkout"><h1>' +
      copy.checkout.title +
      '</h1><p class="shop-banner">' +
      copy.checkout.testBanner +
      '</p><div class="shop-checkout-grid"><form class="shop-checkout-form" id="checkout-form">' +
      '<fieldset><legend>' +
      copy.checkout.contact +
      '</legend><label>' +
      copy.checkout.email +
      '<input name="email" type="email" required value="' +
      account.email +
      '"></label><label>' +
      copy.checkout.name +
      '<input name="name" required value="' +
      account.name +
      '"></label></fieldset><fieldset><legend>' +
      copy.checkout.shipping +
      '</legend><label>' +
      copy.checkout.address +
      '<input name="address1" required value="' +
      account.address1 +
      '"></label><div class="shop-split"><label>' +
      copy.checkout.city +
      '<input name="city" required value="' +
      account.city +
      '"></label><label>' +
      copy.checkout.region +
      '<input name="region" required value="' +
      account.region +
      '"></label></div><div class="shop-split"><label>' +
      copy.checkout.zip +
      '<input name="zip" required value="' +
      account.zip +
      '"></label><label>' +
      copy.checkout.country +
      '<input name="country" required value="' +
      account.country +
      '"></label></div></fieldset><fieldset><legend>' +
      copy.checkout.card +
      '</legend><label>' +
      copy.checkout.cardNumber +
      '<input name="card" required value="' +
      account.card +
      '" placeholder="4242 4242 4242 4242"></label><p class="shop-hint">' +
      copy.checkout.cardHint +
      '</p><div class="shop-split"><label>' +
      copy.checkout.expiry +
      '<input name="expiry" required value="' +
      account.expiry +
      '"></label><label>CVC<input name="cvc" required value="' +
      account.cvc +
      '"></label></div></fieldset><button class="lp-pill lp-pill-lime shop-place" type="submit">' +
      copy.checkout.place +
      ' · ' +
      money(math.total) +
      '</button></form>' +
      summary(bag, math, '<ul class="shop-mini-lines">' + mini + '</ul>') +
      '</div></div>'
    );
  }

  function renderComplete(orderId) {
    const bag = readBag();
    const order = bag.orders.find((item) => item.id === orderId) || bag.orders[0];
    if (!order) {
      return renderCart();
    }
    const items = order.lines
      .map((line) => {
        const product = findProduct(line.handle);
        const image =
          line.image ||
          (product && product.variants[0] && product.variants[0].image) ||
          '';
        return (
          '<li>' +
          (image
            ? '<div class="shop-mini-media"><img alt="" src="' + image + '"></div>'
            : '<div class="shop-mini-media"></div>') +
          '<div><strong>' +
          (product ? pick(product.title) : line.handle) +
          '</strong><span>× ' +
          line.qty +
          '</span></div><b>' +
          money(line.price * line.qty) +
          '</b></li>'
        );
      })
      .join('');
    return (
      '<div class="shop-page shop-complete"><p class="shop-kicker">' +
      copy.complete.kicker +
      '</p><h1>' +
      copy.complete.title +
      '</h1><p class="shop-lede">' +
      copy.complete.lede +
      '</p><p class="shop-order-id">' +
      copy.complete.order +
      ' ' +
      order.id +
      '</p><p>' +
      copy.complete.card +
      ' ··· ' +
      order.last4 +
      '</p><ul class="shop-mini-lines">' +
      items +
      '</ul><p class="shop-complete-total"><span>' +
      copy.cart.total +
      '</span><b>' +
      money(order.total) +
      '</b></p><div class="pdp-actions"><a class="lp-pill" href="' +
      shopLink('/collections/all') +
      '">' +
      copy.complete.back +
      '</a></div></div>'
    );
  }

  function renderPage(handle) {
    const page = PAGES.find((item) => item.handle === handle);
    if (!page) {
      return (
        '<div class="shop-page shop-notfound"><h1>404</h1><a class="lp-pill lp-pill-lime" href="' +
        shopLink('/collections/all') +
        '">' +
        copy.cart.continue +
        '</a></div>'
      );
    }
    return (
      '<article class="shop-page shop-prose"><a class="shop-text-btn" href="' +
      shopLink('/collections/all') +
      '">← ' +
      copy.pages.back +
      '</a>' +
      (page.image
        ? '<div class="shop-page-hero" style="background-image:url(' + page.image + ')"></div>'
        : '') +
      '<p class="shop-kicker">' +
      pick(page.kicker) +
      '</p><h1>' +
      pick(page.title) +
      '</h1><p class="shop-lede">' +
      pick(page.lede) +
      '</p>' +
      page.sections
        .map((section) => {
          return (
            '<section><h2>' +
            pick(section.heading) +
            '</h2>' +
            pick(section.body)
              .map((para) => '<p>' + para + '</p>')
              .join('') +
            '</section>'
          );
        })
        .join('') +
      '</article>'
    );
  }

  function renderSearch(term) {
    const q = term.trim().toLowerCase();
    const products = q
      ? catalog.products.filter((product) => {
          return (
            pick(product.title).toLowerCase().includes(q) ||
            pick(product.lede).toLowerCase().includes(q) ||
            product.handle.includes(q)
          );
        })
      : catalog.products;
    return (
      '<div class="shop-page"><h1>' +
      copy.search.title +
      '</h1><form class="shop-search" action="/search"><input name="q" value="' +
      term.replace(/"/g, '&quot;') +
      '" placeholder="' +
      copy.search.placeholder +
      '"><button class="lp-pill" type="submit">' +
      copy.search.submit +
      '</button></form><div class="shop-grid">' +
      products.map(card).join('') +
      '</div></div>'
    );
  }

  function placeOrder(form) {
    const bag = readBag();
    const math = totals(bag);
    const card = String(form.card.value || '').replace(/\D/g, '');
    if (card.length < 13 || card.length > 19) {
      window.alert(copy.checkout.cardBad);
      return;
    }
    const order = {
      id: 'NB-' + Math.random().toString(36).slice(2, 8).toUpperCase(),
      total: math.total,
      last4: card.slice(-4),
      lines: math.rows.map((row) => ({
        handle: row.product.handle,
        variant: row.variant.id,
        image: row.variant.image,
        qty: row.line.qty,
        price: row.product.price,
      })),
    };
    bag.account = {
      email: form.email.value,
      name: form.name.value,
      address1: form.address1.value,
      city: form.city.value,
      region: form.region.value,
      zip: form.zip.value,
      country: form.country.value,
    };
    bag.orders = [order].concat(bag.orders).slice(0, 12);
    bag.lines = [];
    writeBag(bag);
    location.assign(shopLink('/cart', 'complete=1&order=' + order.id));
  }

  function bind() {
    const pdp = root.querySelector('#pdp-cart');
    if (pdp) {
      pdp.addEventListener('submit', (event) => {
        event.preventDefault();
        const intent = event.submitter && event.submitter.getAttribute('data-intent');
        const variantId = pdp.getAttribute('data-variant');
        addLine(
          variantId,
          1,
          intent === 'buy' ? shopLink('/cart', 'checkout=1') : shopLink('/cart'),
        );
      });
    }
    root.querySelectorAll('[data-option]').forEach((button) => {
      button.addEventListener('click', () => {
        const url = new URL(location.href);
        url.searchParams.set('product', 'hoop');
        url.searchParams.set(button.getAttribute('data-option'), button.getAttribute('data-value'));
        url.searchParams.delete('img');
        history.replaceState({}, '', url);
        render();
      });
    });
    root.querySelectorAll('[data-img]').forEach((button) => {
      button.addEventListener('click', () => {
        const url = new URL(location.href);
        url.searchParams.set('product', 'hoop');
        url.searchParams.set('img', button.getAttribute('data-img'));
        history.replaceState({}, '', url);
        render();
      });
    });
    root.querySelectorAll('[data-remove]').forEach((button) => {
      button.addEventListener('click', () => {
        const bag = readBag();
        writeCart(bag, pricing.removeLine(cartInput(bag), button.getAttribute('data-remove')));
        render();
      });
    });
    root.querySelectorAll('[data-qty]').forEach((select) => {
      select.addEventListener('change', () => {
        const bag = readBag();
        writeCart(bag, pricing.updateLine(cartInput(bag), select.getAttribute('data-qty'), Number(select.value)));
        render();
      });
    });
    const discount = root.querySelector('#discount-form');
    if (discount) {
      discount.addEventListener('submit', (event) => {
        event.preventDefault();
        const bag = readBag();
        writeCart(bag, pricing.setDiscount(cartInput(bag), String(new FormData(discount).get('code') || '')));
        render();
      });
    }
    const checkout = root.querySelector('#checkout-form');
    if (checkout) {
      checkout.addEventListener('submit', (event) => {
        event.preventDefault();
        placeOrder(checkout);
      });
    }
  }

  function render() {
    const bag = readBag();
    const math = totals(bag);
    const current = route();
    let main = '';
    if (current.name === 'pdp') main = renderPdp(current.handle);
    else if (current.name === 'cart') main = renderCart();
    else if (current.name === 'checkout') main = renderCheckout();
    else if (current.name === 'complete') main = renderComplete(current.order);
    else if (current.name === 'page') main = renderPage(current.handle);
    else if (current.name === 'search') main = renderSearch(current.q);
    else main = renderCatalog();
    root.innerHTML = header(math.count) + '<main class="site-main">' + main + '</main>' + footer();
    bind();
  }

  render();
}

const EN = {
  nav: {
    band: 'THE BAND',
    shop: 'SHOP',
    science: 'SCIENCE',
    cart: 'CART',
    getHoop: 'GET HOOP',
  },
  footer: {
    tag: 'The screenless band. The body, read.',
    product: 'PRODUCT',
    legal: 'LEGAL',
    support: 'SUPPORT',
    band: 'The Band',
    shop: 'Shop',
    science: 'Science',
    faq: 'FAQ',
    about: 'About',
    contact: 'Contact',
    privacy: 'Privacy Policy',
    refund: 'Refund Policy',
    shipping: 'Shipping Policy',
    terms: 'Terms of Service',
    disclaimer: '18+. Not a medical device. No ECG.',
    copy: '© 2026 NextBody',
  },
  shop: {
    kicker: 'NEXTBODY',
    title: 'Shop',
    lede: '$99 once. Black or white. Both straps in the box.',
    empty: 'This page is empty.',
    from: 'From',
  },
  product: {
    add: 'Add to cart',
    buy: 'Buy now',
    shipping: 'FREE SHIPPING',
    shippingNote: 'HOOP ships free. 5–10 business days.',
    legal: '18+. Not a medical device. HOOP does not take an ECG and does not diagnose.',
    related: 'Also in the kit',
    inBox: 'IN THE BOX',
  },
  cart: {
    title: 'Cart',
    empty: 'The cart is empty. HOOP is $99 once.',
    continue: 'Continue shopping',
    checkout: 'Checkout',
    subtotal: 'Subtotal',
    discount: 'Discount',
    shipping: 'Shipping',
    shippingFree: 'Free',
    total: 'Total',
    remove: 'Remove',
    code: 'Discount code',
    apply: 'Apply',
    codeHint: 'Try TEST10 on this test shop.',
  },
  checkout: {
    title: 'Checkout',
    testBanner: 'Test checkout — you will not be charged. No card is sent to a processor.',
    contact: 'Contact',
    email: 'Email',
    name: 'Name',
    shipping: 'Shipping',
    address: 'Address',
    city: 'City',
    region: 'State',
    zip: 'ZIP',
    country: 'Country',
    card: 'Test card',
    cardNumber: 'Card number',
    cardHint: 'Use 4242 4242 4242 4242, or any 13–19 digit test number.',
    cardBad: 'Enter a 13–19 digit test card number.',
    expiry: 'MM / YY',
    place: 'Place test order',
  },
  complete: {
    kicker: 'TEST ORDER',
    title: 'HOOP is on its way — in this test.',
    lede: 'No charge. This path only closes the buy flow.',
    order: 'Order',
    card: 'Test card stored',
    back: 'Back to shop',
  },
  search: {title: 'Search', placeholder: 'HOOP…', submit: 'Search'},
  pages: {back: 'Back'},
};

const ZH = {
  nav: {
    band: '手环',
    shop: '商店',
    science: '科学依据',
    cart: '购物车',
    getHoop: '购买 HOOP',
  },
  footer: {
    tag: '无屏手环。身体，被读懂。',
    product: '产品',
    legal: '法律',
    support: '支持',
    band: '手环',
    shop: '商店',
    science: '科学依据',
    faq: '常见问题',
    about: '关于',
    contact: '联系',
    privacy: '隐私政策',
    refund: '退款政策',
    shipping: '配送政策',
    terms: '服务条款',
    disclaimer: '18 岁以上。非医疗器械。不做心电图。',
    copy: '© 2026 NextBody',
  },
  shop: {
    kicker: 'NEXTBODY',
    title: '商店',
    lede: '$99 一次付清。黑色或白色。盒内两条表带都有。',
    empty: '这一页是空的。',
    from: '起',
  },
  product: {
    add: '加入购物车',
    buy: '立即购买',
    shipping: '免运费',
    shippingNote: 'HOOP 免运费。5–10 个工作日。',
    legal: '18 岁以上。HOOP 不是医疗器械，不做心电图，也不做诊断。',
    related: '还可以一起买',
    inBox: '盒内含',
  },
  cart: {
    title: '购物车',
    empty: '购物车是空的。HOOP $99，一次付清。',
    continue: '继续购物',
    checkout: '去结算',
    subtotal: '小计',
    discount: '折扣',
    shipping: '运费',
    shippingFree: '包邮',
    total: '合计',
    remove: '移除',
    code: '优惠码',
    apply: '使用',
    codeHint: '测试店可用 TEST10。',
  },
  checkout: {
    title: '结算',
    testBanner: '测试结算 — 不会扣款。卡号不会发给任何支付机构。',
    contact: '联系方式',
    email: '邮箱',
    name: '姓名',
    shipping: '收货地址',
    address: '地址',
    city: '城市',
    region: '省 / 州',
    zip: '邮编',
    country: '国家 / 地区',
    card: '测试卡',
    cardNumber: '卡号',
    cardHint: '可用 4242 4242 4242 4242，或任意 13–19 位测试卡号。',
    cardBad: '请输入 13–19 位测试卡号。',
    expiry: '月 / 年',
    place: '提交测试订单',
  },
  complete: {
    kicker: '测试订单',
    title: 'HOOP 已下单 — 在这次测试里。',
    lede: '没有扣款。这条路径只是为了把购买流程走完。',
    order: '订单',
    card: '测试卡已记',
    back: '回到商店',
  },
  search: {title: '搜索', placeholder: 'HOOP、表带…', submit: '搜索'},
  pages: {back: '返回'},
};

const PAGES = [
  {
    handle: 'privacy-policy',
    kicker: {en: 'LEGAL', zh: '法律'},
    title: {en: 'Privacy Policy', zh: '隐私政策'},
    lede: {
      en: 'Updated 2026-09-01. This page covers the shop and the test checkout.',
      zh: '更新于 2026-09-01。本页覆盖商店和测试结算。',
    },
    sections: [
      {
        heading: {en: 'Who we are', zh: '我们是谁'},
        body: {
          en: [
            'NextBody operates the HOOP band, the NextBody app, and this shop at nextbody.ai.',
          ],
          zh: ['NextBody 运营 HOOP 手环、NextBody App，以及 nextbody.ai 上的商店。'],
        },
      },
      {
        heading: {en: 'What we collect', zh: '会收集什么'},
        body: {
          en: [
            'A test order stores name, email, address, and the last four digits of the test card. The full number is not stored and is not sent to a processor.',
          ],
          zh: [
            '测试订单会保存姓名、邮箱、地址和测试卡号后四位。完整卡号不会保存，也不会发给支付机构。',
          ],
        },
      },
    ],
  },
  {
    handle: 'refund-policy',
    kicker: {en: 'LEGAL', zh: '法律'},
    title: {en: 'Refund Policy', zh: '退款政策'},
    lede: {en: 'Updated 2026-09-01.', zh: '更新于 2026-09-01。'},
    sections: [
      {
        heading: {en: 'This test shop', zh: '本测试店'},
        body: {
          en: ['Orders here are test orders. No payment is taken, so there is nothing to refund.'],
          zh: ['这里的订单都是测试订单。没有扣款，因此也没有可退的钱。'],
        },
      },
    ],
  },
  {
    handle: 'shipping-policy',
    kicker: {en: 'LEGAL', zh: '法律'},
    title: {en: 'Shipping Policy', zh: '配送政策'},
    lede: {en: 'Updated 2026-09-01.', zh: '更新于 2026-09-01。'},
    sections: [
      {
        heading: {en: 'Cost and time', zh: '费用和时效'},
        body: {
          en: [
            'Shipping is $8 on strap-only carts. Carts of $99 or more — including a single HOOP — ship free.',
          ],
          zh: ['只买表带时运费 $8。满 $99（包括单独买一条 HOOP）免运费。'],
        },
      },
    ],
  },
  {
    handle: 'terms-of-service',
    kicker: {en: 'LEGAL', zh: '法律'},
    title: {en: 'Terms of Service', zh: '服务条款'},
    lede: {en: 'Updated 2026-09-01.', zh: '更新于 2026-09-01。'},
    sections: [
      {
        heading: {en: 'Test checkout', zh: '测试结算'},
        body: {
          en: [
            'The checkout on this storefront is a closed test. It does not charge the card and it does not create a real shipment.',
          ],
          zh: ['本店结算是闭环测试。不会扣款，也不会产生真实发货。'],
        },
      },
    ],
  },
  {
    handle: 'science',
    kicker: {en: 'WHAT IT READS', zh: '它读什么'},
    title: {en: 'Science', zh: '科学依据'},
    lede: {
      en: 'The wrist is the instrument. The app is the page.',
      zh: '手腕是仪器。App 是纸面。',
    },
    sections: [
      {
        heading: {en: 'Twelve signals', zh: '十二种数据'},
        body: {
          en: [
            'Body battery, training load, and sleep run the day. There is no blood pressure. There is no ECG.',
          ],
          zh: ['身体电量、训练负荷和睡眠管住一天。不测血压。不做心电图。'],
        },
      },
    ],
  },
  {
    handle: 'faq',
    kicker: {en: 'ASKED', zh: '有人问过'},
    title: {en: 'FAQ', zh: '常见问题'},
    lede: {
      en: 'The short answers. The band, the price, and this test shop.',
      zh: '短答案。手环、价格，以及这家测试店。',
    },
    sections: [
      {
        heading: {en: 'How much is HOOP?', zh: 'HOOP 多少钱？'},
        body: {
          en: ['$99 once. Black or white. Knit nylon and the sport strap both come in the box. No subscription.'],
          zh: ['$99 一次付清。黑色或白色。编织尼龙和运动表带都在盒里。没有订阅费。'],
        },
      },
      {
        heading: {en: 'Is this checkout real?', zh: '这里的结算是真的吗？'},
        body: {
          en: ['No. You will not be charged. The confirmation page is the end of the path.'],
          zh: ['不是。不会扣款。确认页就是这条路径的终点。'],
        },
      },
    ],
  },
  {
    handle: 'about',
    kicker: {en: 'NEXTBODY', zh: 'NEXTBODY'},
    title: {en: 'About', zh: '关于'},
    lede: {
      en: 'A band with no screen, and an app that says the day plainly.',
      zh: '一条没有屏幕的手环，和一个把一天说清楚的 App。',
    },
    sections: [
      {
        heading: {en: 'Why $99', zh: '为什么是 $99'},
        body: {
          en: ['HOOP is $99 once so the band is not a club.'],
          zh: ['HOOP 只要 $99，一次付清，手环不是会所。'],
        },
      },
    ],
  },
  {
    handle: 'contact',
    kicker: {en: 'WRITE', zh: '写信'},
    title: {en: 'Contact', zh: '联系'},
    lede: {en: 'Shop, press, and privacy.', zh: '商店、媒体和隐私。'},
    sections: [
      {
        heading: {en: 'Addresses', zh: '邮箱'},
        body: {
          en: ['Shop: shop@nextbody.ai · Privacy: privacy@nextbody.ai · Press: press@nextbody.ai'],
          zh: ['商店：shop@nextbody.ai · 隐私：privacy@nextbody.ai · 媒体：press@nextbody.ai'],
        },
      },
    ],
  },
];

bootShop();
