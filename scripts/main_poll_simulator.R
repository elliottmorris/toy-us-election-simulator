library(tidyverse)
library(lubridate)
library(politicaldata)
library(pbapply)
library(parallel)
library(ggrepel)
library(caret)
library(glmnet)
library(kknn)
library(urbnmapr)
library(data.table)

num_sims <- 20000

# wrangle data ------------------------------------------------------------
message("Wrangling data...")
# weights
states2016 <- read_csv('data/2016.csv') %>%
  mutate(score = clinton_count / (clinton_count + trump_count),
         national_score = sum(clinton_count)/sum(clinton_count + trump_count),
         delta = score - national_score,
         share_national_vote = (total_count*(1+adult_pop_growth_2011_15))
         /sum(total_count*(1+adult_pop_growth_2011_15))) %>%
  arrange(state) 

state_weights <- c(states2016$share_national_vote / sum(states2016$share_national_vote))
names(state_weights) <- states2016$state

# read in the polls
url<- 'https://docs.google.com/spreadsheets/d/e/2PACX-1vQ56fySJKLL18Lipu1_i3ID9JE06voJEz2EXm6JW4Vh11zmndyTwejMavuNntzIWLY0RyhA1UsVEen0/pub?gid=0&single=true&output=csv'

all_polls <- read_csv(url)

head(all_polls)

# remove any polls if biden or trump blank
all_polls <- all_polls %>% filter(!is.na(biden),!is.na(trump))#, include == "TRUE")

all_polls <- all_polls %>%
  filter(mdy(end.date) >= (Sys.Date()-60) ) %>%  # all polls over last 2 months
  mutate(weight = sqrt(number.of.observations / mean(number.of.observations,na.rm=T)))

# how much should we weight regression by compared to polls?
# 1 = the weight of an average-sized poll
regression_weight <-  1
#sqrt((all_polls %>% filter(state != '--') %>% pull(number.of.observations) %>% mean * 0.5) / 
#       (all_polls %>% filter(state != '--') %>% pull(number.of.observations) %>% mean))

# average national and state polls
national_biden_margin <- all_polls %>%
  filter(state == '--',
         grepl('phone',tolower(mode))
  ) %>%
  summarise(mean_biden_margin = weighted.mean(biden-trump,weight)) %>%
  pull(mean_biden_margin)/100

state_averages <- all_polls %>%
  filter(state != '--') %>%
  group_by(state) %>%
  summarise(mean_biden_margin = weighted.mean(biden-trump,weight)/100,
            num_polls = n(),
            sum_weights = sum(weight,na.rm=T))

# get 2016 results
results <- politicaldata::pres_results %>% 
  filter(year == 2016) %>%
  mutate(clinton_margin = dem-rep) %>%
  select(state,clinton_margin)

# coefs for a simple model
coefs <- read_csv('data/state_coefs.csv')

# bind everything together
# make log pop density
state <- results %>%
  left_join(state_averages, by = "state") %>%
  mutate(dem_lean_2016 = clinton_margin - 0.021,
         dem_lean_2020_polls = mean_biden_margin - national_biden_margin) %>%
  left_join(coefs, by = "state")


# also create a dataset of all the state polls for the model
state_polls <- all_polls %>%
  filter(state != '--') %>%
  left_join(results, by = "state") %>%
  mutate(mean_biden_margin = biden_margin/100,
         sum_weights = weight,
         dem_lean_2016 = clinton_margin - 0.021,
         dem_lean_2020_polls = mean_biden_margin - national_biden_margin) %>%
  left_join(coefs, by = "state")


