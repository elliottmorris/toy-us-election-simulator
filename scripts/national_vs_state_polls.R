# this file tests the predictive power of state-level polling averages vs
# state-level predictions from national polls + a state-level model
library(tidyverse)
library(lubridate)
library(politicaldata)

# download 538 archive
polls <- read_csv('https://raw.githubusercontent.com/fivethirtyeight/data/master/pollster-ratings/raw-polls.csv')

polls <- polls %>% filter(type_simple == 'Pres-G')

# limit to last week
polls <- polls %>%
  mutate(daystil = difftime(mdy(electiondate),mdy(polldate),units = 'days')) %>%
  filter(daystil<=21,location!='US')

# error on candidate one percent
polls <- polls %>%
  group_by(year,state=location) %>%
  summarise(poll_dem_two_party_share = mean(cand1_pct / (cand1_pct + cand2_pct)))

# modeled predictions
modeled <- read_csv('data/predicted_two_party_state_historical.csv')

# merge
preds <- left_join(modeled, polls, by = c("state", "year"))

# add results
results <- read_csv('data/potus_historical_results.csv') 

preds <- preds %>%
  left_join(results, by= c('state','year'))

# compare accuracies
preds %>%
  summarise(state_poll_rmse = sqrt(mean((poll_dem_two_party_share - dem_two_party_share)^2,na.rm=T)),
            national_model_rmse = sqrt(mean((dem_mean - dem_two_party_share)^2,na.rm=T)),
            state_poll_mae = mean(abs(poll_dem_two_party_share - dem_two_party_share),na.rm=T),
            national_model_mae = mean(abs(dem_mean - dem_two_party_share),na.rm=T)) %>%
  as.data.frame()

# graph
preds %>%
  setNames(.,c('state','year','Modeled vote share from national polls\n(RMSE = 3.3 percentage pts)','State polling average\n(RMSE = 2.5 percentage pts)','dem_two_party_share')) %>%
  mutate(year = as.character(year)) %>%
  gather(variable,value,3:4) %>%
  filter(state != 'DC') %>%
  ggplot(., aes(x=value,y=dem_two_party_share,label=state)) +
  geom_text(alpha=0.8) + 
  geom_abline() + 
  geom_smooth(method='lm',se=F,linetype=2) +
  facet_wrap(~variable) +
  labs(subtitle='Final state-level presidential election predictions, 2000-2016',
       x='Predicted Democratic share of the two-party vote',
       y='Actual Democratic share of the two-party vote') +
  scale_x_continuous(breaks=seq(0,1,0.1),labels=function(x){round(x*100)}) + 
  scale_y_continuous(breaks=seq(0,1,0.1),labels=function(x){round(x*100)}) +
  theme_minimal() +
  theme(panel.grid.minor = element_blank())



