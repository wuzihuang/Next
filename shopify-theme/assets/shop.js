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
      '</a><a href="' +
      shopLink('/collections/all', 'page=user-agreement') +
      '">' +
      copy.footer.agreement +
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
    agreement: 'User Agreement',
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
    agreement: '用户协议',
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
    "handle": "privacy-policy",
    "kicker": {
      "en": "LEGAL",
      "zh": "法律"
    },
    "title": {
      "en": "Privacy Policy",
      "zh": "隐私政策"
    },
    "lede": {
      "en": "How the shop, the app and the band handle what they learn about you — collected, used, kept, deleted. Updated 2026-09-08.",
      "zh": "商店、App 和手环怎么对待它们知道的关于你的一切 —— 收集、使用、保留、删除。 更新于 2026-09-08。"
    },
    "sections": [
      {
        "heading": {
          "en": "Who we are",
          "zh": "我们是谁"
        },
        "body": {
          "en": [
            "NextBody makes the HOOP band and the NextBody app, and runs this shop at nextbody.ai. This policy covers the website, the shop, the account you open here, and the health data the app keeps for you.",
            "It is written to be read once, in full, without a lawyer. Where a term has a legal meaning we say the plain thing next to it.",
            "Questions about anything on this page go to privacy@nextbody.ai."
          ],
          "zh": [
            "NextBody 做 HOOP 手环和 NextBody App，并运营 nextbody.ai 上的商店。本政策覆盖网站、商店、你在这里创建的账户，以及 App 为你保存的健康数据。",
            "它写成一次就能读完的样子，不需要律师在旁边。凡是有法律含义的词，我们都在旁边说一遍人话。",
            "本页任何问题请写 privacy@nextbody.ai。"
          ]
        }
      },
      {
        "heading": {
          "en": "What we collect",
          "zh": "我们收集什么"
        },
        "body": {
          "en": [
            "Account: the email address you sign in with, a hashed password, and the display name you choose. We never store a readable password.",
            "Orders: name, email, shipping address, the items you bought, and the last four digits of the card. The full card number goes to the payment processor and never touches our servers.",
            "Health data from HOOP: heart rate, heart rate variability, stress, skin temperature, blood oxygen at night, sleep stages, steps, distance, active energy, training load, body battery, and the body composition scans you start yourself. Plus the meals, weights, and notes you type in.",
            "Technical: IP address, browser or app version, and timestamps, kept so we can find abuse and fix crashes.",
            "Support: whatever you write to us, and our reply."
          ],
          "zh": [
            "账户：你登录用的邮箱、经过哈希的密码，以及你自己填的显示名。我们不会保存可读的明文密码。",
            "订单：姓名、邮箱、收货地址、买了什么，以及卡号后四位。完整卡号交给支付机构，不进我们的服务器。",
            "HOOP 的健康数据：心率、心率变异性、压力、皮肤温度、夜间血氧、睡眠分期、步数、距离、活动能量、训练负荷、身体电量，以及你自己发起的身体成分扫描。还有你自己输入的饮食、体重和备注。",
            "技术信息：IP 地址、浏览器或 App 版本、时间戳。留着是为了发现滥用和修崩溃。",
            "支持：你写给我们的内容，以及我们的回复。"
          ]
        }
      },
      {
        "heading": {
          "en": "What we do with it",
          "zh": "我们拿它做什么"
        },
        "body": {
          "en": [
            "Health data is used to compute your day — the battery, the load, the night, the plan — and to answer you when you ask the coach. That is the product. It is not used for advertising, and it is not sold. It has no price.",
            "Order and account data is used to take the order, ship it, answer support, and keep the books.",
            "Technical data is used for security and reliability. Aggregate counts — how many people opened the app, how often a screen crashed — never carry your name or your readings."
          ],
          "zh": [
            "健康数据用来算出你的一天 —— 电量、负荷、夜晚、计划 —— 以及在你问教练时回答你。这就是产品本身。它不用于广告，也不出售。它没有标价。",
            "订单和账户数据用于接单、发货、回复支持和记账。",
            "技术数据用于安全和稳定。汇总数字 —— 多少人打开过 App、某个页面崩了多少次 —— 不带你的名字，也不带你的读数。"
          ]
        }
      },
      {
        "heading": {
          "en": "The coach and the model",
          "zh": "教练与模型"
        },
        "body": {
          "en": [
            "When you ask the coach a question, the question and the readings it needs for that answer are sent to the model that writes the reply. It reads before it speaks — the night, the HRV, the load, the meals — and it cites what it read.",
            "The model provider processes that text to produce your answer and for nothing else. Your readings are not used to train a third-party model.",
            "If you never open the coach, nothing goes to a model."
          ],
          "zh": [
            "你向教练提问时，问题以及回答这条问题所需的读数会发给写回复的模型。它先读再说 —— 昨晚、HRV、负荷、饮食 —— 并且会说明自己读了什么。",
            "模型服务方只为生成这条回答而处理这些文本，不做别的。你的读数不会被拿去训练第三方模型。",
            "你从不打开教练，就没有任何东西发给模型。"
          ]
        }
      },
      {
        "heading": {
          "en": "Cookies",
          "zh": "Cookie"
        },
        "body": {
          "en": [
            "The shop sets one httpOnly session cookie. It holds your cart, your language, your signed-in state, and your test orders. It stays on this site and expires when the session does.",
            "There are no advertising pixels and no third-party trackers on this storefront. Nothing here follows you to another site."
          ],
          "zh": [
            "商店只设一个 httpOnly 会话 cookie，里面装购物车、语言、登录状态和测试订单。它只属于本站，会话结束即过期。",
            "本店没有广告像素，没有第三方追踪器。这里的任何东西都不会跟着你去别的网站。"
          ]
        }
      },
      {
        "heading": {
          "en": "Why we are allowed to",
          "zh": "处理的依据"
        },
        "body": {
          "en": [
            "To take an order and run your account, we process what the contract with you needs.",
            "For health data we rely on your explicit consent, given when you pair a band and turned off when you unpair or delete. Consent you can take back is the only kind worth having.",
            "For security logs and fraud checks we rely on our legitimate interest in keeping the service standing. For tax and accounting records, on the law that requires them."
          ],
          "zh": [
            "为了接单和运行你的账户，我们处理履行合同所必需的信息。",
            "健康数据依据的是你的明示同意 —— 配对手环时给出，解绑或删除时收回。能收回的同意才算同意。",
            "安全日志和风控依据的是我们让服务活着的正当利益。税务和会计记录依据的是法律要求。"
          ]
        }
      },
      {
        "heading": {
          "en": "Who else sees it",
          "zh": "谁还会看到"
        },
        "body": {
          "en": [
            "A short list of processors, each bound by contract to use the data only for the job we hired them for: hosting and database, the model provider behind the coach, the payment processor, the carrier that delivers your parcel, and the mail service that sends receipts.",
            "We do not sell personal information and we do not share it with data brokers. If a law or a court orders disclosure, we comply and tell you unless we are forbidden to.",
            "If the company is ever sold or merged, the data moves under this same policy, and we say so before it happens.",
            "Our servers and processors may sit outside your country. Transfers use the safeguards the law asks for — standard contractual clauses or an adequacy decision."
          ],
          "zh": [
            "很短的一份处理方名单，每一家都受合同约束，只能为我们委托的事使用数据：托管与数据库、教练背后的模型服务方、支付机构、送包裹的承运商，以及发收据的邮件服务。",
            "我们不出售个人信息，也不与数据经纪商共享。若法律或法院要求披露，我们会照办，并在允许的前提下告诉你。",
            "若公司被出售或合并，数据在同一份政策之下转移，并且我们会在此之前说明。",
            "我们的服务器和处理方可能不在你所在的国家。跨境传输采用法律要求的保障措施 —— 标准合同条款或充分性认定。"
          ]
        }
      },
      {
        "heading": {
          "en": "How long we keep it",
          "zh": "保留多久"
        },
        "body": {
          "en": [
            "Health data: until you delete it or close the account. Deleting a day deletes it. Closing the account deletes all of it within 30 days, minus backups, which roll off within 90.",
            "Orders and invoices: as long as tax law requires, which in most places is five to seven years.",
            "Technical logs: 90 days. Support mail: 24 months."
          ],
          "zh": [
            "健康数据：保留到你删除它或注销账户为止。删掉某一天就是删掉。注销账户后 30 天内全部删除；备份除外，备份在 90 天内滚动清除。",
            "订单和发票：保留到税法要求的年限，多数地区是五到七年。",
            "技术日志：90 天。支持邮件：24 个月。"
          ]
        }
      },
      {
        "heading": {
          "en": "What you can ask for",
          "zh": "你可以要求什么"
        },
        "body": {
          "en": [
            "A copy of everything we hold, in a file you can open. A correction. A deletion. An export of your readings. A stop to any processing based on consent.",
            "Write to privacy@nextbody.ai from the address on the account. We answer within 30 days and we do not charge for it.",
            "Depending on where you live, the GDPR, the UK GDPR, the CCPA, or the PIPL gives you these rights by name, plus the right to complain to your own regulator. You do not have to go through us first.",
            "Signing out clears the account from this browser. Clearing site data clears the cart and any test orders on this device."
          ],
          "zh": [
            "一份我们持有的全部数据副本，格式你能打开。更正。删除。导出你的读数。停止任何基于同意的处理。",
            "用账户上的邮箱写信到 privacy@nextbody.ai。我们 30 天内答复，不收费。",
            "按你所在地区，GDPR、英国 GDPR、CCPA 或《个人信息保护法》都会逐条给你这些权利，另外还有向监管机构投诉的权利。你不必先经过我们。",
            "退出登录会清掉这个浏览器里的账户。清除站点数据会清掉本设备上的购物车和测试订单。"
          ]
        }
      },
      {
        "heading": {
          "en": "Under 18",
          "zh": "未满 18 岁"
        },
        "body": {
          "en": [
            "HOOP is for people 18 and over. We do not knowingly collect anything from anyone younger.",
            "If you believe a minor has an account, write to privacy@nextbody.ai and we delete it and its readings."
          ],
          "zh": [
            "HOOP 面向 18 岁及以上人群。我们不会在知情的情况下收集更年幼者的任何信息。",
            "若你认为有未成年人开了账户，请写信到 privacy@nextbody.ai，我们会删除该账户及其读数。"
          ]
        }
      },
      {
        "heading": {
          "en": "When this page changes",
          "zh": "本页变更时"
        },
        "body": {
          "en": [
            "The date at the top is the date of the last change. For anything material — a new kind of data, a new processor, a new purpose — we say so in the app before it takes effect, and where the law asks for fresh consent, we ask again."
          ],
          "zh": [
            "页首的日期就是最后修改日期。凡是实质性变化 —— 新增数据类型、新增处理方、新增用途 —— 我们会在生效前在 App 里说明；法律要求重新取得同意的，我们会再问一次。"
          ]
        }
      }
    ]
  },
  {
    "handle": "user-agreement",
    "kicker": {
      "en": "LEGAL",
      "zh": "法律"
    },
    "title": {
      "en": "User Agreement",
      "zh": "用户协议"
    },
    "lede": {
      "en": "The agreement for the app, the account, and the band on your wrist. Updated 2026-09-08.",
      "zh": "关于 App、账户，以及你手腕上那条手环的协议。 更新于 2026-09-08。"
    },
    "sections": [
      {
        "heading": {
          "en": "What this agreement covers",
          "zh": "这份协议管什么"
        },
        "body": {
          "en": [
            "This is the agreement between you and NextBody for the NextBody app, your account, and the HOOP band once it is paired. Buying on this website is covered by the Terms of Service; how we handle data is covered by the Privacy Policy. The three are meant to be read together.",
            "You accept this agreement when you create an account or open the app. If you do not accept it, do not use the app — and if you already bought a band, the Refund Policy still stands."
          ],
          "zh": [
            "这是你与 NextBody 之间关于 NextBody App、你的账户以及配对后的 HOOP 手环的协议。在本站购买由《服务条款》管；数据怎么处理由《隐私政策》管。三份文件应当合起来读。",
            "你创建账户或打开 App 即接受本协议。不接受就不要使用 App —— 如果你已经买了手环，《退款政策》依然有效。"
          ]
        }
      },
      {
        "heading": {
          "en": "Your account",
          "zh": "你的账户"
        },
        "body": {
          "en": [
            "One account belongs to one person, 18 or over. Keep the sign-in to yourself; anything done from a signed-in session counts as done by you.",
            "Tell us at once if you lose control of the account. We can suspend an account that is being used to attack the service or another person, and we say why when we do."
          ],
          "zh": [
            "一个账户属于一个人，18 岁及以上。登录信息自己保管；从已登录会话做出的一切都算你做的。",
            "账户失控请立刻告诉我们。若某个账户被用来攻击服务或攻击他人，我们会停用它，并在停用时说明原因。"
          ]
        }
      },
      {
        "heading": {
          "en": "Your data stays yours",
          "zh": "数据始终是你的"
        },
        "body": {
          "en": [
            "The readings your body produces belong to you. You give us only the permission the product needs: to store them, to compute your day from them, and to show them back to you across your own devices. Nothing wider.",
            "You can export them at any time and you can delete them at any time. Deleting is not a support ticket you have to argue; it is a button, and it means gone."
          ],
          "zh": [
            "你的身体产生的读数归你。你给我们的授权仅限产品所需：保存它们、由它们算出你的一天、并在你自己的设备之间显示回来。不多一分。",
            "你随时可以导出，随时可以删除。删除不是要去跟客服吵的工单，它是一个按钮，按下就是没了。"
          ]
        }
      },
      {
        "heading": {
          "en": "What the band reads",
          "zh": "手环读什么"
        },
        "body": {
          "en": [
            "HOOP reads twelve signals on the wrist and holds them until the app collects them over Bluetooth. Body battery, training load and sleep run the day; heart, blood oxygen, stress, temperature, calories, steps, distance and active energy sit on the instruments. Body composition is a scan you start yourself.",
            "There is no blood pressure and no ECG. The band has no microphone and no camera, and it does not carry a GPS of its own — location, when a workout uses it, comes from the phone and only while that workout is running."
          ],
          "zh": [
            "HOOP 在手腕上读十二种数据，先存住，等 App 通过蓝牙来取。身体电量、训练负荷和睡眠管住一天；心率、血氧、压力、温度、热量、步数、距离和活动能量在仪表上。身体成分是一次由你发起的扫描。",
            "不测血压，不做心电图。手环没有麦克风、没有摄像头，也没有自己的 GPS —— 训练用到位置时，位置来自手机，而且只在那次训练进行时。"
          ]
        }
      },
      {
        "heading": {
          "en": "The coach can be wrong",
          "zh": "教练会说错"
        },
        "body": {
          "en": [
            "The coach reads your own night, HRV, load and meals before it answers, and it tells you what it read. It is still a model writing sentences. It can be confidently wrong about you.",
            "Treat its plan as a suggestion from something that has seen your numbers, not as an instruction from someone who has examined you. Judgment stays with you.",
            "Some answers are metered. If a daily allowance runs out, the app says so plainly instead of pretending the coach has nothing to say."
          ],
          "zh": [
            "教练在回答前会读你自己的夜晚、HRV、负荷和饮食，并会告诉你它读了什么。它终究是一个在写句子的模型，可能非常笃定地把你说错。",
            "把它的计划当成一个看过你数字的东西给的建议，而不是一个检查过你身体的人下的医嘱。判断权还在你手里。",
            "部分回答有额度。每日额度用完时，App 会直接说明，而不是假装教练没话讲。"
          ]
        }
      },
      {
        "heading": {
          "en": "Not a medical device",
          "zh": "不是医疗器械"
        },
        "body": {
          "en": [
            "HOOP is a wellness product for people 18 and over. It is not a medical device. It does not diagnose, treat, cure or prevent any disease, and it is not built to detect a heart attack, sleep apnoea, or any other condition.",
            "Do not use it to make a medical decision, and do not wait on it in an emergency. Call your local emergency number instead.",
            "If you are pregnant, have a pacemaker or another implanted device, or are under a doctor for a heart or sleep condition, ask that doctor before you use the readings for anything."
          ],
          "zh": [
            "HOOP 是面向 18 岁及以上人群的健康产品，不是医疗器械。它不诊断、不治疗、不治愈、不预防任何疾病，也不是为发现心梗、睡眠呼吸暂停或任何其他病症而设计的。",
            "不要用它做医疗决定，紧急情况下也不要等它。请拨打当地急救电话。",
            "若你怀孕、装有心脏起搏器或其他植入设备，或正因心脏、睡眠问题在医生处就诊，请先问过医生，再决定这些读数怎么用。"
          ]
        }
      },
      {
        "heading": {
          "en": "How you may use it",
          "zh": "你可以怎么用"
        },
        "body": {
          "en": [
            "Use the app and the band for yourself. Do not resell access, scrape the service, hammer the API, or take the firmware apart to run it on something else.",
            "Do not put someone else on your account, and do not use the app to give another person medical or training advice as if it were a professional service."
          ],
          "zh": [
            "App 和手环给你自己用。不要转售访问权、抓取服务、猛刷接口，也不要拆固件把它跑在别的东西上。",
            "不要把别人放进你的账户，也不要拿这个 App 去给别人提供医疗或训练建议，装作那是专业服务。"
          ]
        }
      },
      {
        "heading": {
          "en": "What we owe you",
          "zh": "我们欠你什么"
        },
        "body": {
          "en": [
            "A band that works, and an app that reads it, without a subscription for that core reading. App AI is NextBody Pro. What you bought as the band keeps working if you skip Pro.",
            "The service is offered as it is. Features move, screens change, and a release can carry a bug. We do not promise the app is available every minute, only that we act like people who intend it to be.",
            "Where the law lets us limit liability, our total liability to you is capped at what you paid for the band. Nothing here removes a right your own consumer law gives you."
          ],
          "zh": [
            "一条能用的手环、一个能读它的 App，核心读数不收订阅费。App 里的 AI 是 NextBody Pro。跳过 Pro，你买到的手环仍按今天的方式继续工作。",
            "服务按现状提供。功能会挪、界面会变、某个版本可能带 bug。我们不承诺 App 每分钟都在线，只承诺我们像真心想让它在线的人那样做事。",
            "在法律允许限制责任的范围内，我们对你的全部责任以你为手环支付的金额为上限。本协议不剥夺你所在地消费者法给你的任何权利。"
          ]
        }
      },
      {
        "heading": {
          "en": "Ending it",
          "zh": "结束"
        },
        "body": {
          "en": [
            "You can close the account in the app at any time. We delete the readings within 30 days and keep only what tax or accounting law makes us keep.",
            "We can end this agreement if you break it in a way that harms other people or the service. Unpairing a band does not close the account, and closing an account does not brick a band.",
            "This agreement is governed by the law of the place where NextBody is established, and by any consumer law of your own country that applies to you regardless. Before anyone files anything, write to shop@nextbody.ai — most of it is a misunderstanding that a reply fixes."
          ],
          "zh": [
            "你随时可以在 App 里注销账户。我们会在 30 天内删除读数，只保留税务或会计法律要求保留的部分。",
            "若你以伤害他人或伤害服务的方式违反本协议，我们可以终止协议。解绑手环不等于注销账户；注销账户也不会把手环变砖。",
            "本协议适用 NextBody 设立地的法律，同时适用你所在国家依法必然适用的消费者法。任何人提交任何东西之前，请先写 shop@nextbody.ai —— 多数情况是一次回复就能解开的误会。"
          ]
        }
      }
    ]
  },
  {
    "handle": "terms-of-service",
    "kicker": {
      "en": "LEGAL",
      "zh": "法律"
    },
    "title": {
      "en": "Terms of Service",
      "zh": "服务条款"
    },
    "lede": {
      "en": "The rules for buying on nextbody.ai — orders, price, warranty, and the test checkout. Updated 2026-09-08.",
      "zh": "在 nextbody.ai 购买的规则 —— 订单、价格、保修，以及测试结算。 更新于 2026-09-08。"
    },
    "sections": [
      {
        "heading": {
          "en": "These terms",
          "zh": "这份条款"
        },
        "body": {
          "en": [
            "These terms cover nextbody.ai and this storefront: browsing it, opening a shop account, and ordering. Using the shop means you accept them.",
            "The app, your account inside it, and the readings HOOP takes are covered by the User Agreement. Data is covered by the Privacy Policy."
          ],
          "zh": [
            "本条款覆盖 nextbody.ai 和这个店面：浏览、开通商店账户、下单。使用商店即表示接受。",
            "App、App 里的账户以及 HOOP 采集的读数由《用户协议》覆盖。数据由《隐私政策》覆盖。"
          ]
        }
      },
      {
        "heading": {
          "en": "Who can order",
          "zh": "谁可以下单"
        },
        "body": {
          "en": [
            "You must be 18 or over and able to enter a contract where you live. The address and contact details you give have to be real ones — a parcel cannot be delivered to a placeholder.",
            "We can decline or cancel an order, for example when a listing was wrong, stock ran out, or an order looks like fraud or resale at scale. If we cancel, you are not charged, or you are refunded in full."
          ],
          "zh": [
            "你必须年满 18 岁，并在你所在地具备订立合同的能力。填写的地址和联系方式必须是真实的 —— 包裹送不到一个占位符。",
            "我们可以拒绝或取消订单，例如商品信息出错、库存售罄，或订单看起来是欺诈或大规模转售。若由我们取消，你不会被扣款，或全额退回。"
          ]
        }
      },
      {
        "heading": {
          "en": "The product and the price",
          "zh": "产品与价格"
        },
        "body": {
          "en": [
            "HOOP is $99 once, in black or white. The knit nylon strap and the sport strap are both in the box. The app that reads the band is included. App AI is NextBody Pro at $6 / month.",
            "Prices are in US dollars and exclude any duty or import tax your country charges. Where sales tax or VAT applies, it is shown before you pay.",
            "Photography is photography. Finish and strap colour can differ slightly from a render on your screen.",
            "If a price or a spec is obviously wrong — a typo, a decimal in the wrong place — we can correct it and let you decide again before anything ships."
          ],
          "zh": [
            "HOOP 售价 $99，一次付清，黑色或白色。编织尼龙表带和运动表带都在盒里。读取手环的 App 随手环。App 里的 AI 是 NextBody Pro，每月 $6。",
            "价格以美元计，不含你所在国家征收的关税或进口税。适用销售税或增值税时，会在付款前显示。",
            "照片终归是照片。表面颜色和表带颜色与屏幕上的渲染可能略有差别。",
            "若价格或规格明显写错 —— 打字错误、小数点跑位 —— 我们可以更正，并在发货前让你重新决定。"
          ]
        }
      },
      {
        "heading": {
          "en": "How an order works",
          "zh": "订单怎么成立"
        },
        "body": {
          "en": [
            "Your order is an offer to buy. The confirmation email says we received it. The contract is made when we hand the parcel to the carrier, and the shipping notice is the moment it is made.",
            "Risk passes to you on delivery. Title passes when payment clears."
          ],
          "zh": [
            "你的订单是一份购买要约。确认邮件表示我们收到了。合同在我们把包裹交给承运商时成立，发货通知就是成立的那一刻。",
            "风险自签收时转移给你。所有权在款项结清时转移。"
          ]
        }
      },
      {
        "heading": {
          "en": "This checkout is a test",
          "zh": "本店结算是测试"
        },
        "body": {
          "en": [
            "Right now this storefront runs a closed test checkout. It accepts a card number so you can walk the whole path and see an order, but it does not charge the card, it does not reach a payment processor, and it does not create a shipment.",
            "Until a live checkout is switched on, the pages here are a description of the product, not an offer to sell."
          ],
          "zh": [
            "目前本店运行的是闭环测试结算。它接受卡号，只为让你把整条路径走完并看到订单，但不会扣款、不会到达支付机构，也不会产生发货。",
            "在正式结算打开之前，这里的页面是对产品的描述，不构成销售要约。"
          ]
        }
      },
      {
        "heading": {
          "en": "Health, plainly",
          "zh": "关于健康，把话说明"
        },
        "body": {
          "en": [
            "HOOP is for people 18 and over. It is not a medical device. It does not take an ECG, it does not measure blood pressure, and it does not diagnose, treat or prevent any disease.",
            "Nothing on this site is medical advice. If a number worries you, take it to a clinician, not to the internet."
          ],
          "zh": [
            "HOOP 面向 18 岁及以上人群。它不是医疗器械。不做心电图，不测血压，也不诊断、治疗或预防任何疾病。",
            "本站任何内容都不构成医疗建议。若某个数字让你担心，请拿去问医生，而不是问互联网。"
          ]
        }
      },
      {
        "heading": {
          "en": "Your shop account",
          "zh": "商店账户"
        },
        "body": {
          "en": [
            "The shop account holds your orders and addresses. It is separate from the health account in the app; the shop never sees your readings.",
            "Keep the password to yourself. Tell us if it leaks and we will lock the account."
          ],
          "zh": [
            "商店账户保存你的订单和地址。它与 App 里的健康账户是分开的；商店看不到你的读数。",
            "密码自己保管。若泄露请告诉我们，我们会锁定账户。"
          ]
        }
      },
      {
        "heading": {
          "en": "What you may not do here",
          "zh": "这里不能做的事"
        },
        "body": {
          "en": [
            "Do not scrape the site, script the checkout, probe it for holes without asking us first, or copy the text, photography, or the generated faces for your own product.",
            "Security researchers are welcome. Write to shop@nextbody.ai before you test anything, and we will answer."
          ],
          "zh": [
            "不要抓取本站、脚本刷结算、未经我们同意就扫描漏洞，也不要把这里的文案、摄影或生成的表盘搬进你自己的产品。",
            "欢迎安全研究者。测试之前请先写信到 shop@nextbody.ai，我们会回复。"
          ]
        }
      },
      {
        "heading": {
          "en": "What belongs to whom",
          "zh": "谁拥有什么"
        },
        "body": {
          "en": [
            "The NextBody name, the HOOP name, the industrial design, the software, the copy and the images on this site belong to NextBody or its licensors. Buying a band buys the band and a personal licence to use the software on it.",
            "The readings your body produces belong to you. That is in the User Agreement, and it does not change here."
          ],
          "zh": [
            "NextBody 名称、HOOP 名称、工业设计、软件、本站文案与图片归 NextBody 或其许可方所有。买手环买到的是手环本身，以及在其上使用软件的个人许可。",
            "你的身体产生的读数归你。这一条写在《用户协议》里，在这里不变。"
          ]
        }
      },
      {
        "heading": {
          "en": "Warranty and liability",
          "zh": "保修与责任"
        },
        "body": {
          "en": [
            "A new HOOP carries a 12-month limited warranty against manufacturing defects from the day it is delivered. Straps carry 6 months. Wear, water past the rated depth, drops, and anything opened up are not defects.",
            "To the extent the law allows, we are not liable for indirect or consequential loss, and our total liability for an order is capped at what you paid for it. Nothing here limits liability for death, personal injury caused by our negligence, or fraud, and nothing here takes away the statutory rights your own consumer law gives you."
          ],
          "zh": [
            "全新 HOOP 自签收之日起提供 12 个月制造缺陷有限保修。表带 6 个月。正常磨损、超出防水深度进水、跌落，以及任何被拆开过的情况，都不算缺陷。",
            "在法律允许的范围内，我们不对间接损失或后果性损失负责，对一笔订单的全部责任以你为其支付的金额为上限。本条不限制因我们过失造成的死亡或人身伤害的责任，也不限制欺诈责任，更不剥夺你所在地消费者法赋予的法定权利。"
          ]
        }
      },
      {
        "heading": {
          "en": "Law, disputes, and changes",
          "zh": "法律、争议与变更"
        },
        "body": {
          "en": [
            "These terms are governed by the law of the place where NextBody is established, together with any consumer law of your own country that applies to you regardless.",
            "Before a dispute becomes a filing, write to shop@nextbody.ai. We answer, and most of it ends there.",
            "We can change these terms. The date at the top is the date of the last change, and an order is always governed by the terms in force on the day it was placed."
          ],
          "zh": [
            "本条款适用 NextBody 设立地的法律，同时适用你所在国家依法必然适用的消费者法。",
            "在争议变成诉状之前，请先写信到 shop@nextbody.ai。我们会回复，多数事情就到此为止。",
            "我们可以修改本条款。页首日期是最后修改日期；每一笔订单始终适用下单当日生效的条款。"
          ]
        }
      }
    ]
  },
  {
    "handle": "refund-policy",
    "kicker": {
      "en": "LEGAL",
      "zh": "法律"
    },
    "title": {
      "en": "Refund Policy",
      "zh": "退款政策"
    },
    "lede": {
      "en": "Thirty days to change your mind. Twelve months if it is our fault. Updated 2026-09-08.",
      "zh": "三十天可以反悔。如果是我们的错，十二个月都算。 更新于 2026-09-08。"
    },
    "sections": [
      {
        "heading": {
          "en": "Thirty days",
          "zh": "三十天"
        },
        "body": {
          "en": [
            "You have 30 days from delivery to send a HOOP back for a full refund of the product price. It has to come back complete — band, both straps, charger, box — and in a condition someone could reasonably call unused.",
            "You do not have to explain why. A wrist is a personal thing and a band either suits it or does not."
          ],
          "zh": [
            "自签收起 30 天内，你可以把 HOOP 寄回并全额退回产品款。寄回时要齐全 —— 手环、两条表带、充电器、包装盒 —— 并且状态是一个正常人会称为「未使用」的状态。",
            "不必解释原因。手腕是很私人的东西，一条手环要么合适，要么不合适。"
          ]
        }
      },
      {
        "heading": {
          "en": "How to start one",
          "zh": "怎么发起"
        },
        "body": {
          "en": [
            "Write to shop@nextbody.ai with the order number. We reply with a return number and the address to send it to. Please do not post it back without that number — an unlabelled parcel is very hard to match to a person.",
            "Pack it so it survives the trip. Until it reaches us it is still your parcel, so keep the tracking."
          ],
          "zh": [
            "带上订单号写信到 shop@nextbody.ai。我们会回复一个退货编号和寄回地址。请不要在没有编号的情况下直接寄回 —— 没有标识的包裹很难对上人。",
            "包装要能撑过路上。在寄到我们这里之前，它仍是你的包裹，请保留运单号。"
          ]
        }
      },
      {
        "heading": {
          "en": "Who pays the return",
          "zh": "退货运费谁出"
        },
        "body": {
          "en": [
            "If the band is faulty or we sent the wrong thing, we pay both ways and you are not out of pocket.",
            "If you simply changed your mind, return shipping is yours. Original shipping is refunded only where the law says it must be."
          ],
          "zh": [
            "若手环有缺陷或我们发错了东西，来回运费都由我们承担，你不会自掏腰包。",
            "若只是改变主意，退货运费由你承担。原始运费只在法律要求退回时退回。"
          ]
        }
      },
      {
        "heading": {
          "en": "When the money comes back",
          "zh": "钱什么时候回来"
        },
        "body": {
          "en": [
            "We inspect the return the day it lands and issue the refund within 5 business days of accepting it. It goes back to the original payment method. Your bank usually adds 3 to 10 days of its own.",
            "If a return arrives short of parts or visibly used, we tell you what we found and what we can refund before we do anything."
          ],
          "zh": [
            "退货到达当天我们就会检查，确认后 5 个工作日内退款，原路退回。银行通常还要再加 3 到 10 天。",
            "若退回的东西缺件或明显使用过，我们会先告诉你我们看到了什么、能退多少，然后再动作。"
          ]
        }
      },
      {
        "heading": {
          "en": "Faulty units",
          "zh": "设备有问题"
        },
        "body": {
          "en": [
            "A manufacturing defect inside 12 months gets a repair, a replacement, or a refund — our choice first, yours if the first attempt does not fix it. Straps carry 6 months.",
            "Send a photo or a short video with the first email if you can. It usually saves a whole round trip."
          ],
          "zh": [
            "12 个月内出现制造缺陷，可以维修、更换或退款 —— 第一次由我们选择，若第一次没有解决，则由你选择。表带保 6 个月。",
            "第一封邮件里尽量附一张照片或一段短视频，通常能省下一整趟来回。"
          ]
        }
      },
      {
        "heading": {
          "en": "What we cannot take back",
          "zh": "不能退的情况"
        },
        "body": {
          "en": [
            "Straps that have been worn, unless they are faulty. Anything damaged by a drop, by water past the rated depth, or by being opened. Bands bought from someone who is not us. Anything outside the 30 days, unless it is a warranty claim."
          ],
          "zh": [
            "戴过的表带，除非有缺陷。因跌落、超出防水深度进水或被拆开而损坏的物品。从非我方渠道购买的手环。超过 30 天的退货请求，除非属于保修。"
          ]
        }
      },
      {
        "heading": {
          "en": "Cancelling before it ships",
          "zh": "发货前取消"
        },
        "body": {
          "en": [
            "Write within a few hours of ordering and we can usually stop it, change the address, or swap the colour. Once the label is printed the parcel has to travel, and it becomes a return.",
            "In the EU and the UK you also have a statutory 14-day right to withdraw, which runs alongside the 30 days above and is never shortened by it."
          ],
          "zh": [
            "下单后几小时内写信，我们通常还能拦下来、改地址或换颜色。运单一旦打印，包裹就得走完这一趟，然后按退货处理。",
            "在欧盟和英国，你另有法定的 14 天撤回权，与上面的 30 天并行，且绝不会被它缩短。"
          ]
        }
      },
      {
        "heading": {
          "en": "On this test shop",
          "zh": "在本测试店"
        },
        "body": {
          "en": [
            "Orders placed here are test orders. No payment is taken, so there is nothing to refund and no parcel to send back. The confirmation page is the end of the path."
          ],
          "zh": [
            "这里下的都是测试订单。没有扣款，因此没有可退的钱，也没有要寄回的包裹。确认页就是这条路径的终点。"
          ]
        }
      }
    ]
  },
  {
    "handle": "shipping-policy",
    "kicker": {
      "en": "LEGAL",
      "zh": "法律"
    },
    "title": {
      "en": "Shipping Policy",
      "zh": "配送政策"
    },
    "lede": {
      "en": "Where it goes, what it costs, how long it takes, and what happens when it goes wrong. Updated 2026-09-08.",
      "zh": "送到哪里、多少钱、多久到，以及出问题时怎么办。 更新于 2026-09-08。"
    },
    "sections": [
      {
        "heading": {
          "en": "Where we send it",
          "zh": "送到哪里"
        },
        "body": {
          "en": [
            "The live shop ships to the United States, Canada, the United Kingdom, the European Union, Switzerland, Norway, Australia, New Zealand, Japan, Korea, Singapore, Hong Kong, Taiwan and mainland China.",
            "Other destinations open as the customs paperwork is ready. If yours is not on the list, write to shop@nextbody.ai and we will say when."
          ],
          "zh": [
            "正式商店发往美国、加拿大、英国、欧盟、瑞士、挪威、澳大利亚、新西兰、日本、韩国、新加坡、中国香港、中国台湾和中国大陆。",
            "其他地区会在清关文件齐备后开放。若名单里没有你那边，请写 shop@nextbody.ai，我们会告诉你时间。"
          ]
        }
      },
      {
        "heading": {
          "en": "What it costs",
          "zh": "运费"
        },
        "body": {
          "en": [
            "Shipping is $8 on a strap-only cart. A cart of $99 or more — a single HOOP counts — ships free.",
            "Shipping is quoted before you pay. There is no handling fee bolted on at the end."
          ],
          "zh": [
            "只买表带时运费 $8。满 $99 免运费 —— 单独买一条 HOOP 就够。",
            "运费在付款前就报出来。最后不会再加什么手续费。"
          ]
        }
      },
      {
        "heading": {
          "en": "How long it takes",
          "zh": "要多久"
        },
        "body": {
          "en": [
            "Orders leave the warehouse in 2 to 4 business days. Transit is usually 3 to 5 days in the United States and 5 to 10 days everywhere else.",
            "We do not ship on weekends or local public holidays, and a launch week can add a day or two. If an order will be late, we write to you before you have to ask."
          ],
          "zh": [
            "订单在 2 到 4 个工作日内出库。在途通常美国境内 3 到 5 天，其他地区 5 到 10 天。",
            "周末和当地公共假日不发货，发售周可能再多一两天。若订单会延误，我们会在你开口问之前先写信告诉你。"
          ]
        }
      },
      {
        "heading": {
          "en": "Tracking",
          "zh": "追踪"
        },
        "body": {
          "en": [
            "A tracking number reaches you by email the moment the label is scanned. It can sit quiet for a day before the carrier updates it; that is the carrier, not the parcel.",
            "The same number is on the order page in your account."
          ],
          "zh": [
            "运单一被扫描，运单号就会发到你的邮箱。它可能有一天没有更新，那是承运商的节奏，不是包裹出了事。",
            "同一个单号也在你账户的订单页上。"
          ]
        }
      },
      {
        "heading": {
          "en": "Duty and tax",
          "zh": "关税和税费"
        },
        "body": {
          "en": [
            "Inside the United States, tax is calculated at checkout. Elsewhere, import duty and VAT are set by your own country and are yours to pay, unless the checkout collected them up front and said so.",
            "A parcel refused at customs comes back to us, and we refund the product price minus the shipping both ways."
          ],
          "zh": [
            "美国境内的税在结算时计算。其他地区的进口关税和增值税由你所在国家决定，由你承担，除非结算时已经代收并明确说明。",
            "在海关被拒收的包裹会退回我们，我们退还产品款，扣除来回运费。"
          ]
        }
      },
      {
        "heading": {
          "en": "Wrong address, lost, or damaged",
          "zh": "地址错、丢件、破损"
        },
        "body": {
          "en": [
            "Check the address on the confirmation email. We can change it before the label prints; after that it has to be redirected with the carrier, and some carriers charge for that.",
            "Tell us within 7 days if a parcel arrives damaged — a photo of the box helps. Tell us if tracking has not moved for 10 days and we open a case with the carrier; if it is genuinely lost we send another one."
          ],
          "zh": [
            "请核对确认邮件上的地址。运单打印前我们可以改；之后只能通过承运商改派，有些承运商会收费。",
            "包裹到达时若有破损，请在 7 天内告诉我们 —— 拍一张外箱照片会很有帮助。若运单 10 天没有更新，也请告诉我们，我们会向承运商开案；确认丢件的，我们再发一件。"
          ]
        }
      },
      {
        "heading": {
          "en": "On this test shop",
          "zh": "在本测试店"
        },
        "body": {
          "en": [
            "You can enter any supported country and see the rate and the total. Nothing is picked, packed or posted, and no carrier is ever contacted."
          ],
          "zh": [
            "你可以填任意受支持的国家或地区，看到运费和总价。但不会有人拣货、打包、投递，也不会联系任何承运商。"
          ]
        }
      }
    ]
  },
  {
    "handle": "science",
    "kicker": {
      "en": "WHAT IT READS",
      "zh": "它读什么"
    },
    "title": {
      "en": "Science",
      "zh": "科学依据"
    },
    "lede": {
      "en": "The wrist is the instrument. The app is the page. HOOP keeps twelve signals. It does not run other apps.",
      "zh": "手腕是仪器。App 是纸面。HOOP 读十二种数据。它不跑别的 App。"
    },
    "sections": [
      {
        "heading": {
          "en": "Twelve signals",
          "zh": "十二种数据"
        },
        "body": {
          "en": [
            "Body battery, training load, and sleep run the day. Heart, blood oxygen, stress, temperature, calories, steps, distance, and active energy sit on the instruments. Composition is a scan you start yourself.",
            "Night HRV lives on Sleep. There is no blood pressure. There is no ECG."
          ],
          "zh": [
            "身体电量、训练负荷和睡眠管住一天。心率、血氧、压力、温度、热量、步数、距离和活动能量在仪表上。身体成分是一次由你发起的扫描。",
            "夜间 HRV 归在睡眠里。不测血压。不做心电图。"
          ]
        }
      },
      {
        "heading": {
          "en": "How the wrist reads",
          "zh": "手腕怎么读"
        },
        "body": {
          "en": [
            "Green light for pulse, infrared and red for oxygen at night, a skin thermometer against the wrist, and a motion sensor that tells a step from a shrug. Nothing is inferred from a phone in a pocket.",
            "The band samples all day and holds the readings until the phone comes near. Bluetooth carries them across; the numbers do not go through anyone else on the way."
          ],
          "zh": [
            "绿光测脉搏，红光与红外在夜里测血氧，一枚贴着手腕的皮温传感器，以及一颗能把走一步和耸一下肩分开的运动传感器。没有一样是靠口袋里的手机猜出来的。",
            "手环整天采样，先存住，等手机靠近再交出去。蓝牙负责搬运；这一路上没有第三方碰到这些数字。"
          ]
        }
      },
      {
        "heading": {
          "en": "What the numbers are for",
          "zh": "这些数字用来做什么"
        },
        "body": {
          "en": [
            "Body battery is a budget: what the night put in, what the day has taken out. Training load is what you already spent. Sleep is the night scored on its own terms, not against a stranger.",
            "Each of them is compared to your own baseline. Two weeks of wear is what it takes before the app stops hedging and starts saying things plainly."
          ],
          "zh": [
            "身体电量是一本预算：夜里存进多少，白天花掉多少。训练负荷是你已经花掉的部分。睡眠按它自己的标准打分，不拿陌生人来比。",
            "每一项都只跟你自己的基线比。戴满两周，App 才会停止打太极，开始把话说直。"
          ]
        }
      },
      {
        "heading": {
          "en": "What it is not",
          "zh": "它不是什么"
        },
        "body": {
          "en": [
            "HOOP is not a medical device. It does not diagnose. It is for people 18 and over.",
            "The numbers are for managing a body you already know — when to train, how much to eat, whether last night was enough."
          ],
          "zh": [
            "HOOP 不是医疗器械。它不做诊断。面向 18 岁及以上。",
            "这些数字是为了管你已经认识的那副身体 — 什么时候练、吃多少、昨晚够不够。"
          ]
        }
      }
    ]
  },
  {
    "handle": "faq",
    "kicker": {
      "en": "ASKED",
      "zh": "有人问过"
    },
    "title": {
      "en": "FAQ",
      "zh": "常见问题"
    },
    "lede": {
      "en": "The short answers — the band, the app, the money, and this test shop. If yours is not here, write to shop@nextbody.ai.",
      "zh": "短答案 —— 手环、App、钱，以及这家测试店。没有你要问的，就写 shop@nextbody.ai。"
    },
    "sections": [
      {
        "heading": {
          "en": "How much is HOOP?",
          "zh": "HOOP 多少钱？"
        },
        "body": {
          "en": [
            "$99 once. Black or white. The knit nylon strap and the sport strap are both in the box, along with the charger.",
            "The app that reads the band comes with the band. App AI is NextBody Pro: one free month if this health account has not claimed it, then $6 / month."
          ],
          "zh": [
            "$99 一次付清。黑色或白色。编织尼龙表带和运动表带都在盒里，充电器也在。",
            "读取手环的 App 随手环。App 里的 AI 是 NextBody Pro：这个健康账号还没领过则首月免费，之后每月 $6。"
          ]
        }
      },
      {
        "heading": {
          "en": "Does it have a screen?",
          "zh": "有屏幕吗？"
        },
        "body": {
          "en": [
            "No. The wrist stays quiet — no glass, no glow, nothing to check in a meeting.",
            "You read the day in NextBody: on the phone, on the lock screen, on the widget. The face you see there is generated for that day, not picked from a list."
          ],
          "zh": [
            "没有。手腕保持安静 —— 没有玻璃，没有发光，开会时没有东西要瞄。",
            "你在 NextBody 里读这一天：手机上、锁屏上、小组件上。你看到的那张面孔是为那一天生成的，不是从列表里挑的。"
          ]
        }
      },
      {
        "heading": {
          "en": "How long does the battery last?",
          "zh": "续航多久？"
        },
        "body": {
          "en": [
            "About 5 days of ordinary wear, including sleep tracking every night. Heavy workout tracking pulls it down to 3 or 4.",
            "A full charge takes about 90 minutes on the magnetic puck. The app tells you the band is low before the band is low."
          ],
          "zh": [
            "正常佩戴约 5 天，包含每晚睡眠监测。大量训练记录会降到 3 到 4 天。",
            "磁吸充电座充满约 90 分钟。手环快没电之前，App 会先提醒你。"
          ]
        }
      },
      {
        "heading": {
          "en": "Can I swim with it?",
          "zh": "可以游泳吗？"
        },
        "body": {
          "en": [
            "Yes. Swim in it, shower in it, keep it on. It is rated 5 ATM, which covers pools, showers and open water.",
            "It is not for scuba or high-speed water sports. Rinse the sport strap with fresh water after the sea."
          ],
          "zh": [
            "可以。游泳戴，洗澡戴，一直戴着。防水等级 5 ATM，泳池、淋浴、开放水域都覆盖。",
            "不适合潜水和高速水上运动。下过海之后用清水冲一冲运动表带。"
          ]
        }
      },
      {
        "heading": {
          "en": "Will it fit my wrist?",
          "zh": "我的手腕戴得上吗？"
        },
        "body": {
          "en": [
            "One size, two straps. The knit nylon is elastic and fits roughly 135–210 mm; the sport strap is a pin buckle over the same range.",
            "Wear it a finger-width above the wrist bone, snug enough that it does not slide when you shake your arm. Optical readings live or die on that."
          ],
          "zh": [
            "单一尺寸，两条表带。编织尼龙有弹性，大致适配 135–210 mm；运动表带是同一区间的针扣。",
            "戴在腕骨上方一指宽处，紧到甩手臂时不会滑动。光学读数的成败全在这一点上。"
          ]
        }
      },
      {
        "heading": {
          "en": "iPhone or Android?",
          "zh": "iPhone 还是安卓？"
        },
        "body": {
          "en": [
            "The NextBody app ships on iPhone first, iOS 17 and later. The Android build follows.",
            "The band stores its readings on its own, so a day without the phone is not a lost day."
          ],
          "zh": [
            "NextBody App 先上 iPhone，iOS 17 及以上。安卓版随后。",
            "手环自己会存读数，所以有一天没带手机，那一天也不会丢。"
          ]
        }
      },
      {
        "heading": {
          "en": "How accurate is it?",
          "zh": "准不准？"
        },
        "body": {
          "en": [
            "Good enough to run your week, not good enough to run a clinic. Resting heart rate, sleep timing and step count are solid. Continuous heart rate during heavy lifting is the hardest case for any optical sensor, including this one.",
            "Body composition is an estimate from impedance and your own history. Weigh and scan at the same time of day and read the trend, not the decimal."
          ],
          "zh": [
            "足以管好你的一周，不足以支撑一间诊所。静息心率、入睡时间和步数很稳。大重量训练时的连续心率是所有光学传感器最难的场景，这一颗也一样。",
            "身体成分是由阻抗和你自己的历史推出的估计值。固定时间称重和扫描，看趋势，不要盯小数点。"
          ]
        }
      },
      {
        "heading": {
          "en": "What does the coach actually see?",
          "zh": "AI 教练到底看到什么？"
        },
        "body": {
          "en": [
            "Your night, your HRV, your training load, your meals and your battery — the same numbers you can open yourself. It says what it read before it says what it thinks.",
            "It is a model. It can be confidently wrong. It is not a doctor and it does not pretend to be one."
          ],
          "zh": [
            "你的夜晚、你的 HRV、你的训练负荷、你的饮食和你的电量 —— 就是你自己能打开的那些数字。它先说读到了什么，再说它怎么想。",
            "它是模型，可能非常笃定地说错。它不是医生，也不假装是。"
          ]
        }
      },
      {
        "heading": {
          "en": "Who owns my data?",
          "zh": "数据归谁？"
        },
        "body": {
          "en": [
            "You do. Export it whenever you want, delete it whenever you want, and closing the account deletes the lot within 30 days.",
            "It is never sold and never used for advertising. The Privacy Policy says exactly who touches it and for how long."
          ],
          "zh": [
            "归你。随时导出，随时删除；注销账户会在 30 天内删光。",
            "永不出售，永不用于广告。《隐私政策》里写明了谁会碰到它、碰多久。"
          ]
        }
      },
      {
        "heading": {
          "en": "Does it track my location?",
          "zh": "它会记录我的位置吗？"
        },
        "body": {
          "en": [
            "The band has no GPS of its own. If a workout needs a route, it comes from the phone, and only while that workout is running.",
            "There is no microphone and no camera on the band."
          ],
          "zh": [
            "手环没有自己的 GPS。若某次训练需要轨迹，轨迹来自手机，而且只在那次训练进行时。",
            "手环上没有麦克风，也没有摄像头。"
          ]
        }
      },
      {
        "heading": {
          "en": "What is the warranty?",
          "zh": "保修多久？"
        },
        "body": {
          "en": [
            "Twelve months on the band against manufacturing defects, six on the straps, counted from delivery. A defect gets a repair, a replacement, or your money back.",
            "You also have 30 days from delivery to send an unused band back for any reason at all."
          ],
          "zh": [
            "手环制造缺陷保修 12 个月，表带 6 个月，自签收起算。出现缺陷可维修、更换或退款。",
            "另外，自签收起 30 天内，未使用的手环可以无理由退回。"
          ]
        }
      },
      {
        "heading": {
          "en": "When does it ship?",
          "zh": "什么时候发货？"
        },
        "body": {
          "en": [
            "Live orders leave in 2 to 4 business days and land in 3 to 5 inside the United States, 5 to 10 elsewhere. Straps ship for $8; a cart of $99 or more ships free."
          ],
          "zh": [
            "正式订单 2 到 4 个工作日出库，美国境内 3 到 5 天送达，其他地区 5 到 10 天。表带运费 $8；满 $99 免运费。"
          ]
        }
      },
      {
        "heading": {
          "en": "Is this checkout real?",
          "zh": "这里的结算是真的吗？"
        },
        "body": {
          "en": [
            "No. This storefront closes the path with a test card so you can add to cart, pay, and see an order. You will not be charged, and nothing ships.",
            "When the live checkout opens, the prices on these pages are the prices."
          ],
          "zh": [
            "不是。本店用测试卡把路径走完，让你能加购、付款并看到订单。不会扣款，也不会发货。",
            "正式结算打开时，这些页面上的价格就是价格。"
          ]
        }
      }
    ]
  },
  {
    "handle": "about",
    "kicker": {
      "en": "NEXTBODY",
      "zh": "NEXTBODY"
    },
    "title": {
      "en": "About",
      "zh": "关于"
    },
    "lede": {
      "en": "A band with no screen, and an app that says the day plainly. Built so more people can actually manage a body.",
      "zh": "一条没有屏幕的手环，和一个把一天说清楚的 App。为了让更多人真的管得起自己的身体。"
    },
    "sections": [
      {
        "heading": {
          "en": "What we make",
          "zh": "我们做什么"
        },
        "body": {
          "en": [
            "HOOP is a steel band with no display. It reads twelve signals on the wrist all day and all night and hands them to the NextBody app, which turns them into three numbers that run the day: what you have left, what you already spent, and what the day still wants to eat.",
            "Everything else — the instruments, the night, the plan, the coach — sits one layer down, there when you want the why."
          ],
          "zh": [
            "HOOP 是一条没有显示屏的钢制手环。它整日整夜在手腕上读十二种数据，交给 NextBody App，由 App 变成管住一天的三个数：你还剩多少、已经花了多少、今天还该吃多少。",
            "其余的一切 —— 仪表、夜晚、计划、教练 —— 都在下一层，你想知道为什么时它就在。"
          ]
        }
      },
      {
        "heading": {
          "en": "Why no screen",
          "zh": "为什么不要屏幕"
        },
        "body": {
          "en": [
            "A watch asks you to look. Two hundred times a day, for a number that has not moved. That is the part of wearables nobody enjoys and everybody accepts.",
            "Taking the glass off the arm bought us three things: five days on a charge, a case thin enough to sleep in, and a wrist that does not interrupt you. The reading waits in the app, where there is room to say a whole sentence instead of a digit."
          ],
          "zh": [
            "表要求你看。一天两百次，看一个根本没动的数字。这是可穿戴里没人享受、人人接受的那部分。",
            "把玻璃从手臂上拿掉，换来三件事：五天续航、薄到能戴着睡的机身，以及一只不打断你的手腕。读数在 App 里等你，那里有地方说完整一句话，而不是只显示一个数字。"
          ]
        }
      },
      {
        "heading": {
          "en": "Why $99",
          "zh": "为什么是 $99"
        },
        "body": {
          "en": [
            "Memberships in this category start at $239 a year. Pay for two years and you have bought the hardware three times over — and if you stop paying, your own nights stop being readable.",
            "HOOP is $99 once so the band is not a club. Your data is not a hostage, and the core reading has no meter on it.",
            "The next version of you is already under the skin. HOOP just makes it visible."
          ],
          "zh": [
            "同类产品的会员费一年从 $239 起。付两年，等于把硬件买了三遍 —— 而一旦停付，连你自己的夜晚都读不了了。",
            "HOOP 只要 $99，一次付清，手环不是会所。你的数据不是人质，核心读数上没有计价器。",
            "下一个版本的你，已经在皮肤底下了。HOOP 只是让它被看见。"
          ]
        }
      },
      {
        "heading": {
          "en": "How we work",
          "zh": "我们怎么做事"
        },
        "body": {
          "en": [
            "Small team, one product, no roadmap written for a stage. We wear the thing every day, and the day a number lies to us we fix the number before we ship anything new.",
            "We do not run ads on your body. We do not sell readings. When we do not know something — and an optical sensor on a wrist leaves plenty unknown — the app says so instead of inventing a score."
          ],
          "zh": [
            "小团队，一个产品，没有为发布会写的路线图。我们自己每天戴着；哪天某个数字对我们说了谎，我们先修那个数字，再谈新功能。",
            "我们不在你的身体上投广告，不出售读数。遇到我们不知道的事 —— 手腕上的光学传感器留下的未知不少 —— App 会直说，而不是编一个分数出来。"
          ]
        }
      },
      {
        "heading": {
          "en": "What it is not",
          "zh": "它不是什么"
        },
        "body": {
          "en": [
            "Not a medical device, not a diagnosis, not a doctor. No ECG, no blood pressure, no promise about a condition. For people 18 and over.",
            "It is an instrument for managing a body you already live in."
          ],
          "zh": [
            "不是医疗器械，不是诊断，不是医生。不做心电图，不测血压，不对任何病症做承诺。面向 18 岁及以上人群。",
            "它是一件仪器，用来管理你已经住在里面的那副身体。"
          ]
        }
      },
      {
        "heading": {
          "en": "Where this shop stands",
          "zh": "这家店现在的状态"
        },
        "body": {
          "en": [
            "This storefront is a working test: real pages, real cart, real order path, a closed test checkout at the end. Nothing is charged and nothing ships yet.",
            "Write to shop@nextbody.ai if you want to know when it opens for real."
          ],
          "zh": [
            "这个店面是一次可运行的测试：真实的页面、真实的购物车、真实的下单路径，末端是闭环测试结算。不扣款，暂不发货。",
            "想知道什么时候正式开卖，写 shop@nextbody.ai。"
          ]
        }
      }
    ]
  },
  {
    "handle": "contact",
    "kicker": {
      "en": "WRITE",
      "zh": "写信"
    },
    "title": {
      "en": "Contact",
      "zh": "联系"
    },
    "lede": {
      "en": "Four addresses and a person behind each one. We read what you send.",
      "zh": "四个邮箱，每个后面都有一个人。我们会读你寄来的信。"
    },
    "sections": [
      {
        "heading": {
          "en": "Shop and orders",
          "zh": "商店与订单"
        },
        "body": {
          "en": [
            "shop@nextbody.ai — orders, returns, warranty, shipping, and anything about the band itself.",
            "Put the order number in the subject line if you have one. We answer within one business day, Monday to Friday."
          ],
          "zh": [
            "shop@nextbody.ai —— 订单、退货、保修、配送，以及关于手环本身的一切。",
            "有订单号就写在主题里。周一至周五，一个工作日内回复。"
          ]
        }
      },
      {
        "heading": {
          "en": "Privacy and your data",
          "zh": "隐私与你的数据"
        },
        "body": {
          "en": [
            "privacy@nextbody.ai — a copy of your data, a correction, a deletion, or a question about the Privacy Policy.",
            "Write from the address on the account so we know it is you. We answer within 30 days and usually much sooner, and we never charge for it."
          ],
          "zh": [
            "privacy@nextbody.ai —— 索取数据副本、更正、删除，或关于《隐私政策》的任何问题。",
            "请用账户上的邮箱写信，我们才能确认是你。30 天内答复，通常快得多，且从不收费。"
          ]
        }
      },
      {
        "heading": {
          "en": "Press",
          "zh": "媒体"
        },
        "body": {
          "en": [
            "press@nextbody.ai — product photography, specs, review units, and interviews.",
            "Say your outlet and your deadline in the first line and we will match it if we can."
          ],
          "zh": [
            "press@nextbody.ai —— 产品图、参数、评测机与采访。",
            "第一行写清媒体名和截稿时间，能配合的我们都会配合。"
          ]
        }
      },
      {
        "heading": {
          "en": "Security",
          "zh": "安全"
        },
        "body": {
          "en": [
            "security@nextbody.ai — if you have found a hole, tell us before you tell anyone else and give us a way to reach you.",
            "We will not send lawyers after good-faith research."
          ],
          "zh": [
            "security@nextbody.ai —— 若你发现了漏洞，请先告诉我们，再告诉别人，并留下能联系到你的方式。",
            "我们不会对善意研究发律师函。"
          ]
        }
      },
      {
        "heading": {
          "en": "A few honest notes",
          "zh": "几句实话"
        },
        "body": {
          "en": [
            "There is no phone line yet, and this test shop does not open a ticket from a form. Email is the whole support system, and it is read by the people who build the thing.",
            "Returns go to the address we send you with a return number — please do not post anything back before you have one."
          ],
          "zh": [
            "目前没有电话，本测试店也不会从表单生成工单。邮件就是全部的支持系统，而读信的人就是做这东西的人。",
            "退货请寄到我们随退货编号一起给你的地址 —— 拿到编号之前请不要寄出。"
          ]
        }
      }
    ]
  }
];

bootShop();
