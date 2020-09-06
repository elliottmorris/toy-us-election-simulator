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


# setup ------------------- \\
## MASTER VARIABLES
# run date?
RUN_DATE <- as_date(ymd('2016-11-08')) #as_date(Sys.Date()) 

# this much daily sd in election polls
DAILY_SD <- 0.005773503
DAILY_SD * sqrt(300)

# number of simulations to run
NUM_SIMS <- 20000

# number of cores to use
NUM_CORES <- min(6, parallel::detectCores())

# whether to burn all the models up and start over
REDO_ALL_MODELS <- FALSE

## data
# read in the polls
all_polls <- read_csv('data/all_polls_2016.csv')

# impose a master filter over all modes
all_polls <- all_polls %>%
  filter(grepl('phone|online',tolower(mode)),
         population %in% c("Likely Voters","Registered Voters","Adults")) 

# sample size adjustments
all_polls$number.of.observations = pmin(all_polls$number.of.observations,1500)
all_polls <- all_polls %>%
  mutate(number.of.observations = ifelse(is.na(number.of.observations),
                                         mean(number.of.observations,na.rm=T),
                                         number.of.observations))
any(is.na(all_polls$number.of.observations))

# row for dem candidate margin
all_polls <- all_polls %>% 
  mutate(clinton_margin = clinton - trump)

# only one entry for pollster (sometimes we get RV and LV duplicates)
all_polls <- all_polls %>%
  group_by(state,pollster,end.date) %>%
  mutate(priority = case_when(population == 'Likely Voters' ~ 1,
                              population == 'Registered Voters' ~ 2,
                              population == 'Adults' ~ 3
                              ) ) %>%
  arrange(state,pollster,end.date,priority) %>%
  filter(row_number() == 1) %>%
  ungroup()

# save to new object
todays_polls <- all_polls

# read in state voter weights
states2012 <- read_csv('data/2012.csv') %>%
  mutate(score = obama_count / (obama_count + romney_count),
         national_score = sum(obama_count)/sum(obama_count + romney_count),
         delta = score - national_score,
         share_national_vote = (total_count*(1+adult_pop_growth_2011_15))
         /sum(total_count*(1+adult_pop_growth_2011_15))) %>%
  arrange(state) 

state_weights <- c(states2012$share_national_vote / sum(states2012$share_national_vote))
names(state_weights) <- states2012$state


# simulate the election as of today ---------------------------------------

#' function to repeat the above for a given date
#' @param RUN_DATE the date we're running on
#' @param all_polls the raw polls read from the google sheet without any wrangling yet
#' @param DAILY_SD the daily standard deviation in the random walk in the polls 