# model to fill in polling gaps -------------------------------------------
message("Training demographic regression model...")
# simple stepwise linear model with AIC selection
model <- step(lm(mean_biden_margin ~ clinton_margin + black_pct + college_pct + 
                   hisp_other_pct + median_age + pct_white_evangel + pop_density + 
                   white_pct + wwc_pct,
                 data = state %>%
                   select(mean_biden_margin,clinton_margin,black_pct,college_pct,
                          hisp_other_pct,median_age,pct_white_evangel,
                          pop_density,white_pct,wwc_pct,sum_weights) %>%
                   mutate_at(c('clinton_margin','black_pct','college_pct',
                               'hisp_other_pct','median_age','pct_white_evangel',
                               'pop_density','white_pct','wwc_pct'),
                             function(x){
                               (x - mean(x)) / sd(x)
                             }) %>%
                   na.omit(),
                 weight = sum_weights))

summary(model)

# glmnet model fit using caret
# training is the poll data
training <- state %>% 
  dplyr::select(state,mean_biden_margin,clinton_margin,black_pct,college_pct,
                hisp_other_pct,median_age,pct_white_evangel,
                pop_density,white_pct,wwc_pct,sum_weights) %>%
  mutate_at(c('clinton_margin','black_pct','college_pct',
              'hisp_other_pct','median_age','pct_white_evangel',
              'pop_density','white_pct','wwc_pct'),
            function(x){
              (x - mean(x)) / sd(x)
            }) %>% 
  na.omit()

# testing is the averaged data
testing <- state  %>% 
  dplyr::select(state,mean_biden_margin,clinton_margin,black_pct,college_pct,
                hisp_other_pct,median_age,pct_white_evangel,
                pop_density,white_pct,wwc_pct,sum_weights) %>%
  mutate_at(c('clinton_margin','black_pct','college_pct',
              'hisp_other_pct','median_age','pct_white_evangel',
              'pop_density','white_pct','wwc_pct'),
            function(x){
              (x - mean(x)) / sd(x)
            }) 

model <- train(mean_biden_margin ~ clinton_margin + black_pct + college_pct + 
                 hisp_other_pct + median_age + pct_white_evangel + pop_density + 
                 white_pct + wwc_pct,
               data = training,
               weights = sum_weights,
               method = "glmnet",
               metric = "RMSE",
               trControl = trainControl(method="LOOCV"),
               preProcess = c("center", "scale"),
               tuneLength = 20)

# look @ model
model

# or maybe we do kknn?
# model <- train.kknn(
#   formula = mean_biden_margin ~ clinton_margin + black_pct + college_pct + 
#     hisp_other_pct + median_age + pct_white_evangel + pop_density + 
#     white_pct + wwc_pct,
#   data = training,
#   kmax = 10,
#   kernel = c('optimal','guassian'),
#   scale = TRUE
# )

# make the projections
testing$proj_mean_biden_margin <- predict(object=model,newdata=testing)

# check predictions
ggplot(na.omit(testing), aes(x=mean_biden_margin,y=proj_mean_biden_margin,label=state)) +
  geom_text() + 
  geom_abline() + 
  geom_smooth(method='lm')

mean(abs(testing$proj_mean_biden_margin - testing$mean_biden_margin),na.rm=T)

# add to state data frame
state <- state %>%
  # append the predictions
  left_join(testing %>% dplyr::select(state,proj_mean_biden_margin), by = "state") %>%
  # make some mutations
  mutate(sum_weights = ifelse(is.na(sum_weights),0,sum_weights),
         mean_biden_margin = ifelse(is.na(mean_biden_margin),999,mean_biden_margin))  %>%
  mutate(mean_biden_margin_hat = #proj_mean_biden_margin
           (mean_biden_margin * (sum_weights/(sum_weights+regression_weight)) ) +
           (proj_mean_biden_margin * (regression_weight/(sum_weights+regression_weight)) )
  ) %>%
  mutate(mean_biden_margin = ifelse(mean_biden_margin==999,NA,mean_biden_margin))

# plot final prediction against data
ggplot(na.omit(state), aes(mean_biden_margin, mean_biden_margin_hat, label=state)) +
  geom_text(aes(size=num_polls)) + 
  geom_abline() + 
  geom_smooth(method='lm')


