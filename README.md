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
bet you’d have better-than-replacement-level rates of success with it,
but I only wrote it for a fun coding exercise and to show people how
this sort of program works—so act accordingly.

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

Last updated on **September 21, 2020 at 06:14 AM EDT.**

### National polling average and popular vote prediction

Joe Biden’s margin in national polls is **<span
style="color: #3498DB;">8.4</span>** percentage points.

His margin implied by state-level polls and the demographic regression
is **<span style="color: #3498DB;">7.6</span>** percentage points.

This chart draws a trend for Biden’s implied national margin and plots
individual national polls alongside it. His implied national margin will
not always match the raw average of national polls.

![](README_files/figure-gfm/unnamed-chunk-2-1.png)<!-- -->

### State polling averages and vote prediction

The polling average in each state:

In map form….

![](README_files/figure-gfm/unnamed-chunk-3-1.png)<!-- -->

In table form…

**The twenty most competitive states:**

| State | Biden margin, uncertainty interval (%) | State | Biden margin, … (%) |
|:------|:---------------------------------------|:------|:--------------------|
| MN    | 9 \[-3, 21\]                           | GA    | 0 \[-11, 12\]       |
| MI    | 9 \[-2, 21\]                           | IA    | -2 \[-13, 10\]      |
| NV    | 7 \[-5, 18\]                           | OH    | -3 \[-14, 9\]       |
| NH    | 7 \[-5, 19\]                           | AK    | -3 \[-15, 9\]       |
| WI    | 7 \[-4, 19\]                           | SC    | -6 \[-17, 6\]       |
| AZ    | 6 \[-6, 17\]                           | MT    | -6 \[-18, 5\]       |
| PA    | 6 \[-5, 18\]                           | MO    | -7 \[-19, 4\]       |
| FL    | 4 \[-8, 16\]                           | KS    | -8 \[-20, 4\]       |
| NC    | 2 \[-10, 14\]                          | NE    | -9 \[-20, 3\]       |
| TX    | 0 \[-12, 12\]                          | LA    | -9 \[-21, 3\]       |

**The rest of the states:**

| State | Biden margin, uncertainty interval (%) | State | Biden margin, … (%) |
|:------|:---------------------------------------|:------|:--------------------|
| DC    | 75 \[63, 86\]                          | NM    | 13 \[1, 25\]        |
| MA    | 33 \[21, 45\]                          | CO    | 11 \[-1, 22\]       |
| CA    | 30 \[18, 41\]                          | MS    | -12 \[-23, 0\]      |
| HI    | 30 \[19, 42\]                          | UT    | -12 \[-24, -1\]     |
| VT    | 28 \[16, 39\]                          | TN    | -14 \[-25, -2\]     |
| MD    | 28 \[16, 40\]                          | SD    | -15 \[-26, -3\]     |
| NY    | 26 \[14, 37\]                          | IN    | -16 \[-27, -4\]     |
| WA    | 25 \[14, 37\]                          | ID    | -16 \[-28, -4\]     |
| CT    | 22 \[10, 34\]                          | ND    | -17 \[-29, -5\]     |
| NJ    | 21 \[10, 33\]                          | AL    | -18 \[-29, -6\]     |
| RI    | 20 \[8, 32\]                           | AR    | -19 \[-31, -7\]     |
| IL    | 19 \[7, 31\]                           | KY    | -19 \[-31, -8\]     |
| ME    | 16 \[4, 28\]                           | OK    | -23 \[-35, -11\]    |
| DE    | 16 \[5, 28\]                           | WY    | -24 \[-35, -12\]    |
| VA    | 14 \[3, 26\]                           | WV    | -27 \[-39, -15\]    |
| OR    | 13 \[1, 24\]                           |       |                     |

### State polling averages and vote prediction, over time:

In our simple polling model, Joe Biden’s projected election-day vote
margin in any state is equal to a combination of his polling average and
a projection based on the relationship between demographics and the
polls in other states. Accordingly, the chart below shows our estimate
of his support according to the polls and our demographic regression on
any given day—and it *also* represents our projection for his final
election-day vote. *(In other words, we don’t forecast any movement in
the race between now and election day. Although it is naive to assume
the race will remain static, it suits our educaitonal purposes with this
model.)*

![](README_files/figure-gfm/unnamed-chunk-6-1.png)<!-- -->

### State win probabilities

The odds that either candidate wins a state they’re favored in, given
the polling error:

In map form…

![](README_files/figure-gfm/unnamed-chunk-7-1.png)<!-- -->

### State win probabilities, over time:

*(Just for key states.)*

![](README_files/figure-gfm/unnamed-chunk-8-1.png)<!-- -->

### Tipping-point states

The states that give the winner their 270th electoral college vote, and
how often that happens:

| State | Tipping point chance (%) | State | Tipping point chance (%) |
|:------|-------------------------:|:------|-------------------------:|
| FL    |                     18.9 | NM    |                      0.9 |
| PA    |                     16.2 | IA    |                      0.7 |
| AZ    |                      9.6 | AK    |                      0.2 |
| MI    |                      8.4 | DE    |                      0.1 |
| WI    |                      7.8 | ME    |                      0.1 |
| TX    |                      6.4 | CT    |                      0.0 |
| NC    |                      6.0 | IL    |                      0.0 |
| MN    |                      5.8 | KS    |                      0.0 |
| NV    |                      4.7 | LA    |                      0.0 |
| NH    |                      3.9 | MO    |                      0.0 |
| CO    |                      3.4 | MT    |                      0.0 |
| GA    |                      2.9 | NE    |                      0.0 |
| OR    |                      1.6 | NJ    |                      0.0 |
| VA    |                      1.2 | RI    |                      0.0 |
| OH    |                      1.1 | SC    |                      0.0 |

### Electoral college outcomes

The range of electoral college outcomes:

![](README_files/figure-gfm/unnamed-chunk-10-1.png)<!-- -->

### Chance of winning the election, over time

![](README_files/figure-gfm/unnamed-chunk-11-1.png)<!-- -->

#### The divide between the electoral college and popular vote

The chance that one party wins the national popular vote, but loses the
electoral college majority:

|                                                                           | Chance (%) |
|:--------------------------------------------------------------------------|-----------:|
| Democrats win the popular vote and electoral college                      |         90 |
| Democrats win the popular vote, but Republicans win the electoral college |          7 |
| Republicans win the popular vote and electoral college                    |          3 |
| Republicans win the popular vote, but Democrats win the electoral college |          0 |

The overall probability that Joe Biden win the national popular vote is
96.46%. The overall probability that Joe Biden win the electoral college
majority is 89.92%.

**The gap between the popular vote and tipping-point state**

We can quantify either party’s edge as the average across simulations of
Joe Biden’s margin in the tipping-point state and his margin nationally:

On average, the tipping point state is **<span
style="color: #3498DB;">2.2</span>** percentage points to the **<span
style="color: #3498DB;">right</span>** of the nation as a whole.

But the actual divide could take on a host of other values:

![](README_files/figure-gfm/unnamed-chunk-13-1.png)<!-- -->

### Changes in state averages relative to the national margin

This map shows where Biden and Trump have gained or lost ground since
2016, relative to their gains/losses nationally:

![](README_files/figure-gfm/unnamed-chunk-14-1.png)<!-- -->

Endmatter
=========

I hope you learned something. You can find me on Twitter at
[@gelliottmorris](https://www.twitter.com/gelliottmorris) or my personal
website at [gelliottmorris.com](https://www.gelliottmorris.com/).

This content is licensed with the [MIT license](LICENSE).