simulation_election_day_x <- function(RUN_DATE, todays_polls, DAILY_SD){
  message(sprintf("Simulating the election for %s....", RUN_DATE))
  
  # days til the election?
  days_til_election <- as.numeric(ymd('2016-11-08') - RUN_DATE)
  start_date <- ymd("2016-01-01") # min(todays_polls$date)
  
  
  # wrangle polls -----------------------------------------------------------
  todays_polls <- todays_polls %>% 
    filter(as_date(as_datetime(todays_polls$entry.date.time..et.)) <= RUN_DATE) %>%
    mutate(date = as_date(end.date))
  
  head(todays_polls)
  
  # remove any polls if clinton or trump blank
  todays_polls <- todays_polls %>% filter(!is.na(clinton),!is.na(trump))#, include == "TRUE")
  
  todays_polls <- todays_polls %>%
    mutate(weight = sqrt(number.of.observations / mean(number.of.observations,na.rm=T)))
  
  # how much should we weight regression by compared to polls?
  # 1 = the weight of an average-sized poll
  regression_weight <-  3 # so 5 is the weight of five polls
  # sqrt((all_polls %>% filter(state != '--') %>% pull(number.of.observations) %>% mean * 0.5) /
  #      (all_polls %>% filter(state != '--') %>% pull(number.of.observations) %>% mean))
  
  
  # get rolling average of national polls -----------------------------------
  
  # average national and state polls
  # should weight according to sample size and recency
  # we could be more complicated about this, but that's not necessary... yet...
  
  # avg overy day
  national_poll_average <- lapply(as_date(start_date:RUN_DATE),
                                  function(RUN_DATE_MOD){
                                    
                                    national_clinton_margin_MOD <- todays_polls %>%
                                      mutate(date_entered = as_date(as_datetime(todays_polls$entry.date.time..et.)) ) %>%
                                      filter(date_entered <= RUN_DATE_MOD) %>%
                                      filter(state == '--') %>%
                                      mutate(decayed_weight = exp( as.numeric(RUN_DATE_MOD - ymd(end.date))*-0.05)) %>%
                                      summarise(mean_clinton_margin = weighted.mean(clinton-trump,weight*decayed_weight,na.rm=T)) %>%
                                      pull(mean_clinton_margin)/100
                                    
                                    tibble(date = RUN_DATE_MOD,
                                           national_clinton_margin = national_clinton_margin_MOD)
                                    
                                  }) %>% bind_rows
  
  ggplot(national_poll_average, aes(x=date,y=national_clinton_margin)) +
    geom_line()  +
    geom_point(data =  todays_polls %>%
                 filter(as_date(as_datetime(todays_polls$entry.date.time..et.)) <= RUN_DATE) %>%
                 filter(state == '--') %>%
                 mutate(clinton_margin = (clinton-trump)/100),
               aes(x=date,y=clinton_margin),alpha=0.2)
  
  # now filter dates
  todays_polls <- todays_polls %>% filter(ymd(end.date) >= start_date)
  
  # get the last one for later on
  national_clinton_margin <- last(national_poll_average$national_clinton_margin)
  
  # now trend line adjust the polls
  national_poll_average_deltas <- national_poll_average %>% 
    mutate(national_clinton_margin_delta = last( national_clinton_margin) - national_clinton_margin)
  
  state_averages <- todays_polls %>%
    filter(state != '--') %>%
    # trend line adjust
    left_join(national_poll_average_deltas) %>%
    mutate(clinton_margin = (clinton-trump) + national_clinton_margin_delta) %>%
    # average
    group_by(state) %>%
    mutate(decayed_weight = exp( as.numeric(RUN_DATE - ymd(end.date))*-0.05)) %>%
    summarise(mean_clinton_margin = weighted.mean(clinton_margin,weight*decayed_weight,na.rm=T)/100,
              num_polls = n(),
              sum_weights = sum(weight,na.rm=T))
  
  # get 2012 results
  results <- politicaldata::pres_results %>% 
    filter(year == 2012) %>%
    mutate(obama_margin = dem-rep) %>%
    select(state,obama_margin)
  
  # coefs for a simple model
  coefs <- read_csv('data/state_coefs.csv')
  
  # bind everything together
  # make log pop density
  state <- results %>%
    left_join(state_averages, by = "state") %>%
    mutate(dem_lean_2012 = obama_margin - 0.039,
           dem_lean_2016_polls = mean_clinton_margin - national_clinton_margin) %>%
    left_join(coefs, by = "state")
  
  
  # also create a dataset of all the state polls for the model
  state_polls <- todays_polls %>%
    filter(state != '--') %>%
    left_join(results, by = "state") %>%
    mutate(mean_clinton_margin = clinton_margin/100,
           sum_weights = weight,
           dem_lean_2012 = obama_margin - 0.039,
           dem_lean_2016_polls = mean_clinton_margin - national_clinton_margin) %>%
    left_join(coefs, by = "state")
  
  
  # model to fill in polling gaps -------------------------------------------
  
  # simple stepwise linear model with AIC selection
  stepwise_model <- step(lm(mean_clinton_margin ~  black_pct + college_pct + 
                              hisp_other_pct + pct_white_evangel + pop_density + 
                              white_pct + wwc_pct,
                            data = state %>%
                              select(mean_clinton_margin,obama_margin,black_pct,college_pct,
                                     hisp_other_pct,median_age,pct_white_evangel,
                                     pop_density,white_pct,wwc_pct,sum_weights) %>%
                              mutate_at(c('black_pct','college_pct',
                                          'hisp_other_pct','median_age','pct_white_evangel',
                                          'pop_density','white_pct','wwc_pct'),
                                        function(x){
                                          (x - mean(x)) / sd(x)
                                        }) %>%
                              na.omit(),
                            weight = sum_weights))
  
  summary(stepwise_model)
  
  # glmnet model fit using caret
  # training is the poll data
  training <- state %>% 
    dplyr::select(state,mean_clinton_margin,black_pct,college_pct,
                  hisp_other_pct,median_age,pct_white_evangel,
                  pop_density,white_pct,wwc_pct,sum_weights) %>%
    mutate_at(c('black_pct','college_pct',
                'hisp_other_pct','median_age','pct_white_evangel',
                'pop_density','white_pct','wwc_pct'),
              function(x){
                (x - mean(x)) / sd(x)
              }) %>% 
    na.omit()
  
  # testing is the averaged data
  testing <- state  %>% 
    dplyr::select(state,mean_clinton_margin,black_pct,college_pct,
                  hisp_other_pct,median_age,pct_white_evangel,
                  pop_density,white_pct,wwc_pct,sum_weights) %>%
    mutate_at(c('black_pct','college_pct',
                'hisp_other_pct','median_age','pct_white_evangel',
                'pop_density','white_pct','wwc_pct'),
              function(x){
                (x - mean(x)) / sd(x)
              }) 
  
  glmnet_model <- train(mean_clinton_margin ~  black_pct + college_pct + 
                          hisp_other_pct + pct_white_evangel + pop_density + 
                          white_pct + wwc_pct,
                        data = training,
                        weights = sum_weights,
                        method = "glmnet",
                        metric = "RMSE",
                        trControl = trainControl(method="LOOCV"),
                        preProcess = c("center", "scale"),
                        tuneLength = 10)
  
  glmnet_model
  
  
  # combine predictions from the two models
  preds <- testing %>%
    mutate(aic_pred = predict(object=stepwise_model,newdata=.),
           glmnet_pred = predict(object=glmnet_model,newdata=testing)) %>%
    mutate(pred = (aic_pred + glmnet_pred)/2) %>%
    pull(pred)
  
  # and average the demographic predictions with the implied margin from partisan lean
  # giving more weight to the partisan lean until we have a ton of polls to shore up the regression
  demo_weight <- min( sum(state$sum_weights,na.rm=T) / (sum(state$sum_weights,na.rm=T) + 100), 0.5)
  partisan_weight <- 1 - demo_weight
  
  preds <- (preds * (demo_weight)) + 
    ( (state$dem_lean_2016 + national_biden_margin) * (partisan_weight) )
  
  # make the projections
  testing$proj_mean_clinton_margin <- preds
  
  # check predictions
  ggplot(na.omit(testing), aes(x=mean_clinton_margin,y=proj_mean_clinton_margin,label=state)) +
    geom_text() + 
    geom_abline() + 
    geom_smooth(method='lm')
  
  mean(abs(testing$proj_mean_clinton_margin - testing$mean_clinton_margin),na.rm=T)
  
  # average predictions with the polls ------------------------------------
  state <- state %>%
    # append the predictions
    left_join(testing %>% dplyr::select(state,proj_mean_clinton_margin), by = "state") %>%
    # make some mutations
    mutate(sum_weights = ifelse(is.na(sum_weights),0,sum_weights),
           mean_clinton_margin = ifelse(is.na(mean_clinton_margin),999,mean_clinton_margin))  %>%
    mutate(poll_weight = (sum_weights/(sum_weights+regression_weight)) ,
           demographic_weight = (regression_weight/(sum_weights+regression_weight))) %>%
    mutate(mean_clinton_margin_hat = #proj_mean_clinton_margin
             (mean_clinton_margin * poll_weight) +
             (proj_mean_clinton_margin *  demographic_weight)
    ) %>%
    mutate(mean_clinton_margin = ifelse(mean_clinton_margin == 999,NA,mean_clinton_margin))
  
  
  # adjust state projections to match average of national vote 
  og_national_clinton_margin <- last(national_poll_average$national_clinton_margin)
  
  implied_national_clinton_margin <- weighted.mean(state$mean_clinton_margin_hat,state_weights) 
  
  # regress the state predictions back toward the national average
  natl_diff <- function(par, 
                        dat = state, 
                        weights = state_weights,
                        target_natl = og_national_clinton_margin,
                        current_natl = implied_national_clinton_margin){
    
    dat$mean_clinton_margin_hat_shift <- dat$mean_clinton_margin_hat + (target_natl - current_natl)*par
    
    #print(weighted.mean(dat$mean_clinton_margin_hat, weights) )
    #print(weighted.mean(dat$mean_clinton_margin_hat_shift, weights) )
    
    return( abs( weighted.mean(dat$mean_clinton_margin_hat_shift, weights) - target_natl) )
    # return( dat$mean_clinton_margin_hat )
    
  }
  
  natl_diff(par = 1)
  
  multiplier <- optim(par = 1,fn = natl_diff,method = "Brent",upper = 5, lower = -5)$par
  
  state$mean_clinton_margin_hat <- state$mean_clinton_margin_hat + 
    (og_national_clinton_margin - implied_national_clinton_margin)*multiplier
  
  
  # save margin for later
  national_clinton_margin <- weighted.mean(state$mean_clinton_margin_hat,state_weights) 
  
  # plot final prediction against data
  ggplot(na.omit(state), aes(mean_clinton_margin, mean_clinton_margin_hat, label=state)) +
    geom_text(aes(size=num_polls)) + 
    geom_abline() + 
    geom_smooth(method='lm')
  
  # generate new state lean variable based on adjusted clinton national margin
  state$dem_lean_2016 <-  state$mean_clinton_margin_hat - national_clinton_margin 
  
  state_evs <- read_csv('data/state_evs.csv')
  
  # clean up estimates
  final <- state %>%
    dplyr::select(state,region,obama_margin,dem_lean_2012,
                  mean_clinton_margin = mean_clinton_margin_hat,
                  dem_lean_2016_polls,
                  dem_lean_2016, 
                  num_polls,
                  pop_density,
                  wwc_pct) %>%
    mutate(shift = dem_lean_2016 - dem_lean_2012)
  
  final <- final %>%
    left_join(state_evs)
  
  
  # toy simulations ---------------------------------------------------------
  # errors
  national_error <- (0.025) + (DAILY_SD * sqrt(days_til_election)) # national error + drift
  regional_error <- (0.025) 
  state_error <- (0.03) 
  
  sqrt(national_error^2 + regional_error^2 + state_error^2) # this is the total standard deviation on vote margin
  
  # sims
  national_errors <- rnorm(NUM_SIMS, 0, national_error)
  regional_errors <- replicate(NUM_SIMS, rnorm(length(unique(final$region)), 0, regional_error))
  state_errors <- replicate(NUM_SIMS, rnorm(51, 0, state_error))
  
  # actual sims
  
  #' Simulate polling errors.
  #'
  #' @param state_errors Matrix of simulated state polling errors. (num_states x NUM_SIMS)
  #' @param regional_errors Matrix of simulated regional polling errors. (num_regions x NUM_SIMS)
  #' @param national_errors Numeric vector of simulated national polling errors. Length is NUM_SIMS.
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
    left_join(final %>% select(state, dem_lean_2016), by = "state") %>%
    mutate(proj_clinton_margin = dem_lean_2016 + national_clinton_margin,
           error = state_error + regional_error + national_error,
           sim_clinton_margin = proj_clinton_margin + error) %>%
    group_by(state) %>%
    mutate(draw = row_number()) %>%
    left_join(state_evs, by='state') %>%
    left_join(enframe(state_weights, 'state', 'weight'), by = "state") %>%
    group_by(draw) %>%
    mutate(dem_nat_pop_margin = weighted.mean(sim_clinton_margin, weight)) %>%
    select(state, sim_clinton_margin, draw, ev, weight, dem_nat_pop_margin)
  
  # summarise state data
  state_summary <- sims %>%
    group_by(state) %>%
    summarise(clinton_margin_mean = mean(sim_clinton_margin),
              clinton_margin_high = quantile(sim_clinton_margin, 0.975),
              clinton_margin_low = quantile(sim_clinton_margin, 0.025),
              clinton_win_prob = mean(sim_clinton_margin >= 0))
  
  # summarise national data
  national_summary  <- sims %>%
    group_by(draw) %>%
    summarise(natl_dem_ev = sum(ev * (sim_clinton_margin >= 0)),
              dem_nat_pop_margin = unique(dem_nat_pop_margin)) %>%
    ungroup() %>%
    summarise(
      # votes
      clinton_nat_margin_mean = mean(dem_nat_pop_margin),
      clinton_nat_margin_high = quantile(dem_nat_pop_margin, 0.975),
      clinton_nat_margin_low = quantile(dem_nat_pop_margin, 0.025),
      clinton_nat_margin_win_prob = mean(dem_nat_pop_margin >= 0),
      # ec outcomes
      clinton_ec_vote_mean = mean(natl_dem_ev),
      clinton_ec_vote_mean = median(natl_dem_ev),
      clinton_ec_vote_high = quantile(natl_dem_ev, 0.975),
      clinton_ec_vote_low = quantile(natl_dem_ev, 0.025),
      clinton_ec_vote__win_prob = mean(natl_dem_ev >= 270),
    )
  
  # histogram of EC and pop votes
  sims_summary <- sims %>%
    group_by(draw) %>%
    summarise(natl_dem_ev = sum(ev * (sim_clinton_margin >= 0)),
              dem_nat_pop_margin = unique(dem_nat_pop_margin)) %>%
    ungroup()
  
  # return list of this ------
  # return
  list(RUN_DATE = RUN_DATE,
       national_summary = national_summary,
       state_summary = state_summary,
       sims_summary = sims_summary,
       raw_sims = sims,
       og_national_clinton_margin = og_national_clinton_margin,
       national_clinton_margin = national_clinton_margin)
  
  
}