# adjust predictions for poll selection bias ------------------------------
clinton_margin_in_polled_states <- state %>% 
  filter(!is.na(mean_biden_margin)) %>% 
  select(state,clinton_margin,mean_biden_margin) %>%
  left_join(enframe(state_weights,'state','state_weight'), by = "state") %>%
  mutate(state_weight = state_weight / sum(state_weight)) %>%
  summarise(average_clinton_margin = 
              weighted.mean(clinton_margin,state_weight)) %>%
  pull(average_clinton_margin)

clinton_margin_overall <- state %>% 
  select(state,clinton_margin,mean_biden_margin) %>%
  left_join(enframe(state_weights,'state','state_weight'), by = "state") %>%
  summarise(average_clinton_margin = 
              weighted.mean(clinton_margin,state_weight)) %>%
  pull(average_clinton_margin)

# the differences here are interesting
# but we don't actually need to perform a correction
# because clinton margin is a variable in the regression

# adjust state-level polls and predictions to polled national margin ------
# for now, no.... aggregates of state polls out-performed national 
# polls in 2008 and 2012 -- don't want to overreact to 2016
og_national_biden_margin <- national_biden_margin

adj_national_biden_margin <-  national_biden_margin # weighted.mean(state$mean_biden_margin_hat,state_weights)

state$mean_biden_margin_hat <-  state$mean_biden_margin_hat - (adj_national_biden_margin - national_biden_margin)

# save new biden national margin
national_biden_margin <- weighted.mean(state$mean_biden_margin_hat,state_weights)

national_biden_margin

# generate new state lean variable based on adjusted biden national margin
state$dem_lean_2020 <-  state$mean_biden_margin_hat - national_biden_margin 

state_evs <- read_csv('data/state_evs.csv')

# clean up estimates
final <- state %>%
  dplyr::select(state,region,clinton_margin,dem_lean_2016,
         mean_biden_margin = mean_biden_margin_hat,
         dem_lean_2020_polls,
         dem_lean_2020, 
         num_polls,
         pop_density,
         wwc_pct) %>%
  mutate(shift = dem_lean_2020 - dem_lean_2016)

final <- final %>%
  left_join(state_evs)

# calc shift from 2016 to 2020 --------------------------------------------
# plot
final %>% 
  filter(abs(clinton_margin) < 0.1) %>% # num_polls > 0
  ggplot(., aes(y=reorder(state,shift),x=shift,
                col = clinton_margin > 0)) + 
  #geom_point() +
  geom_vline(xintercept = 0) + 
  geom_label(aes(label = state,size=ev)) +
  scale_size(range=c(2,6)) + 
  scale_x_continuous(breaks=seq(-1,1,0.01),
                     labels = function(x){round(x*100)}) +
  scale_color_manual(values=c('TRUE'='blue','FALSE'='red')) +
  theme_minimal() + 
  theme(panel.grid.minor = element_blank(),
        legend.position = 'none',
        axis.text.y=element_blank(),
        axis.title.y=element_blank(),
        axis.ticks.y=element_blank()) +
  labs(subtitle='Swing toward Democrats in relative presidential vote margin\nSized by electoral votes',
       x='Biden state margin relative to national margin\nminus Clinton state margin relative to national margin')

# as a map
# plot
swing.map.gg <- urbnmapr::states %>%
  left_join(final %>% rename(state_abbv = state)) %>%
  filter(state_abbv != 'DC') %>%
  ggplot(aes(x=long,y=lat,group=group,
             fill = shift*100)) +
  geom_polygon(col='gray40')  + 
  coord_map("albers",lat0=39, lat1=45) +
  scale_fill_gradient2(name='Swing toward Democrats in relative presidential vote margin*',high='#3498DB',low='#E74C3C',mid='gray98',midpoint=0,
                       guide = 'legend') +
  labs(caption='*Biden state margin relative to national margin minus Clinton state margin relative to national margin') +
  guides('fill'=guide_legend(nrow=1,title.position = 'top')) +
  theme_void() + 
  theme(legend.position = 'top',
        plot.caption = element_text(hjust=0.2,margin=margin(30,30,30,30)))


