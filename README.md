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
with a grain of salt.

## Automated report:

![refresh\_readme](https://github.com/elliottmorris/toy-us-election-simulator/workflows/refresh_readme/badge.svg)

The following maps and stats are updated periodically throughought the
day using [GitHub Actions](https://github.com/features/actions).

Last updated on **May 20, 2020 at 09:13 PM EDT.**

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
| FL    |                     15.8 | NJ    |                      0.8 |
| TX    |                      9.9 | CT    |                      0.7 |
| PA    |                      9.4 | SC    |                      0.7 |
| MI    |                      7.9 | MO    |                      0.5 |
| NC    |                      6.9 | DE    |                      0.4 |
| GA    |                      6.2 | AK    |                      0.3 |
| AZ    |                      5.4 | KS    |                      0.3 |
| OH    |                      5.0 | LA    |                      0.3 |
| WI    |                      4.8 | MS    |                      0.3 |
| MN    |                      4.5 | RI    |                      0.3 |
| VA    |                      4.5 | IN    |                      0.2 |
| NV    |                      2.9 | MT    |                      0.1 |
| NH    |                      1.8 | NE    |                      0.1 |
| IA    |                      1.7 | UT    |                      0.1 |
| NM    |                      1.7 | AL    |                      0.0 |
| ME    |                      1.6 | ID    |                      0.0 |
| CO    |                      1.5 | MA    |                      0.0 |
| WA    |                      1.4 | NY    |                      0.0 |
| OR    |                      1.0 | TN    |                      0.0 |
| IL    |                      0.8 | VT    |                      0.0 |

### Electoral college-popular vote divide

On average, the tipping point state is
**<span style="color: #3498DB;">2.3</span>** percentage points to the
**<span style="color: #3498DB;">right</span>** of the nation as a whole.