# simulate for every day
todays_simulations <- simulation_election_day_x(RUN_DATE, all_polls, DAILY_SD)


# overall analysis for today's simulations --------------------------------
# first, get the national margins from the model
og_national_clinton_margin <- todays_simulations$og_national_clinton_margin
national_clinton_margin <- todays_simulations$national_clinton_margin

og_national_clinton_margin
national_clinton_margin

# import results data
results <- politicaldata::pres_results %>% 
  filter(year == 2012) %>%
  mutate(obama_margin = dem-rep) %>%
  select(state,obama_margin)

coefs <- read_csv('data/state_coefs.csv')

state <- results %>%
  left_join(todays_simulations$state_summary,by='state') %>%
  mutate(national_clinton_margin = national_clinton_margin,
         dem_lean_2012 = obama_margin - 0.021,
         dem_lean_2016 = clinton_margin_mean - national_clinton_margin) %>%
  left_join(coefs, by = "state")


state_evs <- read_csv('data/state_evs.csv')

# clean up estimates
final <- state %>%
  dplyr::select(state,region,obama_margin,dem_lean_2012,
                clinton_margin_mean,
                dem_lean_2016, 
                pop_density,
                wwc_pct) %>%
  mutate(shift = dem_lean_2016 - dem_lean_2012)

