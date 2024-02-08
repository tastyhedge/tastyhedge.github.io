---
layout: post
date: 2024-02-08
author: Oleksandr Gituliar
title: "Calibrate Americans with Open-Source"
---

In this post, I'd like to focus on the inverse problem to options pricing -- implied volatility
calibration.

**In my previous posts**, I discussed how to price American options [Pricing Americans with
Finite-Difference](/blog/finite-difference-americans), I focused on the finite-difference method and
with its help. In my opinion, this method is a must-know for everyone interested in quantitative
finance, since it's used to solve a broad range of problems on par with the famous Monte-Carlo
method.

**Trading options** without analyzing delta, vega, gamma, or other complex plots of your
option position. You just go to your trading app and price is already there. You can take a long or
even short position pretty much like you do with stocks. However, if your intentions go beyond
buying a lottery ticket, you'd probably prefer to risk manage your position and keep under control
how it changes, for example as a stock price moves.

In this case, it's not enough to get stock and option prices from your broker, you also need to know
the implied volatility. Of course, your broker will give you volatility data as well, however:

- Implied volatility is not available ad-hock from the exchange and should be calculated by the
  broker itself.
- Implied volatility is model-dependent and varies on the model you use to price options. For
  example, it might differ if you use Black-Scholes model for American or European options.

## You as a Broker

Imagine that you want to open a brokerage firm and need to provide volatility data to your clients
or risk manage your own positions if you want to trade against your clients. To fullfil that goal we
should take care of several things:

**Market data.** This is usually available online with some delay, as real-time data is very
expensive.

Tesla options. No dividends. As an example, let's look at 5-min snapshots of Tesla options on
1-May-2023. In total, there are 566'720 options to price on that day, which gives 7'268 options
every 5 min.

**Risk analytics.** This sort of programs are also proprietary, however there're decent
open-source alternatives that we will utilize.

**Calculation speed.** We want to be fast. Probably not as fast as high-frequency peers, however
fast enough to calibrate each option every 10 min, as there are millions options quoted on the
exchange for more than 5'000 tickers with multiple strikes and expiry dates.

![xxx](/img/calibrate-americans/stats.png)

## European Calibration

Although calibration of the European options has no closed-form solution,
there is a very efficient algorithm to solve this problem. For more details and C++ implementation
see [Let's Be Rational](http://www.jaeckel.org/) by Peter Jaeckel.

```cpp
//  v   - option price
//  s   - stock price
//  k_  - strike
//  dte - days to expiry
//  w   - parity (put / call)
//  z   - implied volatility
//
Error
calibrateEuropean(f64 v, f64 s, f64 k_, f64 dte, Parity w, f64& z)
{
  f64 r = m_rateCurve->rate(dte);
  f64 q = 0;

  f64 t = dte / kDaysInYear;
  f64 k = k_ * exp(-t * r);

  z = implied_volatility_from_a_transformed_rational_guess(v, s, k, t, w);

  return "";
}
```

![xxx](/img/calibrate-americans/calibrateEuropean.png)

On my machine it takes on average 354ns per option to calibrate (with a standard deviation of 278
ns), which is about 3 million options per second. Below is a complete statistics collected with
[Tracy](https://github.com/wolfpld/tracy) profiler.

## American Pricing

```cpp
Error
priceAmerican(f64 s, f64 k, f64 dte, f64 z, f64 r, f64 q, Parity w, f64& v)
{
  auto w_ = (w == kParity_Call) ? ql::Option::Call : ql::Option::Put;
  auto payoff = make_shared<ql::PlainVanillaPayoff>(w_, k);

  // set up dates
  auto anchor = ql::Date(31, ql::Jul, 1944);
  auto dayCounter = ql::Actual365Fixed();
  auto maturity = anchor + std::ceil(dte);

  ql::Settings::instance().evaluationDate() = anchor;

  auto americanExercise = make_shared<ql::AmericanExercise>(anchor, maturity);

  ql::Handle<ql::YieldTermStructure>
    flatTermStructure = make_shared<ql::FlatForward>(anchor, r, dayCounter);

  ql::Handle<ql::YieldTermStructure>
    flatDividendTS = ql::ext::make_shared<ql::FlatForward>(anchor, q, dayCounter);

  ql::Handle<ql::Quote>
    underlyingH = ql::ext::make_shared<ql::SimpleQuote>(s);

  ql::Handle<ql::BlackVolTermStructure>
    flatVolTS = make_shared<ql::BlackConstantVol>(anchor, ql::TARGET(),
                                                  std::abs(z), dayCounter);

  auto bsmProcess = make_shared<ql::BlackScholesMertonProcess>(
    underlyingH, flatDividendTS, flatTermStructure, flatVolTS);

  auto engine = make_shared<ql::QdFpAmericanEngine>(
    bsmProcess, ql::QdFpAmericanEngine::fastScheme());

  ql::VanillaOption americanOption(payoff, americanExercise);

  americanOption.setPricingEngine(engine);

  try {
      // Finally call Andersen et al.
      v = americanOption.NPV();
  }
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

![xxx](/img/calibrate-americans/priceAmerican.png)

As you already know, most equity options are of the American style. Such options are costly to price
because of their early-exercise feature. However, QuantLib contains implementation of the
[Andersen-Lake-Offengenden](https://papers.ssrn.com/sol3/papers.cfm?abstract_id=2547027) method,
which is a very fast way to price Americans.

For pricing American options I'll use a
[QuantLib](https://hpcquantlib.wordpress.com/2022/10/09/high-performance-american-option-pricing/)
implementation of the, which to my knowledge is the fastest algorithm for pricing americans
currently available. It's extremely accurate and x100 faster than tree or finite-difference methods.

Below is a full statistics with mean of 15us per option, which is 50x slower than calibration of
European options.

## American Calibration

There is no fast method to calibrate American options similar to the Jaeckel's algorithm. Hence, I
use classical [Newton-Raphson](https://en.wikipedia.org/wiki/Newton%27s_method) method: starting
with a European volatility as an initial guess and adjusting it repeatedly until it replicates the
American price to the desired tolerance.

```cpp
Error
calibrateAmerican(f64 v_, f64 s, f64 k, f64 dte, kParity_ w, f64& z)
{
  Error err;

  /// Initial guess
  ///
  f64 r = m_rateCurve->rate(dte);
  f64 q = 0;

  if (auto err = calibrateEuropean(v_, s, k, dte, w, z); !err.empty())
    return "calibrateAmerican : " + err;

  /// Newton-Raphson solver
  ///
  f64 v = v_;
  s16 n = 16;
  while (n-- > 0 && !std::isnan(z)) {
    if (auto err = priceAmerican(s, k, dte, z, r, q, w, v); !err.empty())
      return "calibrateAmerican : " + err;
    if (std::isnan(v))
      break;

    const f64 tolerance = 0.005;
    if (std::abs(v - v_) < tolerance)
      /// Solution found
      return "";

    /// Finite-difference derivative
    f64 vUp;
    const f64 dz = 0.0001;
    if (err = priceAmerican(s, k, dte, z + dz, r, q, w, vUp); !err.empty())
      break;

    f64 dvdz = (vUp - v) / dz;
    z -= (v - v_) / dvdz;
  }

  /// No solution
  z = NaN;
  return "";
}

```

As you can see from the statistics, **one American on average takes 60us to calibrate**, which is
equivalent to three American price calls (or one Newton-Raphson adjustment step). This is 170x
slower than European calibration with Jackel.

![xxx](/img/calibrate-americans/calibrateAmerican.png)

## Final Word
