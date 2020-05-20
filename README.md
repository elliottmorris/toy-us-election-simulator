# Toy US election simulator

This is nothing fancy. Just a simple election simulator based on national and state-level polling. The code in this repo will generate the graphs and statistics I shared here: https://twitter.com/gelliottmorris/status/1257331350618726400?s=20

I hope this code well help shed some light on basic methods for aggregating national and state polls, inferring electoral standings in states without a lot of data and simulating what might happen in the electoral college if polls lead us astray.

## Technical notes

The simulated error in this model is specified to capture the empirical (IE historical) uncertainty in state-level polls fielded 200 days before the election. It may not be well-calibrated to handle any additional error from the regression model used to "fill in" averages in states without any or many polls, so take it (and the rest of this exercise) with a grain of salt.