final <- final %>%
  left_join(state_evs)


sims <- todays_simulations$raw_sims

# calc the avg tipping point
tipping_point <- sims %>%
  group_by(draw) %>%
  mutate(dem_ev = sum(ev * (sim_clinton_margin > 0))) %>% 
  arrange(draw,
          ifelse(dem_ev >= 270, desc(sim_clinton_margin),sim_clinton_margin)) %>%
  ungroup() 

# state-level correlations?
tipping_point %>%
  dplyr::select(draw,state,sim_clinton_margin) %>%
  spread(state,sim_clinton_margin) %>%
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

# ev-popvote divide?
tipping_point %>%
  group_by(draw) %>%
  mutate(cumulative_ev = cumsum(ev)) %>%
  filter(cumulative_ev >= 270) %>%
  filter(row_number() == 1)  %>%
  mutate(diff =  sim_clinton_margin - dem_nat_pop_margin) %>%
  pull(diff) %>% mean # hist(breaks=100)

# what is the pop vote range?
dem_nat_pop_margin <- sims %>%
  group_by(draw) %>%
  summarise(dem_nat_pop_margin = unique(dem_nat_pop_margin)) %>%
  pull(dem_nat_pop_margin)

dem_pop_vote_prob <- mean(dem_nat_pop_margin>0)

