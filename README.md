Toy US election simulator
================

G. Elliott Morris
[@gelliottmorris](https://www.twitter.com/gelliottmorris)

This is just a simple election simulator based on national and
state-level polls. The code in this repo will generate the graphs and
statistics I shared
[here](https://twitter.com/gelliottmorris/status/1257331350618726400?s=20).

My aim for this code is to help shed some light on basic methods for
aggregating national and state polls, inferring electoral standings in
states without a lot of data and simulating what might happen in the
electoral college if polls lead us astray. **None of this should be
considered an official election forecast**, or really even a good one. I
bet you’d have better-than-replacement rates of success with it, but I
only wrote it for a fun coding exercise and to show people how this sort
of program works, so act accordingly.

This caveat being addressed, I will concede that I do think this model
will provide us with some interesting material as the election cycle
progresses, so I’ve set up the model to update the maps and tables at
the bottom of this document throughout the day using [GitHub
Actions](https://github.com/features/actions). You can check back here
regularly to see how the race is changing.

Technical notes
---------------

The file `scripts/main_poll_simulator.R` runs a series of models to
forecast the presidential election using national and state-level polls.
The first step is to average available polls fielded over the last two
months. That average is weighted by each poll’s sample size. If all
states had plenty of polls, this model would be easy; we would move on
to simulating many different “trial” elections by generating errors from
the appropriate distributions. Alas, not all states will be polled
adequately, so we turn to an intermediate step.

The second step is to predict what polls would say if pollsters surveyed
neglected states. We can regress Biden’s observed vote margin in each
state on a series of demographic variables in each. I use: Clinton’s
margin in the 2016 election; the share of adults who are black; the
share of adults with a bachelor’s degree or higher; the share of adults
who are Hispanic or another non-white, non-black race; the median age of
voters in a state; the share of adults who are white evangelicals; the
average number of people who live within five miles of any given
resident; the share of adults who are white and the share of adults who
are white without a college degree. Any regular statistical model would
struggle to avoid being over-fit by all these variables, so I use
[stepwise variable selection via
AIC](https://en.wikipedia.org/wiki/Stepwise_regression) and [elastic net
regularization](https://en.wikipedia.org/wiki/Elastic_net_regularization)
with a linear model trained using [leave-one-out
cross-validation](https://www.cs.cmu.edu/~schneide/tut5/node42.html). In
states with polls, the predictions from the regression model are given a
weight equal to that of a poll with an average sample size and averaged
with the raw polling data. In states without polls, the final “polling
average” is just the regression prediction.

Because polls are not perfect predictions of voting behavior, the final
step is to simulate many tens of thousands of different “trial”
election, in each one generating (a) national polling error, (b) a
regional polling error and (c) a state-level polling error. These errors
are disaggregated from the observed historical root-mean-square error of
election polls using a error sum-of-squares
[formula](https://fivethirtyeight.com/features/how-fivethirtyeight-calculates-pollster-ratings/)
that I cribbed from Nate Silver. This is equivalent to saying that
polling error is assumed to be correlated nationally and regionally, but
also have state-specific components that aren’t shared across
geographies. We could be more complex about this—–perhaps someone will
submit a pull request to generate correlated state-level errors using
`mvrnorm`, for example—but this works for my illustrative purposes here.

Odds and ends
-------------

**A note on timing:** The simulated error in this model is specified to
capture the empirical (IE historical) uncertainty in state-level polls
fielded **200 days** before the election. It may not be well-calibrated
to handle any additional error from the regression model used to “fill
in” averages in states without any or many polls. So take it (and the
rest of this exercise) as an imperfect guide to the electoral
environment, rather than the best or most robust model we could think
of.

**A note on forecasting:** The reason this is a “toy” model is because
it does not attempt to project movement in the polls between whatever
day it runs and election day. Instead, it just treats the polls as
uncertain readings of the future, assuming no change in means. But this
is an empirically flawed assumption. We know from history that polls
during and after conventions tend to over-state the party that most
recently nominated a candidate. A true *forecasting* model will adjust
for these historical patterns and project that the favored candidate’s
election-day polling margin will be smaller than it is on the model run
date. This is yet another reason you should treat this analysis with a
hefty dose of skepticism—at least until election day…

**A note on polls:** The purpose of this analysis is to determine what
we know *now* from the polls. But polls often err in predicting
elections. It is probably better to combine general election polls with
other indicators of election outcomes, such as the state of the economy
or presidential approval ratings. Fancier election models will do so.
This is yet another reason not to squint at the estimates here.

**A final reminder: this is not an official election forecast.** The
purpose of this repo is to help people understand how these forecasts
work, and to provide some forecasters with code to improve their
methods.

With all that out of the way, I guess we can proceed…

Automated report:
-----------------

![refresh\_readme](https://github.com/elliottmorris/toy-us-election-simulator/workflows/refresh_readme/badge.svg)

These graphs are updated hourly with new polls.

Last updated on **August 12, 2020 at 07:12 AM EDT.**

### National polling average

Joe Biden’s margin in national polls is **<span
style="color: #3498DB;">10.6</span>** percentage points. His margin
implied by state-level polls and the demographic regression is **<span
style="color: #3498DB;">9.7</span>** percentage points.

### State polling averages

The polling average in each state:

In map form….

![](README_files/figure-gfm/unnamed-chunk-2-1.png)<!-- -->

In table form…

**The twenty most competitive states:**

| State | Biden margin, uncertainty interval (%) | State | Biden margin, … (%) |
|:------|:---------------------------------------|:------|:--------------------|
| ME    | 11 \[-3, 24\]                          | GA    | 1 \[-13, 15\]       |
| MN    | 10 \[-4, 23\]                          | TX    | 0 \[-14, 14\]       |
| NV    | 9 \[-5, 22\]                           | IA    | 0 \[-14, 13\]       |
| WI    | 8 \[-6, 21\]                           | AK    | -4 \[-17, 10\]      |
| MI    | 8 \[-5, 22\]                           | MO    | -5 \[-18, 9\]       |
| PA    | 7 \[-7, 20\]                           | SC    | -5 \[-19, 8\]       |
| FL    | 6 \[-8, 19\]                           | MT    | -8 \[-21, 6\]       |
| AZ    | 4 \[-10, 17\]                          | KS    | -8 \[-22, 6\]       |
| NC    | 3 \[-11, 16\]                          | MS    | -11 \[-24, 3\]      |
| OH    | 1 \[-13, 14\]                          | LA    | -11 \[-25, 2\]      |

**The rest of the states:**

| State | Biden margin, uncertainty interval (%) | State | Biden margin, … (%) |
|:------|:---------------------------------------|:------|:--------------------|
| DC    | 80 \[66, 93\]                          | VA    | 12 \[-2, 25\]       |
| CA    | 37 \[23, 51\]                          | NH    | 12 \[-2, 25\]       |
| MA    | 32 \[18, 45\]                          | UT    | -12 \[-26, 2\]      |
| VT    | 31 \[17, 44\]                          | IN    | -12 \[-26, 2\]      |
| HI    | 31 \[18, 45\]                          | NE    | -13 \[-26, 1\]      |
| MD    | 29 \[15, 43\]                          | TN    | -15 \[-28, -1\]     |
| NY    | 26 \[12, 39\]                          | AR    | -16 \[-30, -2\]     |
| WA    | 26 \[12, 40\]                          | KY    | -16 \[-30, -3\]     |
| IL    | 22 \[8, 35\]                           | SD    | -16 \[-30, -3\]     |
| RI    | 21 \[8, 35\]                           | ID    | -18 \[-32, -5\]     |
| CT    | 20 \[7, 34\]                           | AL    | -19 \[-33, -5\]     |
| NJ    | 20 \[7, 34\]                           | ND    | -21 \[-35, -8\]     |
| OR    | 18 \[4, 32\]                           | OK    | -22 \[-35, -8\]     |
| DE    | 16 \[3, 30\]                           | WV    | -28 \[-41, -14\]    |
| CO    | 14 \[0, 28\]                           | WY    | -30 \[-43, -16\]    |
| NM    | 14 \[1, 28\]                           |       |                     |

### Changes in state averages relative to the national margin

This map shows where Biden and Trump have gained or lost ground in each
state, controlling for gains and losses nationally:

![](README_files/figure-gfm/unnamed-chunk-5-1.png)<!-- -->

### State win probabilities

The odds that either candidate wins a state they’re favored in, given
the polling error:

In map form…

![](README_files/figure-gfm/unnamed-chunk-6-1.png)<!-- -->

### Tipping-point states

The states that give the winner their 270th electoral college vote, and
how often that happens:

| State | Tipping point chance (%) | State | Tipping point chance (%) |
|:------|-------------------------:|:------|-------------------------:|
| FL    |                     19.3 | MO    |                      0.6 |
| PA    |                     10.7 | NJ    |                      0.6 |
| MI    |                      8.8 | AK    |                      0.4 |
| TX    |                      8.8 | CT    |                      0.3 |
| NC    |                      6.1 | DE    |                      0.3 |
| WI    |                      5.7 | IL    |                      0.3 |
| AZ    |                      5.5 | SC    |                      0.3 |
| OH    |                      5.4 | KS    |                      0.1 |
| VA    |                      5.4 | MS    |                      0.1 |
| MN    |                      4.9 | MT    |                      0.1 |
| GA    |                      4.4 | NY    |                      0.1 |
| NV    |                      3.0 | RI    |                      0.1 |
| CO    |                      2.1 | IN    |                      0.0 |
| ME    |                      1.7 | LA    |                      0.0 |
| IA    |                      1.5 | SD    |                      0.0 |
| NH    |                      1.5 | TN    |                      0.0 |
| NM    |                      1.2 | UT    |                      0.0 |
| OR    |                      0.7 | VT    |                      0.0 |

### Electoral college outcomes

The range of electoral college outcomes:

![](README_files/figure-gfm/unnamed-chunk-8-1.png)<!-- -->

#### Chance of the popular vote winner losing the electoral college majority

The chance that one party wins the national popular vote, but loses the
electoral college majority:

|                                                                           | Chance (%) |
|:--------------------------------------------------------------------------|-----------:|
| Democrats win the popular vote and electoral college                      |         93 |
| Democrats win the popular vote, but Republicans win the electoral college |          6 |
| Republicans win the popular vote and electoral college                    |          1 |
| Republicans win the popular vote, but Democrats win the electoral college |          0 |

The probability the Democrats win the national popular vote is 98.86%.

#### The divide between the electoral college and popular vote

We can quantify either party’s edge as the average across simulations of
Joe Biden’s margin in the tipping-point state and his margin nationally:

On average, the tipping point state is **<span
style="color: #3498DB;">2.6</span>** percentage points to the **<span
style="color: #3498DB;">right</span>** of the nation as a whole.

Endmatter
=========

I hope you learned something. You can find me on Twitter at
[@gelliottmorris](https://www.twitter.com/gelliottmorris) or my personal
website at [gelliottmorris.com](https://www.gelliottmorris.com/).

This content is licensed with the [MIT license](LICENSE).
