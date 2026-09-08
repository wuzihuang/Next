// Generated from shopify-web/app/lib/cartPricing.js. Run npm run build:shop-core.
(function () {
const exports = {};
"use strict";
/** Shared test-store cart rules. The Liquid asset is generated from this file. */
Object.defineProperty(exports, "__esModule", { value: true });
exports.TEST_DISCOUNT_CODE = void 0;
exports.canonicalVariantId = canonicalVariantId;
exports.clampQuantity = clampQuantity;
exports.normalizeDiscountCode = normalizeDiscountCode;
exports.isKnownDiscount = isKnownDiscount;
exports.emptyCart = emptyCart;
exports.addLine = addLine;
exports.updateLine = updateLine;
exports.removeLine = removeLine;
exports.setDiscount = setDiscount;
exports.resolveVariant = resolveVariant;
exports.quoteCart = quoteCart;
exports.formatMoney = formatMoney;
/** @typedef {{variantId: string, quantity: number}} CartLineInput */
/** @typedef {{lines: CartLineInput[], discountCode?: string}} CartState */
/** @typedef {{id: string}} PriceVariant */
/** @typedef {{handle: string, price: number, variants: PriceVariant[]}} PriceProduct */
exports.TEST_DISCOUNT_CODE = 'TEST10';
const SHIPPING_THRESHOLD_CENTS = 9900;
const SHIPPING_FLAT_CENTS = 800;
const LEGACY_VARIANT = new Map([
    ['hoop-black-knit', 'hoop-black'],
    ['hoop-black-sport', 'hoop-black'],
    ['hoop-white-knit', 'hoop-white'],
    ['hoop-white-sport', 'hoop-white'],
]);
/** @param {string} variantId */
function canonicalVariantId(variantId) {
    return LEGACY_VARIANT.get(variantId) || variantId;
}
/** @param {number} quantity */
function clampQuantity(quantity) {
    if (!Number.isFinite(quantity))
        return 1;
    return Math.min(9, Math.max(0, Math.floor(quantity)));
}
/** @param {string} code */
function normalizeDiscountCode(code) {
    return typeof code === 'string' ? code.trim().toUpperCase() : '';
}
/** @param {string} code */
function isKnownDiscount(code) {
    return normalizeDiscountCode(code) === exports.TEST_DISCOUNT_CODE;
}
/** @returns {CartState} */
function emptyCart() {
    return { lines: [] };
}
/** Normalize persisted quantities and merge legacy aliases before any operation.
 * @param {CartState} cart
 * @returns {CartState}
 */
function normalizeCart(cart) {
    /** @type {CartLineInput[]} */
    const lines = [];
    for (const line of Array.isArray(cart?.lines) ? cart.lines : []) {
        if (typeof line?.variantId !== 'string' || !line.variantId)
            continue;
        const variantId = canonicalVariantId(line.variantId);
        const quantity = clampQuantity(line.quantity);
        if (quantity <= 0)
            continue;
        const existing = lines.find((item) => item.variantId === variantId);
        if (existing)
            existing.quantity = clampQuantity(existing.quantity + quantity);
        else
            lines.push({ variantId, quantity });
    }
    const discountCode = normalizeDiscountCode(cart?.discountCode || '');
    return discountCode ? { lines, discountCode } : { lines };
}
/** @param {CartState} cart @param {string} variantId @param {number} quantity */
function addLine(cart, variantId, quantity) {
    const next = normalizeCart(cart);
    const nextQuantity = clampQuantity(quantity);
    if (!variantId || nextQuantity <= 0)
        return next;
    const canonicalId = canonicalVariantId(variantId);
    const existing = next.lines.find((line) => line.variantId === canonicalId);
    if (existing)
        existing.quantity = clampQuantity(existing.quantity + nextQuantity);
    else
        next.lines.push({ variantId: canonicalId, quantity: nextQuantity });
    return next;
}
/** @param {CartState} cart @param {string} variantId @param {number} quantity */
function updateLine(cart, variantId, quantity) {
    const next = normalizeCart(cart);
    const canonicalId = canonicalVariantId(variantId);
    const nextQuantity = clampQuantity(quantity);
    next.lines = next.lines.flatMap((line) => line.variantId !== canonicalId ? [line] : nextQuantity > 0 ? [{ ...line, quantity: nextQuantity }] : []);
    return next;
}
/** @param {CartState} cart @param {string} variantId */
function removeLine(cart, variantId) {
    return updateLine(cart, variantId, 0);
}
/** @param {CartState} cart @param {string} code */
function setDiscount(cart, code) {
    return normalizeCart({ ...cart, discountCode: code });
}
/**
 * @template {PriceProduct} P
 * @param {P[]} products
 * @param {string} variantId
 * @returns {{product: P, variant: P['variants'][number]} | undefined}
 */
function resolveVariant(products, variantId) {
    const canonicalId = canonicalVariantId(variantId);
    for (const product of products) {
        const variant = product.variants.find((item) => item.id === canonicalId);
        if (variant)
            return { product, variant };
    }
    return undefined;
}
/**
 * Resolve cart lines and calculate a complete quote using integer cents.
 * Shipping qualification uses the subtotal before the test discount.
 * @template {PriceProduct} P
 * @param {CartState} cart
 * @param {P[]} products
 */
function quoteCart(cart, products) {
    const normalized = normalizeCart(cart);
    const lines = normalized.lines.flatMap((line) => {
        const found = resolveVariant(products, line.variantId);
        if (!found || !Number.isFinite(found.product.price) || found.product.price < 0)
            return [];
        return [{ line, ...found }];
    });
    const subtotalCents = lines.reduce((sum, { line, product }) => sum + Math.round(product.price * 100) * line.quantity, 0);
    const discountCents = isKnownDiscount(normalized.discountCode || '') ? Math.round(subtotalCents / 10) : 0;
    const shippingCents = subtotalCents > 0 && subtotalCents < SHIPPING_THRESHOLD_CENTS ? SHIPPING_FLAT_CENTS : 0;
    return {
        lines,
        quantity: lines.reduce((sum, { line }) => sum + line.quantity, 0),
        subtotal: subtotalCents / 100,
        discount: discountCents / 100,
        shipping: shippingCents / 100,
        total: (subtotalCents - discountCents + shippingCents) / 100,
    };
}
/** @param {number} amount */
function formatMoney(amount) {
    const rounded = Math.round(amount * 100) / 100;
    return Number.isInteger(rounded) ? `$${rounded}` : `$${rounded.toFixed(2)}`;
}

window.NextBodyCart = exports;
})();