# extract state-level data
state_probs <- sims %>%
  group_by(state_abbv = state) %>%
  summarise(mean_clinton_margin = mean(sim_clinton_margin,na.rm=T),
            se_clinton_margin = sd(sim_clinton_margin,na.rm=T),
            ev = unique(ev),
            prob = mean(sim_clinton_margin > 0,na.rm=T)) %>%
  ungroup() %>%
  arrange(desc(mean_clinton_margin)) %>% 
  mutate(cumulative_ev = cumsum(ev)) 

# graph mean estimates by state
urbnmapr::states %>%
  left_join(state_probs) %>%
  filter(state_abbv != 'DC') %>%
  ggplot(aes(x=long,y=lat,group=group,
             fill = mean_clinton_margin*100)) +
  geom_polygon(col='gray40')  + 
  coord_map("albers",lat0=39, lat1=45) +
  scale_fill_gradient2(name='clinton vote margin',high='#3498DB',low='#E74C3C',mid='gray98',midpoint=0,
                       guide = 'legend') +
  guides('fill'=guide_legend(nrow=1,title.position = 'top',title.hjust = 0.5)) +
  theme_void() + 
  theme(legend.position = 'top')

# graph win probabilities
urbnmapr::states %>%
  left_join(state_probs) %>%
  ggplot(aes(x=long,y=lat,group=group,fill=prob*100)) +
  geom_polygon(col='gray40')  + 
  coord_map("albers",lat0=39, lat1=45) +
  scale_fill_gradient2(name='Democratic win probability',high='#3498DB',low='#E74C3C',mid='gray98',midpoint=50,
                       limits = c(0,100)) +
  theme_void() + 
  theme(legend.position = 'top')


