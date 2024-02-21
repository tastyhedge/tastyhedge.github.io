---
layout: post
date: 2024-02-08
author: Oleksandr Gituliar
title: "How-To Calibrate American Options Really Fast"
draft: true
---

**In this post**, you will learn how to calibrate American options in C++. We will use modern
methods and open-source tools, so the calibration process will be really fast and accessible to
everyone.

Calibration is ... The purpose of the model itself is to quantify the risks of
derivatives, which is an inevitable step to build advanced hedging and trading strategies.

We consider Black-Scholes model with early exercise. It's suitable for pricing equity options, which
are mostly of American style. Early-exercise models have no analytical solution and usually are
solved with some time-consuming numerical method. We use a [boundary-interpolation]() method, which
is available in [QuantLib](). This modern method is very fast and is essential for anyone interested
in quantitative finance.

**In my previous post**, we saw how to price American options with
[finite-difference](/blog/finite-difference-americans) method. This method is much slower, however
more universal and can be used to solve a much broader range of problems, similar to Monte-Carlo.
Every seasoned quant should master both methods.

## Intro

**Trading options** is possible without a risk management strategy. You don't necessary need to
understand a pricing model and all risk measures it calculates (like delta, vega, gamma, etc.).
Option prices are available in the trading app that is provided by your broker. You can buy or even
sell options pretty much like you do with stocks.

**A naive approach** like that one, will eventually lead to a disaster very soon. Hence, if your
intentions go beyond betting on a stock market using options, you'd better hedge your risks and keep
under control risk limits of your portfolio.

**Implied volatility** is what defines the Black-Scholes model, which you need for risk management,
as option prices alone can't quantify the underlying risks. Your broker will likely provide implied
volatility data, however keep in mind that:

- **Pricing model** is another piece that you need to make IV useful. The model is an engine that
  quantifies the risks, given the implied volatility and observable market data (such as option
  price, stock price, interest rate, and dividend rate). For example, it might differ if you use
  Black-Scholes model for American or European options.
- **Market Data** Option exchanges do not provide implied volatility and should be calculated by the
  broker itself. This is a non-trivial and time-consuming task...

## Prerequisite

**Imagine for a moment** that we want to run a brokerage business. Apart from the main service -- to
execute client orders -- we'd also better to provide volatility data, so that our clients can manage
risks of their positions and survive in the whirl of the financial market. In addition, we might
consider to manage risk of our own positions if we decide to take some risk too.

**Market data** is provided by the exchange, like option prices, volume, open interest, etc.
Perfectly, we'd like to get this data in real-time, however for the calibration exercise we are fine
with historical data that is available on the internet for some small fee.

**Options market** is 1'000x bigger than stock market. **Calculation speed.** We want to be fast.
Probably not as fast as high-frequency peers, however fast enough to calibrate each option every 10
min, as there are millions options quoted on the exchange for more than 5'000 tickers with multiple
strikes and expiry dates.

**Tesla (TSLA)** is good candidates to test our approach. Liquid. No dividends. As an example, let's
look at 5-min snapshots of Tesla options on 1-May-2023. In total, there are 566'720 options to price
on that day, which gives 7'268 options every 5 min.

**Interest rate** is taken from Federal Reserve data

**Risk analytics.** This sort of programs are proprietary and expensive, however we can calibrate
ourselves. After all, that's what this post is about, so let's dive in.

## Step1: European Calibration

**The first step** in our approach is to calibrate a European option. This gives a good guess for
the American volatility, which we will improve later in Step 3.

