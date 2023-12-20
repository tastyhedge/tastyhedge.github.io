---
layout: post
author: Oleksandr Gituliar
title: "Finite-Difference"
---

<!-- - Option Chain for AAPL / AMD / TSLA -->

In [my previous post]() I discussed performance of the finite-difference algorithm for pricing
American options on CPU vs GPU. Since then, people have asked to elaborate on the pricing algorithm
itself. Hence, this post is dedicated to the [Finite-Difference
Method](https://en.wikipedia.org/wiki/Finite_difference_methods_for_option_pricing).

**C++ is a great language** to implement a finite-difference pricer on CPU and GPU. You'll find full
source code from the previous post in [gituliar/kwinto-cuda]() on GitHub. Here, I'll discuss some of
its key parts.

For C++ development, I recommend my favorite setup: Visual Studio for Windows + CMake + vcpkg.
Occasionally, I also compile on Ubuntu Linux with GCC and Clang, which is possible since I use CMake
in my projects.

**Pricing American options** is an open problem in the quantitative finance. It has no closed form
solution similar to the Black-Scholes formula for European options. Therefore, to solve this problem
in practice various _numerical methods_ are used.

To continue, you don't need deep knowledge of the finite-difference method. This material should be
accessible for people with basic understanding of C++ and numerical methods at the undergraduate level.

<!-- You don't need to have hands-on experience with a finite-difference method. All necessary details
will appear as we go. It's neither scarry nor difficult, believe me. -->

**Calibration.** For now we solve a pricing problem only, that is to find an option price given
_implied volatility_ and option parameters, like strike, expiry, etc. In practice, the implied
volatility is unknown and should be determined given the option price from the exchange. This is
known as _calibration_ and is the inverse problem to pricing, which we'll focus on in another post.

For example, below is a chain of option prices and already calibrated implied
volatilities for AMD as of 2023-11-17 15:05:

![AMD Option Chain on 2023-11-17 15:05](/assets/img/AMD-options.jpg)

## Pricing Equation

**American option's price** is defined as a solution of the [Black-Scholes
equation](https://en.wikipedia.org/wiki/Black%E2%80%93Scholes_equation). In fact, it's the same
equation that results into a famous [Black-Scholes formula]() for European option. However, for
American option we should impose an extra condition to account for the _early exercise_, which we
discuss down below. It's this early-exercise condition that makes the original equation so difficult
that we have no option, but to solve it numerically.

**The Black-Scholes equation** is that just a particular example of the pricing differential
equation. In general, we can define similar differential equations for various types and flavours of
options and other derivatives, which can be treated with the same method. This versatility is what
makes the finite-difference so popular among quants and widely used in financial institutions.

**The pricing equation** is usually derived using [Delta Hedging]() argument, which is an intuitive
and powerful approach to derive pricing equations, not only for vanilla options, but for exotic
multi-asset derivatives as well. See ... for more details.

In practice, it's more convenient to change variables to `x = \ln(s)` which leads to the following
equation:

![Pricing PDE](/assets/img/Black-Scholes.jpg)

## Numerical Solution

**The Black-Scholes** equation belongs to the family of [diffusion equations](), which in general
case have no closed-form solution. Fortunately it's one of the easiest differential equations to
solve numerically, which apart from the
[Finite-Difference](https://en.wikipedia.org/wiki/Finite_difference_method), are usually treated
with [Monte-Carlo]() or [Fourier transformation]() methods.

**The Solution.** Let's be more specific about the solution we are looking for. Our goal is to find
the option price _function_ `V(t,s)` at a fixed time `t=0` (today) for arbitrary spot price `s`.
Here

- `t` is time from today;
- `s` is the spot price of the option's underlying asset. Although, it's more convenient to work
  with `x = ln(s)` instead.

Let's continue with concrete steps of the finite-difference method:

**1) Finite Grid.** We define a _rectangular grid_ on the domain of independent variables `(t,s)`
which take

- `t[i] = t[i-1] + dt[i] ` for `i=0..N-1`
- `x[j] = x[j-1] + dx[j] ` for `j=0..M-1`.

This naturally leads to the following C++ definitions:

```cpp
#define N 512
#define M 1024

auto xDim = 512;
auto tDim = 512;

std::vector<f64> x;
std::vector<f64> t;
```

**2) [Difference Operators](https://en.wikipedia.org/wiki/Finite_difference#Basic_types)** are used
to approximate continuous derivatives in the original pricing equation. They are defined on the
`(t,x)` grid as:

![Discretization](/assets/img/Difference-Operators.jpg)

**3) Finite-Difference Equation**, a discrete version of the Black-Scholes equation, is derived from
the pricing equation by replacing continuous derivatives with difference operators defined in Step 2.

It's convenient to introduce the A operator, which contains difference operators over the x-axis
only.

![Pricing PDE](/assets/img/Difference-Equation.jpg)

**4) Solution Scheme.** The above equation isn't completely defined yet, as we can expand
**\delta_t** operator in several ways. (**\delta_x and \delta_xx** operators are generally chosen
according to the central difference definition.)