# plot relationswhip between shift in lean with wwc
final %>% 
  filter(state != 'DC') %>%
  ggplot(., aes(x=wwc_pct,y=shift,
                col = clinton_margin > 0,group=NA)) + 
  geom_label(aes(label = state,size=ev)) +
  geom_smooth(method='lm')

# any relationship with urbanicity?
final %>%
  filter(state != 'DC') %>%
  ggplot(.,aes(x=pop_density,y=mean_biden_margin,label=state,
               col = clinton_margin > 0,group=NA)) + 
  geom_text_repel() + 
  geom_smooth(method='lm',col='black',linetype=2) + 
  scale_y_continuous(breaks=seq(-1,1,0.05), labels = function(x){round(x*100)}) +
  scale_color_manual(values=c('TRUE'='blue','FALSE'='red')) +
  theme_minimal() + 
  theme(panel.grid.minor = element_blank(),
        legend.position = 'none') +
  labs(subtitle='2020 Biden vote margin*',
       x='Number of people living within 5 miles of each resident (logged)',
       y='',
       caption='*2020 Biden margin is an average of the polls and a regression model\nthat predicts poll margins with state-level demographics')

# tipping point state?
final %>%
  arrange(desc(mean_biden_margin)) %>%
  mutate(cumulative_ev = cumsum(ev)) %>%
  filter(cumulative_ev >= 270) %>% filter(row_number() == 1)  

final %>%
  arrange(desc(mean_biden_margin)) %>%
  mutate(cumulative_ev = cumsum(ev)) %>%
  filter(cumulative_ev >= 270) %>% filter(row_number() == 1)  %>%
  pull(mean_biden_margin) -  national_biden_margin


# toy simulations ---------------------------------------------------------
message("Simulating the election...")
# errors
national_error <- (0.04)
regional_error <- (0.04)
state_error <- (0.04)

sqrt(national_error^2 + regional_error^2 + state_error^2) # this is the total standard deviation on vote margin

# sims
national_errors <- rnorm(num_sims, 0, national_error)
regional_errors <- replicate(num_sims,rnorm(length(unique(final$region)), 0, regional_error))
state_errors <- replicate(num_sims,rnorm(51, 0, state_error))

# actual sims

#' Simulate polling errors.
#'
#' @param state_errors Matrix of simulated state polling errors. (num_states x num_sims)
#' @param regional_errors Matrix of simulated regional polling errors. (num_regions x num_sims)
#' @param national_errors Numeric vector of simulated national polling errors. Length is num_sims.
#' @param state_region Data frame of states and their regions.
#'
#' @return A data frame of simulated polling errors with the following columns: sim, state, region, state_error,
#' regional_error, national_error. One row per simulation.
#'
simulate_polling_errors <- function(state_errors, regional_errors, national_errors, state_region) {
  states <- unique(state_region$state)

  regions <- unique(state_region$region)

  state_errors <- state_errors %>%
    t() %>%
    as_tibble(.name_repair = "minimal") %>%
    set_names(~ states) %>%
    mutate(sim = row_number()) %>%
    pivot_longer(-sim, names_to = "state", values_to = "state_error")

  regional_errors <- regional_errors %>%
    t() %>%
    as_tibble(.name_repair = "minimal") %>%
    set_names(~ regions) %>%
    mutate(sim = row_number()) %>%
    pivot_longer(-sim, names_to = "region", values_to = "regional_error")

  national_errors <-
    tibble(sim = 1:length(national_errors), national_error = national_errors)

  state_region %>%
    left_join(state_errors, by = "state") %>%
    left_join(regional_errors, by = c("region", "sim")) %>%
    left_join(national_errors, by = "sim") %>%
    select(sim, state, region, state_error, regional_error, national_error)
}