**European calibration** has no closed-form solution. Fortunately, there is a very efficient
numerical algorithm: [Let's Be Rational](http://www.jaeckel.org/) by Peter Jaeckel. Its reference
implementation is available in C++ and other languages. We use it as following:

<!-- **`implied_volatility_from_a_transformed_rational_guess`** function from `lets_be_rational.cpp`
which -->

```cpp
// #include <...>

Error
calibrateEuropean(
  f64    v,                          //  option price
  f64    s,                          //  stock price
  f64    k,                          //  strike
  f64    dte,                        //  days to expiration
  Parity w,                          //  put / call
  f64&   z)                          //  implied volatility
{
  f64 r = m_rateCurve->rate(dte);    //  interest rate
  f64 q = 0;                         //  dividend rate

  f64 t = dte / kDaysInYear;
  f64 k_ = k * exp(-t * r);

  z = implied_volatility_from_a_transformed_rational_guess(v, s, k_, t, w);

  return "";
}
```

### Performance

**2'800'000 opt/s** is how many European options I'm able to calibrate on my machine with AMD Ryzen
9 CPU. You may wonder whether this is a lot or not ?

**The options market** has about 750'000 options listed on 5'000 stocks. Hence, we can calibrate the
entire market in just 1/4 of a second on a single CPU core. Of course, this is not a nanosecond
scale, required for high-frequency trading, however it's more than enough for most hedging and
trading strategies.

**Advanced statistic** with per-call distribution time of `calibrateEuropean`, collected with
[Tracy](https://github.com/wolfpld/tracy) profiler, looks as following:

![Step 1: Statistics](calibrateEuropean.png)

## Step 2: American Pricing

**The second step** is to adjust our initial guess to a desired tolerated error. You'll see how to
do this in the next step. For now we need to learn how to efficiently price American options.

**American pricing** is costly because of the early-exercise feature. Fortunately, there is a modern
[boundary-interpolation](https://papers.ssrn.com/sol3/papers.cfm?abstract_id=2547027) method by
Andersen et al. It's available in
[QuantLib](https://hpcquantlib.wordpress.com/2022/10/09/high-performance-american-option-pricing/)
and is probably the fastest method to price American options.

**QuantLib** is an advanced library with many features, so we need to perform some preparation steps
prior to calling the pricing algorithm:

```cpp
// #include <...>

Error
priceAmerican(f64 s, f64 k, f64 dte, f64 z, Parity w, f64& v)
{
  /// Anchor + Maturity
  ///
  auto anchor = ql::Date(31, ql::Jul, 1944);
  auto act365 = ql::Actual365Fixed();
  auto maturity = anchor + std::ceil(dte);

  ql::Settings::instance().evaluationDate() = anchor;

  /// Option Data
  ///
  ql::Option
    w_ = (w == kParity_Call) ? ql::Option::Call : ql::Option::Put;

  f64 r = m_rateCurve->rate(dte);
  ql::Handle<ql::YieldTermStructure>
    r_ = make_shared<ql::FlatForward>(anchor, r, act365);

  f64 q = 0;
  ql::Handle<ql::YieldTermStructure>
    q_ = make_shared<ql::FlatForward>(anchor, q, act365);

  ql::Handle<ql::Quote>
    s_ = make_shared<ql::SimpleQuote>(s);

  ql::Handle<ql::BlackVolTermStructure>
    z_ = make_shared<ql::BlackConstantVol>(anchor, ql::TARGET(), z, act365);

  /// Black-Scholes Model
  ///
  auto bsm = make_shared<ql::BlackScholesMertonProcess>(s_, q_, r_, z_);
  auto engine = make_shared<ql::QdFpAmericanEngine>(
    bsm, ql::QdFpAmericanEngine::fastScheme());

  auto payoff = make_shared<ql::PlainVanillaPayoff>(w_, k);
  auto americanExercise = make_shared<ql::AmericanExercise>(anchor, maturity);
  ql::VanillaOption americanOption(payoff, americanExercise);

  americanOption.setPricingEngine(engine);

  /// Boundary-Interpolation Pricer
  ///
  try {
      v = americanOption.NPV();
  }

  /// Error Handling
  ///
  catch (...) {
      std::exception_ptr ep = std::current_exception();
      try {
          std::rethrow_exception(ep);
      }
      catch (std::exception& e) {
          return "priceAmerican : "s + e.what();
      }
  }

  return "";
}

```

### Performance

**45'000 opt/s** is how many American options I can price on the same machine. It's not as
impressive as 2'800'000 opt/s for European calibration. But it's about 100x faster than
pricing with the finite-difference method. See my post on [pricing American options on CPU and
GPU](blog/pricing-derivatives-on-a-budget/) for detailed benchmarks.

**Advanced statistic** with per-call distribution time of `priceAmerican`, collected with
[Tracy](https://github.com/wolfpld/tracy) profiler, looks as following:

![Step 2: Statistics](priceAmerican.png)

## Step 3: American Calibration

**The third step**, and the final one, is to adjust our initial guess repeatedly until it replicates
the American price to the desired tolerance. As option prices are quoted with $0.01 step, we can
safely tolerate the error within that range.

**[Newton's](https://en.wikipedia.org/wiki/Newton%27s_method) method** is a classical algorithm to
numerically find roots of a real-valued function. In our case, the function is a difference between
the model and market prices of the option, while unknown variable is implied volatility.

The final implementation looks as:

```cpp
Error
calibrateAmerican(f64 v_, f64 s, f64 k, f64 dte, kParity_ w, f64& z)
{
  Error err;

  /// Initial guess
  ///
  if (auto err = calibrateEuropean(v_, s, k, dte, w, z); !err.empty())
    return "calibrateAmerican : " + err;

  /// Newton's solver
  ///
  f64 v = v_;
  s16 n = 16;
  while (n-- > 0 && !std::isnan(z)) {
    if (auto err = priceAmerican(s, k, dte, z, w, v); !err.empty())
      return "calibrateAmerican : " + err;
    if (std::isnan(v))
      break;

    const f64 tolerance = 0.005;
    if (std::abs(v - v_) < tolerance)
      /// Solution found
      return "";

    /// Boundary-Interpolation Pricer
    ///
    f64 vUp;
    const f64 dz = 0.0001;
    if (err = priceAmerican(s, k, dte, z + dz, w, vUp); !err.empty())
      break;

    /// Finite-difference derivative
    ///
    f64 dvdz = (vUp - v) / dz;
    z -= (v - v_) / dvdz;
  }

  /// No solution
  ///
  z = NaN;
  return err;
}

```

### Performance

**16'500 opt/s** is how many American options I can calibrate on my machine. Effectively, we make 3
pricing calls per calibration. Eventually, it's 170x slower than European calibration with [Let's Be
Rational](http://www.jaeckel.org/) by Jaeckel, but much slower if using the finite-difference.

**Advanced statistic** with per-call distribution time of `calibrateAmerican`, collected with
[Tracy](https://github.com/wolfpld/tracy) profiler is shown below.

**The distribution** indicates that:

- Deep in- and out-the-money options are cheap to calibrate, as the volatility is the same for
  European and American cases, hence the initial guess is already an answer (see around 10 um
  region).
- At-the-money options, on the other hand, require several adjustment steps, hence more
  `priceAmerican` calls. This makes the whole calibration slower (see around 100 us region).

![Step 3: Statistics](calibrateAmerican.png)

## Conclusion

In order to build advanced hedging and trading strategies, portfolio managers need to quantify
underlying risks of their portfolios. This is what pricing models are responsible for.

In this post, we saw how to calibrate the Black-Scholes model to American option prices using C++
and modern quantitative methods. We discussed performance of our implementation by calibrating
quotes of the Tesla options.

Our approach allows to calibrate **16'500 opt/s** on a single AMD Ryzen 9 core. At this speed the
entire market of **750'000 options** listed on **5'000 stocks** should take **45 s** to calibrate.

![Summary](stats.png)
