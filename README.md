Toy US election simulator
================

This is nothing fancy. Just a simple election simulator based on
national and state-level polling. The code in this repo will generate
the graphs and statistics I shared here:
<https://twitter.com/gelliottmorris/status/1257331350618726400?s=20>

I hope this code well help shed some light on basic methods for
aggregating national and state polls, inferring electoral standings in
states without a lot of data and simulating what might happen in the
electoral college if polls lead us astray.

**None of this should be considered an official election forecast**,
this is just a fun exercise in coding and political statistics.

## Technical notes

The simulated error in this model is specified to capture the empirical
(IE historical) uncertainty in state-level polls fielded 200 days before
the election. It may not be well-calibrated to handle any additional
error from the regression model used to “fill in” averages in states
without any or many polls, so take it (and the rest of this exercise)
with a grain of
salt.

## Automated report:

![.github/workflows/refresh\_readme.yml](https://github.com/elliottmorris/toy-us-election-simulator/workflows/.github/workflows/refresh_readme.yml/badge.svg)

The following maps and stats are updated periodically throughought the
day using [GitHub Actions](https://github.com/features/actions).

Last updated on **May 20, 2020 at 19:06 PM.**

### National polling average:

Joe Biden’s margin in national polls is
**<span style="color: #3498DB;">5.6</span>** percentage points. That is
different than his margin implied by the state-level polls and the
demographic regression, which is
**<span style="color: #3498DB;">7.6</span>** percentage points.

### State polling averages:

![](README_files/figure-gfm/unnamed-chunk-2-1.png)<!-- -->

### Tipping-point state

| State | Tipping point chance (%) | State | Tipping point chance (%) |
| :---- | -----------------------: | :---- | -----------------------: |
| FL    |                     17.9 | WA    |                      0.9 |
| PA    |                      9.4 | OR    |                      0.8 |
| TX    |                      8.8 | SC    |                      0.8 |
| NC    |                      6.8 | CT    |                      0.7 |
| AZ    |                      6.7 | MT    |                      0.6 |
| MI    |                      6.6 | MO    |                      0.5 |
| OH    |                      6.2 | MS    |                      0.5 |
| WI    |                      5.5 | NJ    |                      0.5 |
| GA    |                      5.0 | RI    |                      0.4 |
| VA    |                      4.9 | DE    |                      0.3 |
| MN    |                      4.6 | KS    |                      0.2 |
| NV    |                      2.0 | AK    |                      0.1 |
| CO    |                      1.8 | AL    |                      0.1 |
| ME    |                      1.6 | IN    |                      0.1 |
| NH    |                      1.5 | LA    |                      0.1 |
| NM    |                      1.5 | NE    |                      0.1 |
| IL    |                      1.4 | TN    |                      0.1 |
| IA    |                      0.9 | UT    |                      0.1 |

### Electoral college-popular vote divide

On average, the tipping point state is
**<span style="color: #3498DB;">2.2</span>** percentage points to the
**<span style="color: #3498DB;">right</span>** of the nation as a whole.