state_region <- final %>%
  ungroup() %>%
  select(state, region) %>%
  distinct()

simulated_polling_errors <- simulate_polling_errors(state_errors, regional_errors, national_errors, state_region)

sims <- simulated_polling_errors %>%
  left_join(final %>% select(state, dem_lean_2020), by = "state") %>%
  mutate(proj_biden_margin = dem_lean_2020 + national_biden_margin,
         error = state_error + regional_error + national_error,
         sim_biden_margin = proj_biden_margin + error) %>%
  group_by(state) %>%
  mutate(draw = row_number()) %>%
  left_join(state_evs, by='state') %>%
  left_join(enframe(state_weights, 'state', 'weight'), by = "state") %>%
  group_by(draw) %>%
  mutate(dem_nat_pop_margin = weighted.mean(sim_biden_margin, weight)) %>%
  select(state, sim_biden_margin, draw, ev, weight, dem_nat_pop_margin)

# prior implementation
state_and_national_errors <- pblapply(1:length(national_errors),
                                      cl = parallel::detectCores() - 1,
                                      function(x){
                                        state_region <- final %>%
                                          mutate(proj_biden_margin = dem_lean_2020 + national_biden_margin) %>%
                                          dplyr::select(state, proj_biden_margin) %>%
                                          left_join(final %>% 
                                                      ungroup() %>%
                                                      dplyr::select(state,region) %>% distinct,
                                                    by = "state") %>%
                                          left_join(tibble(region = unique(final$region),
                                                           regional_error = regional_errors[,x]), 
                                                    by = "region") %>%
                                          left_join(tibble(state = unique(final$state),
                                                           state_error = state_errors[,x]),
                                                    by = "state")
                                        
                                        state_region %>%
                                          mutate(error = state_error + regional_error + national_errors[x]) %>% 
                                          mutate(sim_biden_margin = proj_biden_margin + error) %>%
                                          dplyr::select(state,sim_biden_margin)
                                      })

# check the standard deviation (now in margin)
state_and_national_errors %>%
  do.call('bind_rows',.) %>%
  group_by(state) %>%
  summarise(sd = sd(sim_biden_margin)) %>% 
  pull(sd) %>% mean

# add electoral votes and pop vote to the simulations
sims_old <- state_and_national_errors %>%
  do.call('bind_rows',.) %>%
  group_by(state) %>%
  mutate(draw = row_number()) %>%
  ungroup() %>%
  left_join(states2016 %>% dplyr::select(state,ev), by='state') %>%
  left_join(enframe(state_weights,'state','weight'), by = "state") %>%
  group_by(draw) %>%
  mutate(dem_nat_pop_margin = weighted.mean(sim_biden_margin,weight))

# Verify new implementation produces the same results
all_equal(sims_old, sims)

message("The rest of the script is charts, etc...")

# what is the pop vote range?
dem_nat_pop_margin <- sims %>%
  group_by(draw) %>%
  summarise(dem_nat_pop_margin = unique(dem_nat_pop_margin)) %>%
  pull(dem_nat_pop_margin)

dem_pop_vote_prob <- mean(dem_nat_pop_margin>0)

# extract state-level data
state_probs <- sims %>%
  group_by(state_abbv = state) %>%
  summarise(mean_biden_margin = mean(sim_biden_margin,na.rm=T),
            se_biden_margin = sd(sim_biden_margin,na.rm=T),
            ev = unique(ev),
            prob = mean(sim_biden_margin > 0,na.rm=T)) %>%
  ungroup() %>%
  arrange(desc(mean_biden_margin)) %>% 
  mutate(cumulative_ev = cumsum(ev)) 