**\delta_t** operator might be chosen as _Forward_ or _Backward_ difference, which lead to the
[explicit scheme](https://en.wikipedia.org/wiki/Finite_difference_method#Explicit_method) solution.
In this case, the numerical error is O(dt) + O(dx^2), which is not the best we can achieve.

**[Crank-Nicolson](https://en.wikipedia.org/wiki/Finite_difference_method#Crank%E2%80%93Nicolson_method)
scheme**, an implicit scheme, is a better alternative to the explicit scheme. It's slightly more
complicated, since requires to solve a liner system of equations, however the numerical error is
O(dt^2) + O(dx^2), which is much better than for the explicit schemes.

You can think of the Crank-Nicolson scheme as a continuos mix of forward and backward schemes tuned
by \theta parameter, so that

- `\theta = 1` is Euler forward scheme
- `\theta = 0` is Euler backward
- `\theta = 1/2` is Crank-Nicolson scheme

![Finite-Difference Schemes](/assets/img/Finite-Difference.jpg)

**5) Backward Evolution.** I guess at this point it's clear what our next step should be. All we
need is to solve a _tridiagonal_ linear system in order to find `V(t_i)` from `V(t_i+1)` as is
prescribed by the Crank-Nicolson method above. The _initial value_ is given by the option price at
maturity `V(t=T)`, which is equal to the _payoff_ or _intrinsic value_ for a given strike `k`, in
other words

- `max(s-k, 0)` for calls,
- `max(k-s, 0)` for puts.

[Thomas algorithm](https://en.wikipedia.org/wiki/Tridiagonal_matrix_algorithm) is a simplified
form of Gaussian elimination that is used to solve tridiagonal systems of linear equations. For
such systems, the solution can be obtained in O(n) operations instead of O(n^3) required by
Gaussian elimination, which makes this step relatively fast.

C++ implementation of the Thomas solver is compact and widely available, for example, see [Numerical
Recipes](https://numerical.recipes/). I list it below for completeness:

```cpp
Error
solveTridiagonal(
    const int xDim,
    const f64* al, const f64* a, const f64* au,    /// LHS
    const f64* y,                                  /// RHS
    f64* x)                                        /// Solution
{
    if (a[0] == 0)
        return "solveTridiagonal: Error 1";
    if (xDim <= 2)
        return "solveTridiagonal: Error 2";

    std::vector<f64> gam(xDim);

    f64 bet;
    x[0] = y[0] / (bet = a[0]);
    for (auto j = 1; j < xDim; j++) {
        gam[j] = au[j - 1] / bet;
        bet = a[j] - al[j] * gam[j];

        if (bet == 0)
            return "solveTridiagonal: Error 3";

        x[j] = (y[j] - al[j] * x[j - 1]) / bet;
        if (x[j] < 0)
            continue;
    };

    for (auto j = xDim - 2; j >= 0; --j) {
        x[j] -= gam[j + 1] * x[j + 1];
    }

    return "";
};

```

**6) Early Exercise.** For American options we should taken into account the right to exercise
before maturity. As already mention, this particular feature make the Black-Scholes equation more
complicated with no closed-form solution.

I account for this at every backward evolution step like this:

```cpp
for (auto xi = 0; xi < xDim; ++xi) {
    v[xi] = std::max(v[xi], vInit[xi]);
}
```

![Early Exercise Condition](/assets/img/Early-Exercise.jpg)

## Boundary Conditions

You probably noticed that our definition of the difference operators on the grid is incomplete.
Namely, the x-axis difference is not well defined at boundaries of the grid.

**At boundaries**, difference operators over the x-axis are not well defined as some values outside
of the grid are missing. For example,

```
V'(x_0) = (V(x_1) - V(x_-1)) / (x_1 - x_-1)
```

however `x_-1` and `V(x_-1)` are not defined.

We overcome this by taking into account the asymptotic behavior of the price function `V(t,s)` at
boundaries of `s`, when `s -> 0` and `s -> +oo`.

We know that `delta` is constant at boundaries, either 0 or 1, depending on the parity (PUT or
CALL). However, more universal relation is that `gamma = 0` at boundaries. This gives the following
relation:

## Finite-Difference Grid

Finally, it's time to discuss how grid points are distributed over `x`- and `t`-axes. So far we just
said that there are `N` and `M` points along each axis, but said nothing about the limits and
distribution of those points. In other words, what are the values `x[0]` / `x[M-1]` and gaps `dt[i]
= t[i+1] - t[i]` and `dx[i] = x[i+1] - x[i]` ?

**The t-Axis** is divided uniformly with a step dt = T / N between points. It doesn't seem to use
some non-uniform step here, at least not something I observed in practice.

**The x-Axis** is divided in a more tricky way. ...

![Asinh Plot](/assets/img/fd-asinh.png)

```cpp
/// Init X-Grid

const f64 density = 0.1;
const f64 scale = 10;

const f64 xMid = log(s);
const f64 xMin = xMid - scale * z * sqrt(t);
const f64 xMax = xMid + scale * z * sqrt(t);

const f64 yMin = std::asinh((xMin - xMid) / density);
const f64 yMax = std::asinh((xMax - xMid) / density);

const f64 dy = 1. / (xDim - 1);
for (auto j = 0; j < xDim; j++) {
    const f64 y = j * dy;
    xGrid(j) = xMid + density * std::sinh(yMin * (1.0 - y) + yMax * y);
}

/// Inspired by https://github.com/lballabio/QuantLib files:
///   - fdmblackscholesmesher.cpp
///   - fdblackscholesvanillaengine.cpp
```

## Conclusion

Finite-Difference is a powerful numerical method, widely used by the quantitative finance
practitioners. It can treat problems with exotic derivatives with non-constant coefficients and is
easy to program, as we saw in this post.
