import {Await, Link} from 'react-router';
import {Suspense} from 'react';
import type {
  FeaturedCollectionFragment,
  RecommendedProductsQuery,
} from 'storefrontapi.generated';
import {ProductItem} from '~/components/ProductItem';
import {MockShopNotice} from '~/components/MockShopNotice';
import {
  HomeScreen,
  VitalsScreen,
  BodyBatteryScreen,
  SleepScreen,
  TrainingScreen,
  FuelScreen,
  PlanScreen,
  ChatScreen,
} from '~/components/AppScreens';

type HomeLandingProps = {
  isShopLinked: boolean;
  featuredCollection: FeaturedCollectionFragment | undefined;
  recommendedProducts: Promise<RecommendedProductsQuery | null>;
};

export function HomeLanding({
  isShopLinked,
  featuredCollection,
  recommendedProducts,
}: HomeLandingProps) {
  return (
    <div className="home">
      {isShopLinked ? null : <MockShopNotice />}
      <Hero />
      <Statement />
      <Band />
      <AppShowcase />
      <Pillars />
      <Hardware />
      <Science />
      <ShopRail
        featuredCollection={featuredCollection}
        recommendedProducts={recommendedProducts}
      />
      <Close />
    </div>
  );
}

function Hero() {
  return (
    <section className="hero" aria-labelledby="hero-title">
      <img
        alt=""
        className="hero-bg"
        src="/band/product-black-nylon.jpg"
      />
      <div className="hero-scrim" />
      <div className="hero-copy">
        <p className="eyebrow">HOOP</p>
        <h1 id="hero-title">The wearable designed for your next body.</h1>
        <p className="hero-lede">
          A screenless band. Heart, sleep, training, and a body battery — read
          in the NextBody app. Not a watch.
        </p>
        <div className="hero-actions">
          <Link className="btn btn-light" prefetch="intent" to="/collections/all">
            Get HOOP
          </Link>
        </div>
      </div>
    </section>
  );
}

function Statement() {
  return (
    <section className="statement" aria-label="Position">
      <p>Worn all day. Read when you want. The wrist stays quiet.</p>
    </section>
  );
}

function Band() {
  return (
    <section className="band" id="band" aria-labelledby="band-title">
      <div className="band-copy">
        <p className="eyebrow">The band</p>
        <h2 id="band-title">No screen. No glance. Just wear it.</h2>
        <p>
          HOOP is a screenless wristband — case, strap, worn on the wrist. Optical
          sensors keep the day. The phone is where the reading lives.
        </p>
        <p>
          One side key. A knit nylon strap or a sport strap. Black or silver
          case. Eight millimeters on the wrist.
        </p>
      </div>
      <div className="band-gallery">
        <figure className="band-shot band-shot-main">
          <img
            alt="HOOP black knit, top view of the metal case"
            src="/band/product-black-top.jpg"
          />
        </figure>
        <figure className="band-shot">
          <img
            alt="HOOP silver knit, three-quarter view"
            src="/band/product-silver-nylon.jpg"
          />
        </figure>
        <figure className="band-shot">
          <img
            alt="HOOP black knit, side profile of the case and rings"
            src="/band/product-black-side.jpg"
          />
        </figure>
      </div>
    </section>
  );
}

function AppShowcase() {
  return (
    <section className="app-showcase" aria-labelledby="app-title">
      <div className="app-showcase-head">
        <p className="eyebrow">The app</p>
        <h2 id="app-title">One panel. One plan. One answer.</h2>
        <p>
          NextBody is the only place the band speaks. Home is the panel, page
          two is the instruments, and the plan is what the day should do.
        </p>
      </div>
      <div className="app-showcase-grid">
        <div className="app-screen-cell">
          <HomeScreen />
          <p className="app-screen-label">Home · Body battery + the day</p>
        </div>
        <div className="app-screen-cell">
          <VitalsScreen />
          <p className="app-screen-label">Page two · Eight instruments</p>
        </div>
        <div className="app-screen-cell">
          <PlanScreen />
          <p className="app-screen-label">Plan · Today&apos;s tasks</p>
        </div>
        <div className="app-screen-cell">
          <ChatScreen />
          <p className="app-screen-label">Chat · Ask anything</p>
        </div>
      </div>
    </section>
  );
}

