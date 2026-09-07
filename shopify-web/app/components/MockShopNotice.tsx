export function MockShopNotice() {
  return (
    <section
      className="mock-shop-notice"
      aria-labelledby="mock-shop-notice-heading"
    >
      <div className="inner">
        <h2 id="mock-shop-notice-heading">Catalog is on mock data</h2>
        <p>
          The band shots below are HOOP. Shop cards still come from the Hydrogen
          mock store until this project is linked with{' '}
          <code>npx shopify hydrogen link</code>.
        </p>
      </div>
    </section>
  );
}