# graph mean estimates by state
margin_map.gg <- urbnmapr::states %>%
  left_join(state_probs) %>%
  filter(state_abbv != 'DC') %>%
  ggplot(aes(x=long,y=lat,group=group,
             fill = mean_biden_margin*100)) +
  geom_polygon(col='gray40')  + 
  coord_map("albers",lat0=39, lat1=45) +
  scale_fill_gradient2(name='Biden vote margin',high='#3498DB',low='#E74C3C',mid='gray98',midpoint=0,
                       guide = 'legend') +
  guides('fill'=guide_legend(nrow=1,title.position = 'top',title.hjust = 0.5)) +
  theme_void() + 
  theme(legend.position = 'top')

margin_map.gg

# table form  -- close states
sumary_table.close <- state_probs %>%
  arrange(abs(mean_biden_margin)) %>% 
  head(20) %>%
  mutate(upper = round((mean_biden_margin + se_biden_margin*1.96)*100),
         lower = round((mean_biden_margin - se_biden_margin*1.96)*100),
         mean_biden_margin = round(mean_biden_margin*100)) %>%
  arrange(desc(mean_biden_margin)) %>% 
  mutate(txt = sprintf('%s [%s, %s]',mean_biden_margin,lower,upper)) %>%
  dplyr::select(state_abbv,txt) 

margin.kable.close <- left_join(sumary_table.close %>%
                            head(ceiling(nrow(.)/2)) %>%
                            mutate(row_number = row_number()),
                            sumary_table.close %>%
                            tail(floor(nrow(.)-(nrow(.)/2))) %>%
                            mutate(row_number = row_number()),
                          by='row_number') %>% 
  select(-row_number)

margin.kable.close[is.na(margin.kable.close)] <- ' '

margin.kable.close <- margin.kable.close %>%
  setNames(.,c('State','Biden margin, uncertainty interval (%)','State','Biden margin, ... (%)')) %>%
  knitr::kable(.)

# table form  -- not  states
sumary_table.not_close <- state_probs %>%
  arrange(abs(mean_biden_margin)) %>% 
  tail(31) %>%
  mutate(upper = round((mean_biden_margin + se_biden_margin*1.96)*100),
         lower = round((mean_biden_margin - se_biden_margin*1.96)*100),
         mean_biden_margin = round(mean_biden_margin*100)) %>%
  arrange(desc(mean_biden_margin)) %>% 
  mutate(txt = sprintf('%s [%s, %s]',mean_biden_margin,lower,upper)) %>%
  dplyr::select(state_abbv,txt) 

margin.kable.not_close <- left_join(sumary_table.not_close %>%
                                  head(ceiling(nrow(.)/2)) %>%
                                  mutate(row_number = row_number()),
                                sumary_table.not_close %>%
                                  tail(floor(nrow(.)-(nrow(.)/2))) %>%
                                  mutate(row_number = row_number()),
                                by='row_number') %>% 
  select(-row_number)

margin.kable.not_close[is.na(margin.kable.not_close)] <- ' '

margin.kable.not_close <- margin.kable.not_close %>%
  setNames(.,c('State','Biden margin, uncertainty interval (%)','State','Biden margin, ... (%)')) %>%
  knitr::kable(.)


# graph win probabilities
win_probs_map <- urbnmapr::states %>%
  left_join(state_probs) %>%
  ggplot(aes(x=long,y=lat,group=group,fill=prob*100)) +
  geom_polygon(col='gray40')  + 
  coord_map("albers",lat0=39, lat1=45) +
  scale_fill_gradient2(name='Democratic win probability',high='#3498DB',low='#E74C3C',mid='gray98',midpoint=50,
                       limits = c(0,100)) +
  theme_void() + 
  theme(legend.position = 'top')

win_probs_map