function Pillars() {
  return (
    <section className="pillars" aria-labelledby="pillars-title">
      <div className="pillars-head">
        <p className="eyebrow">In the app</p>
        <h2 id="pillars-title">Three numbers that run the day.</h2>
      </div>
      <ul className="pillar-grid">
        <li className="pillar">
          <h3>Body battery</h3>
          <p>How much you have left to spend. Built from the wrist, settled each day.</p>
        </li>
        <li className="pillar">
          <h3>Sleep</h3>
          <p>The night, staged and scored. Overnight oxygen stays on the night clock.</p>
        </li>
        <li className="pillar">
          <h3>Training</h3>
          <p>Load on a 0–21 day. Not a weekly pile. Not a watch face.</p>
        </li>
      </ul>
      <figure className="pillars-photo">
        <img
          alt="Runner wearing HOOP on the left wrist"
          src="/band/lifestyle-run.jpg"
        />
      </figure>
    </section>
  );
}

function Hardware() {
  return (
    <section className="hardware" aria-labelledby="hardware-title">
      <div className="hardware-head">
        <p className="eyebrow">On the wrist</p>
        <h2 id="hardware-title">Two straps. Two finishes. One case.</h2>
      </div>
      <div className="hardware-grid">
        <article className="hardware-card">
          <img
            alt="Black knit nylon strap through the HOOP case"
            src="/band/product-black-nylon.jpg"
          />
          <div>
            <h3>Knit nylon</h3>
            <p>Woven, breathable, made to stay on.</p>
          </div>
        </article>
        <article className="hardware-card">
          <img
            alt="Black sport strap, slim profile of the HOOP case"
            src="/band/product-sport-profile.jpg"
          />
          <div>
            <h3>Sport strap</h3>
            <p>Honeycomb elastomer for wet work and heat.</p>
          </div>
        </article>
        <article className="hardware-card hardware-card-wide">
          <img
            alt="Person wearing HOOP, close on the wrist"
            src="/band/lifestyle-portrait.jpg"
          />
          <div>
            <h3>8 mm</h3>
            <p>Low enough to forget. High enough to hold the sensors.</p>
          </div>
        </article>
      </div>
    </section>
  );
}

function Science() {
  return (
    <section className="science" id="science" aria-labelledby="science-title">
      <div className="science-copy">
        <p className="eyebrow">What it reads</p>
        <h2 id="science-title">The wrist is the instrument. The app is the page.</h2>
        <p>
          Heart rate, HRV, stress, skin temperature, steps, and overnight
          oxygen. Body composition when you take a scan. Training and meals live
          in NextBody — not on the band.
        </p>
        <p className="science-note">
          For people 18 and over. HOOP is not a medical device. It does not take
          an ECG, and it does not diagnose.
        </p>
      </div>
      <figure className="science-photo">
        <img
          alt="Training with HOOP on the wrist"
          src="/band/lifestyle-train.jpg"
        />
      </figure>
    </section>
  );
}

function ShopRail({
  featuredCollection,
  recommendedProducts,
}: Pick<HomeLandingProps, 'featuredCollection' | 'recommendedProducts'>) {
  const shopHref = featuredCollection
    ? `/collections/${featuredCollection.handle}`
    : '/collections/all';

  return (
    <section className="shop-rail" id="shop" aria-labelledby="shop-title">
      <div className="shop-rail-head">
        <div>
          <p className="eyebrow">Shop</p>
          <h2 id="shop-title">Get HOOP</h2>
        </div>
        <Link className="btn-ghost" prefetch="intent" to={shopHref}>
          View all
        </Link>
      </div>
      <Suspense fallback={<p className="shop-fallback">Loading the kit…</p>}>
        <Await resolve={recommendedProducts}>
          {(response) => (
            <div className="recommended-products-grid">
              {response
                ? response.products.nodes.map((product) => (
                    <ProductItem key={product.id} product={product} />
                  ))
                : null}
            </div>
          )}
        </Await>
      </Suspense>
    </section>
  );
}

function Close() {
  return (
    <section className="close-band" aria-labelledby="close-title">
      <p className="eyebrow">NextBody</p>
      <h2 id="close-title">Find your next body.</h2>
      <Link className="btn" prefetch="intent" to="/collections/all">
        Get HOOP
      </Link>
    </section>
  );
}
