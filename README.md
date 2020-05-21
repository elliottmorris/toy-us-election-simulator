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

![refresh\_readme](https://github.com/elliottmorris/toy-us-election-simulator/workflows/refresh_readme/badge.svg)

The following maps and stats are updated periodically throughought the
day using [GitHub Actions](https://github.com/features/actions).

Last updated on **May 20, 2020 at 08:49 PM EDT.**

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
| FL    |                       16 | MN    |                        3 |
| PA    |                       12 | WI    |                        3 |
| MI    |                       10 | NH    |                        2 |
| OH    |                        8 | NV    |                        2 |
| TX    |                        7 | CO    |                        1 |
| NC    |                        6 | CT    |                        1 |
| VA    |                        6 | DE    |                        1 |
| AZ    |                        5 | IA    |                        1 |
| GA    |                        5 | IL    |                        1 |
| NJ    |                        4 | OR    |                        1 |
| ME    |                        3 | RI    |                        1 |

### Electoral college-popular vote divide

On average, the tipping point state is
**<span style="color: #3498DB;">2.2</span>** percentage points to the
**<span style="color: #3498DB;">right</span>** of the nation as a whole.