# electoral vote histogram
ev.histogram <- sims %>%
  group_by(draw) %>%
  summarise(dem_ev = sum(ev * (sim_biden_margin > 0))) %>%
  ggplot(.,aes(x=dem_ev,fill=dem_ev >= 270)) +
  geom_histogram(binwidth=1) + 
  scale_fill_manual(values=c('TRUE'='blue','FALSE'='red')) +
  scale_y_continuous(labels = function(x){paste0(round(x / max(sims$draw)*100,2),'%')},
                     expand = expansion(mult = c(0, 0.2))) +
  labs(x='Democratic electoral votes',y='Probability') +
  theme_minimal() + 
  theme(legend.position = 'none') +
  labs(subtitle = sprintf('p(Biden win) = %s',
                          sims %>%
                            group_by(draw) %>%
                            summarise(dem_ev = sum(ev * (sim_biden_margin > 0))) %>%
                            ungroup() %>%
                            summarise(dem_ev_majority = round(mean(dem_ev >=270),2)) %>%
                            pull(dem_ev_majority)))

ev.histogram

# scenarios
scenarios.kable <- sims %>%
  group_by(draw) %>%
  summarise(dem_ev = sum(ev * (sim_biden_margin > 0)),
            dem_nat_pop_margin = unique(dem_nat_pop_margin)) %>%
  mutate(scenario = 
           case_when(dem_ev >= 270 & dem_nat_pop_margin > 0 ~ 'Democrats win the popular vote and electoral college',
                     dem_ev >= 270 & dem_nat_pop_margin < 0 ~ 'Republicans win the popular vote, but Democrats win the electoral college',
                     dem_ev <  270 & dem_nat_pop_margin > 0 ~ 'Democrats win the popular vote, but Republicans win the electoral college',
                     dem_ev <  270 & dem_nat_pop_margin < 0 ~ 'Republicans win the popular vote and electoral college',
           )) %>%
  group_by(scenario) %>%
  summarise(chance = n()) %>%
  mutate(chance = round(chance / sum(chance)*100)) %>%
  setNames(.,c('','Chance (%)')) %>%
  knitr::kable()


# tipping point state, maps -----------------------------------------------
# calc the avg tipping point
tipping_point <- pblapply(1:max(sims$draw),
                          cl = parallel::detectCores() - 1,
                          function(x){
                            temp <- sims[sims$draw==x,]
                            
                            if(temp$dem_nat_pop_margin > 0){
                              temp <- temp %>% arrange(desc(sim_biden_margin))
                            }else{
                              temp <- temp %>% arrange(sim_biden_margin)
                            }
                            
                            return(temp)
                          }) 

tipping_point <- tipping_point %>%
  rbindlist() %>%
  ungroup()


# state-level correlations?
tipping_point %>%
  dplyr::select(draw,state,sim_biden_margin) %>%
  spread(state,sim_biden_margin) %>%
  dplyr::select(-draw) %>%
  cor 

# what is the tipping point
tipping_point %>%
  group_by(draw) %>%
  mutate(cumulative_ev = cumsum(ev)) %>%
  filter(cumulative_ev >= 270) %>%
  filter(row_number() == 1) %>% 
  group_by(state) %>%
  summarise(prop = n()) %>%
  mutate(prop = round(prop / sum(prop)*100,1)) %>%
  arrange(desc(prop)) %>% filter(prop>1) %>% as.data.frame()

tipping_point.kable <- left_join(tipping_point %>%
            group_by(draw) %>%
            mutate(cumulative_ev = cumsum(ev)) %>%
            filter(cumulative_ev >= 270) %>%
            filter(row_number() == 1) %>% 
            group_by(state) %>%
            summarise(prop = n()) %>%
            mutate(prop = round(prop / sum(prop)*100,1)) %>%
            arrange(desc(prop))  %>% 
            head(nrow(.)/2) %>%
            mutate(row_number = row_number()),
          tipping_point %>%
            group_by(draw) %>%
            mutate(cumulative_ev = cumsum(ev)) %>%
            filter(cumulative_ev >= 270) %>%
            filter(row_number() == 1) %>% 
            group_by(state) %>%
            summarise(prop = n()) %>%
            mutate(prop = round(prop / sum(prop)*100,1)) %>%
            arrange(desc(prop))  %>% 
            tail(nrow(.)-(nrow(.)/2))%>%
            mutate(row_number = row_number()),
          by='row_number') %>% 
  select(-row_number) %>%
  setNames(.,c('State','Tipping point chance (%)','State','Tipping point chance (%)')) %>%
  knitr::kable(.)