# electoral vote histogram
sims %>%
  group_by(draw) %>%
  summarise(dem_ev = sum(ev * (sim_clinton_margin > 0))) %>%
  ggplot(.,aes(x=dem_ev,fill=dem_ev >= 270)) +
  geom_histogram(binwidth=1) + 
  scale_fill_manual(values=c('TRUE'='blue','FALSE'='red')) +
  scale_y_continuous(labels = function(x){paste0(round(x / max(sims$draw)*100,2),'%')},
                     expand = expansion(mult = c(0, 0.2))) +
  labs(x='Democratic electoral votes',y='Probability') +
  theme_minimal() + 
  theme(legend.position = 'none') +
  labs(subtitle = sprintf('p(clinton win) = %s',
                          sims %>%
                            group_by(draw) %>%
                            summarise(dem_ev = sum(ev * (sim_clinton_margin > 0))) %>%
                            ungroup() %>%
                            summarise(dem_ev_majority = round(mean(dem_ev >=270),2)) %>%
                            pull(dem_ev_majority)))


# scenarios
 sims %>%
  group_by(draw) %>%
  summarise(dem_ev = sum(ev * (sim_clinton_margin > 0)),
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


# simulate for every day of the cycle so far ------------------------------
# every day from today going back in time
days_to_simulate <- na.omit(as_date(na.omit(rev(seq.Date(ymd('2016-03-01'),RUN_DATE,'day'))))[seq(1,300,3)])


# run the simulations for each week in parllale!!
if(length(days_to_simulate) > 0){
  campaign_simulations <- pblapply(1:length(days_to_simulate),
                                   cl = NUM_CORES,
                                   function(idx){
                                     TODAY_RUN_DATE <- days_to_simulate[idx]
                                     print(TODAY_RUN_DATE)
                                     
                                     output <- simulation_election_day_x(RUN_DATE = TODAY_RUN_DATE, all_polls, DAILY_SD)
                                     output$raw_sims <- NULL
                                     
                                     return(output)
                                   })
}


# look at time-series results ---------------------------------------------
key_states <- c('AZ','TX','FL','GA','NC','PA','MI','OH','IA','WI','NV','MN')


# glance at first entry
campaign_simulations[[1]]$state_summary %>% filter(state %in% key_states)

# look at overall dem margin over time
map_df(campaign_simulations,
         function(x){
         x[['national_summary']] %>%
           mutate(date = x[['RUN_DATE']])
       })  %>%
ggplot(.,aes(x=date,y=clinton_nat_margin_mean)) +
geom_hline(yintercept=0,col='#E74C3C',alpha=0.8) +
geom_line() +
geom_point(data = all_polls %>%
             filter(state == '--') %>%
             mutate(clinton_margin = (clinton-trump)/100,
                    date = ymd(end.date)) ,
           aes(x=date,y=clinton_margin),alpha=0.2) +
coord_cartesian(xlim=c(ymd('2016-03-01'),ymd('2016-11-06'))) +
scale_x_date(date_breaks='month',date_labels='%b') +
scale_y_continuous(breaks=seq(-1,1,0.05),labels = function(x){round(x*100)}) +
theme_minimal() +
theme(panel.grid.minor = element_blank())  +
labs(x='',
     y='',
     subtitle="Projected clinton margin, alongside national polls")

# overall odds over time
map_df(campaign_simulations,
         function(x){
           x[['national_summary']] %>%
             mutate(date = x[['RUN_DATE']])
         })  %>%
  ggplot(.,aes(x=date,y=clinton_ec_vote__win_prob)) +
  geom_hline(yintercept=0.5,col='#E74C3C',alpha=0.8) +
  geom_line() +
  coord_cartesian(xlim=c(ymd('2016-03-01'),ymd('2016-11-06'))) +  scale_x_date(date_breaks='month',date_labels='%b') +
  scale_y_continuous(breaks=seq(0,1,0.1),labels = function(x){x*100},
                     limits=c(0,1)) +
  theme_minimal() +
  theme(panel.grid.minor = element_blank()) +
  labs(x='',
       y='',
       subtitle="Clinton chance of winning the electoral college")


# dem margins in key states over time
base_frame <- expand_grid(state = campaign_simulations[[1]]$state_summary$state,
                          date = as_date(ymd('2016-03-01'):ymd("2016-11-08")))


polls_and_trends <- 
  # start with base data on dates
  base_frame %>%
  # add averages
  left_join(
    map_df(campaign_simulations,
           function(x){
             x[['state_summary']] %>%
               mutate(date = x[['RUN_DATE']])
           }),
    by = c("state", "date"))  %>%
  # then add polls
  left_join(
    all_polls %>%
      filter(state != '--') %>%
      mutate(clinton_margin = (clinton-trump)/100,
             date = ymd(end.date)),
    by=c('date','state')
  )



polls_and_trends %>%
  filter(state %in% key_states) %>%
  ggplot(.) +
  geom_hline(yintercept=0,col='#E74C3C',alpha=0.8) +
  geom_line(data = . %>% filter(!is.na(clinton_margin_mean)),
            aes(x=date,y=clinton_margin_mean)) +
  geom_ribbon(data = . %>% filter(!is.na(clinton_margin_mean)),
              aes(x=date,ymin=clinton_margin_low,ymax=clinton_margin_high),
              col=NA,alpha=0.2) +
  geom_point(aes(x=date,y=clinton_margin),alpha=0.2) +
  scale_y_continuous(breaks = seq(-1,1,0.05),
                     labels = function(x){round(x*100)}) +
  facet_wrap(~state) +
  coord_cartesian(xlim=c(ymd('2016-03-01'),ymd('2016-11-06'))) +
  scale_x_date(date_breaks='month',date_labels='%b') +
  theme_minimal() +
  theme(panel.grid.minor = element_blank()) +
  labs(x='Date',y='',subtitle='clinton margin and 95% prediction interval in key states')


# probability in key states over time
polls_and_trends %>%
  filter(state %in% key_states) %>%
  ggplot(.) +
  geom_hline(yintercept=0.5,col='#E74C3C',alpha=0.8) +
  geom_line(data = . %>% filter(!is.na(clinton_margin_mean)),
            aes(x=date,y=clinton_win_prob)) +
  scale_y_continuous(breaks = seq(0,1,0.1),
                     labels = function(x){round(x*100)},
                     limits = c(0,1)) +
  facet_wrap(~state) +
  coord_cartesian(xlim=c(ymd('2016-03-01'),ymd('2016-11-06'))) +
  scale_x_date(date_breaks='month',date_labels='%b') +
  theme_minimal() +
  theme(panel.grid.minor = element_blank())  +
  labs(x='Date',y='',subtitle='clinton win probability in key states')



