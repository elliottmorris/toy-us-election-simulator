# script to get RMSE for polls in states in the past month of the election
library(tidyverse)
library(lubridate)

# download archive
polls <- read_csv('https://raw.githubusercontent.com/fivethirtyeight/data/master/pollster-ratings/raw-polls.csv')

# polls since 2000
#polls <- polls %>% filter(year > 2000)

# only president, at state level
polls <- polls %>% 
  filter(type_simple == 'Pres-G',location!='US')

# limit to last week
polls <- polls %>%
  mutate(daystil = difftime(mdy(electiondate),mdy(polldate),units = 'days')) %>%
  filter(daystil<=7)

# change to two-party percentages 
#polls <- polls %>%
#  mutate(cand1_pct = cand1_pct/(cand1_pct+cand2_pct),
#         cand1_actual = cand1_actual/(cand1_actual+cand2_actual))

# error on candidate one percent
polls %>%
  group_by(year,location) %>%
  summarise(cand1_pct = mean(cand1_pct),
            cand2_pct = mean(cand2_pct),
            cand1_actual = unique(cand1_actual),
            cand2_actual = unique(cand2_actual)) %>%
  ungroup() %>%
  summarise(median_error = median(abs((cand1_actual-cand2_actual) - (cand1_pct-cand2_pct))),
            rmse = sqrt(mean(((cand1_actual-cand2_actual) - (cand1_pct-cand2_pct))^2)))