# ev-popvote divide?
ev.popvote.divide <- tipping_point %>%
  group_by(draw) %>%
  mutate(cumulative_ev = cumsum(ev)) %>%
  filter(cumulative_ev >= 270) %>%
  filter(row_number() == 1)  %>%
  mutate(diff =  sim_biden_margin - dem_nat_pop_margin) %>%
  pull(diff) %>% mean # hist(breaks=100)

ev.popvote.divide

# ec - popular vote gap ---------------------------------------------------
results <- read_csv('data/potus_historical_results.csv')

# apply the infaltor from multi- to two-party vote
margin_inflator <- all_polls %>%
  filter(state != '--') %>%
  mutate(two_party_margin = (biden / (biden + trump)) - (trump / (biden + trump)),
         biden_margin = (biden - trump)/100) %>%
  summarise(margin_inflator = mean(two_party_margin / biden_margin,na.rm=T)) %>% 
  pull(margin_inflator)

# bind with averages
results <- results %>%
  bind_rows(state_probs %>%
              select(state = state_abbv,
                     dem_two_party_share = mean_biden_margin) %>%
              mutate(year = 2020,
                     dem_two_party_share = dem_two_party_share * margin_inflator,
                     dem_two_party_share = 0.5 + dem_two_party_share/2)) 


# data frame with electoral votes
historical_evs <- read_csv('data/state_evs_historical.csv')


results <- results %>%
  left_join(historical_evs) %>%
  na.omit() %>%
  mutate(# how many evs total?
    total_evs = case_when(year < 1960 ~ 531,
                          year == 1960 ~ 537,
                          year > 1960 ~ 538),
    # how many evs to win?
    evs_to_win = case_when(year < 1960 ~ 266,
                           year == 1960 ~ 269,
                           year > 1960 ~ 270)
    
  )

# add usa
usa <- read_csv('data/nationwide_potus_results.csv') %>% filter(State == 'Nationwide')
usa <- usa %>%
  gather(year,vote,2:ncol(.)) %>% 
  mutate(party = gsub("[^a-zA-Z]","",year),
         year = gsub("[a-zA-Z]","",year)) %>%
  group_by(State,year) %>%
  spread(party,vote) %>%
  mutate(dem_two_party_share_national = Dem / (Dem + Rep)) %>%
  as.data.frame() %>%
  ungroup() %>%
  dplyr::select(state=State,year,dem_two_party_share_national) %>%
  mutate(year = as.numeric(year)) %>%
  dplyr::select(-state)

results <- results %>%
  left_join(usa)

results <- results %>%
  group_by(year) %>%
  arrange(year,desc(dem_two_party_share)) %>%
  mutate(cumulative_ev = cumsum(ev)) %>%
  filter(cumulative_ev >= evs_to_win) %>%
  filter(row_number()  == 1) %>%
  mutate(dem_two_party_share_national = ifelse(year == 2020, 
                                               0.5 + (national_biden_margin * margin_inflator)/2,
                                               dem_two_party_share_national)) %>%
  na.omit()  %>%
  ungroup()

results %>%
  filter(year >= 1972) %>%
  mutate(lean = dem_two_party_share - dem_two_party_share_national,
         year = fct_reorder(as.character(year),-year)) %>%
  ggplot(.,aes(x=year,y=lean)) +
  geom_col() + 
  theme_minimal() + 
  coord_flip()

message("All done!")



