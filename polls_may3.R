library(tidyverse)
library(lubridate)
library(politicaldata)
library(pbapply)
library(parallel)
library(ggrepel)
library(caret)

# wrangle data ------------------------------------------------------------
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
all_polls <- read_csv('data/polls.csv')

head(all_polls)

# remove any polls if biden or trump blank
all_polls <- all_polls %>% filter(!is.na(biden),!is.na(trump))#, include == "TRUE")

all_polls <- all_polls %>%
  filter(mdy(end.date) >= (Sys.Date()-60) ) %>%
  mutate(weight = sqrt(number.of.observations / mean(number.of.observations)))

# ow much should we weight regression by compared to polls?
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
  left_join(state_averages) %>%
  mutate(dem_lean_2016 = clinton_margin - 0.021,
         dem_lean_2020_polls = mean_biden_margin - national_biden_margin) %>%
  left_join(coefs)


# model to fill in polling gaps -------------------------------------------
# simple lm
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
training <- state %>% 
  dplyr::select(state,mean_biden_margin,clinton_margin,black_pct,college_pct,
         hisp_other_pct,median_age,pct_white_evangel,
         pop_density,white_pct,wwc_pct,sum_weights) %>%
  mutate_at(c('clinton_margin','black_pct','college_pct',
              'hisp_other_pct','median_age','pct_white_evangel',
              'pop_density','white_pct','wwc_pct'),
            function(x){
              (x - mean(x)) / sd(x)
            }) 

testing <- training
training <- training %>% na.omit()

model <- train(mean_biden_margin ~ clinton_margin + black_pct + college_pct + 
                 hisp_other_pct + median_age + pct_white_evangel + pop_density + 
                 white_pct + wwc_pct,
               data = training,
               weights = sum_weights,
               method = "glmnet",
               metric = "RMSE",
               trControl = trainControl(method="LOOCV"),
               tuneLength = 20)

# look @ model
model

# make the projections
testing$proj_mean_biden_margin <- predict(object=model,newdata=testing)

# check predictions
ggplot(na.omit(testing), aes(x=mean_biden_margin,y=proj_mean_biden_margin,label=state)) +
  geom_text() + 
  geom_abline() + 
  geom_smooth(method='lm')

# add to state data frame
state <- state %>%
  # append the predictions
  left_join(testing %>% dplyr::select(state,proj_mean_biden_margin)) %>%
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

# adjust state-level polls and predictions to polled national margin?
# for now, no....
adj_national_biden_margin <-  national_biden_margin # weighted.mean(state$mean_biden_margin_hat,state_weights)

state$mean_biden_margin_hat <-  state$mean_biden_margin_hat - (adj_national_biden_margin- national_biden_margin)

# save new biden national margin
national_biden_margin <- weighted.mean(state$mean_biden_margin_hat,state_weights)

national_biden_margin

# generate new state lean variable based on adjusted biden national margin
state$dem_lean_2020 <-  state$mean_biden_margin_hat - national_biden_margin 

# clean up estimates
final <- state %>%
  select(state,region,clinton_margin,dem_lean_2016,
         mean_biden_margin = mean_biden_margin_hat,
         dem_lean_2020_polls,
         dem_lean_2020, 
         num_polls,
         pop_density) %>%
  mutate(shift = dem_lean_2020 - dem_lean_2016)

final <- final %>%
  left_join(read_csv('data/state_evs.csv')) 


# shift from 2016 to 2020 -------------------------------------------------
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

# any realtionship with urbanicity?
final %>%
  filter(state != 'DC') %>%
  ggplot(.,aes(x=pop_density,y=mean_biden_margin-clinton_margin,label=state,
               col = clinton_margin > 0,group=NA)) + 
  geom_text_repel() + 
  geom_smooth(method='lm',col='black',linetype=2) + 
  scale_y_continuous(breaks=seq(-1,1,0.02), labels = function(x){round(x*100)}) +
  scale_color_manual(values=c('TRUE'='blue','FALSE'='red')) +
  theme_minimal() + 
  theme(panel.grid.minor = element_blank(),
        legend.position = 'none') +
  labs(subtitle='Swing towards Biden in presidential vote margin',
       x='Number of people within 5 miles of each resident (log values)',
       y='')
  
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

# plot
urbnmapr::states %>%
  left_join(final %>% select(state_abbv = state,mean_biden_margin) %>%
              mutate(mean_biden_margin = case_when(mean_biden_margin > 0.2 ~ 0.2,
                                                   mean_biden_margin < -0.2 ~ -0.2,
                                                   TRUE ~ mean_biden_margin))) %>%
  ggplot(aes(x=long,y=lat,group=group,fill=mean_biden_margin*100)) +
  geom_polygon(col='gray40')  + 
  coord_map("albers",lat0=39, lat1=45) +
  scale_fill_gradient2(name='Democratic vote margin',high='#3498DB',low='#E74C3C',mid='gray98',midpoint=0) +
  theme_void() + 
  theme(legend.position = 'top')

# toy simulations ---------------------------------------------------------
# errors
national_error <- (0.0167*2)*1.5
regional_error <- (0.0167*2)*1.5
state_error <- (0.0152*2)*1.5

# sims
national_errors <- rnorm(1e04, 0, national_error)
regional_errors <- replicate(1e04,rnorm(length(unique(final$region)), 0, regional_error))
state_errors <- replicate(1e04,rnorm(51, 0, state_error))

# actual sims
state_and_national_errors <- pblapply(1:length(national_errors),
                                      cl = detectCores() -1,
                                      function(x){
                                        state_region <- final %>%
                                          mutate(proj_biden_margin = dem_lean_2020 + national_biden_margin) %>%
                                          select(state, proj_biden_margin) %>%
                                          left_join(final %>% 
                                                      ungroup() %>%
                                                      dplyr::select(state,region) %>% distinct) %>%
                                          left_join(tibble(region = unique(final$region),
                                                           regional_error = regional_errors[,x])) %>%
                                          left_join(tibble(state = unique(final$state),
                                                           state_error = state_errors[,x]))
                                        
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
  
# calc the new tipping point
tipping_point <- state_and_national_errors %>%
  do.call('bind_rows',.) %>%
  group_by(state) %>%
  mutate(draw = row_number()) %>%
  ungroup() %>%
  left_join(states2016 %>% dplyr::select(state,ev),by='state') %>%
  left_join(enframe(state_weights,'state','weight')) %>%
  group_by(draw) %>%
  mutate(dem_nat_pop_margin = weighted.mean(sim_biden_margin,weight))


tipping_point <- pblapply(1:max(tipping_point$draw),
                          cl = parallel::detectCores() - 1,
                          function(x){
                            temp <- tipping_point[tipping_point$draw==x,]
                            
                            if(temp$dem_nat_pop_margin > 0){
                              temp <- temp %>% arrange(desc(sim_biden_margin))
                            }else{
                              temp <- temp %>% arrange(sim_biden_margin)
                            }
                            
                            return(temp)
                          }) %>%
  do.call('bind_rows',.) %>%
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

left_join(tipping_point %>%
      group_by(draw) %>%
      mutate(cumulative_ev = cumsum(ev)) %>%
      filter(cumulative_ev >= 270) %>%
      filter(row_number() == 1) %>% 
      group_by(state) %>%
      summarise(prop = n()) %>%
      mutate(prop = round(prop / sum(prop)*100,1)) %>%
      arrange(desc(prop))  %>% 
      head(20) %>%
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
        tail(nrow(.)-20)%>%
        mutate(row_number = row_number()),
      by='row_number'
      ) %>% 
  select(-row_number) %>%
  setNames(.,c('State','Tipping point chance (%)','State','Tipping point chance (%)')) %>%
  knitr::kable(.)

# ev-popvote divide?
tipping_point %>%
  group_by(draw) %>%
  mutate(cumulative_ev = cumsum(ev)) %>%
  filter(cumulative_ev >= 270) %>%
  filter(row_number() == 1)  %>%
  mutate(diff = dem_nat_pop_margin - sim_biden_margin) %>%
  pull(diff) %>% mean # hist(breaks=100)

# extract state-level data
state_probs <- tipping_point %>%
  group_by(state_abbv = state) %>%
  summarise(mean_biden_margin = mean(sim_biden_margin,na.rm=T),
            ev = unique(ev),
            prob = mean(sim_biden_margin > 0,na.rm=T)) %>%
  ungroup() %>%
  arrange(desc(mean_biden_margin)) %>% 
  mutate(cumulative_ev = cumsum(ev)) 

# graph mean estimates by state
urbnmapr::states %>%
  left_join(state_probs%>%
              mutate(mean_biden_margin = case_when(mean_biden_margin > 0.2 ~ 0.2,
                                                   mean_biden_margin < -0.2 ~ -0.2,
                                                   TRUE ~ mean_biden_margin))) %>%
  ggplot(aes(x=long,y=lat,group=group,fill=mean_biden_margin*100)) +
  geom_polygon(col='gray40')  + 
  coord_map("albers",lat0=39, lat1=45) +
  scale_fill_gradient2(name='Democratic vote margin',high='#3498DB',low='#E74C3C',mid='gray98',midpoint=0,
                       limits = c(-20,20),guide = 'legend') +
  theme_void() + 
  theme(legend.position = 'top')

# graph win probabilities
urbnmapr::states %>%
  left_join(state_probs %>% 
              mutate(mean_biden_margin = case_when(mean_biden_margin > 0.2 ~ 0.2,
                                                   mean_biden_margin < -0.2 ~ -0.2,
                                                   TRUE ~ mean_biden_margin)) ) %>%
  ggplot(aes(x=long,y=lat,group=group,fill=prob*100)) +
  geom_polygon(col='gray40')  + 
  coord_map("albers",lat0=39, lat1=45) +
  scale_fill_gradient2(name='Democratic win probability',high='#3498DB',low='#E74C3C',mid='gray98',midpoint=50,
                       limits = c(0,100)) +
  theme_void() + 
  theme(legend.position = 'top')

# electoral vote histogram
tipping_point %>%
  group_by(draw) %>%
  summarise(dem_ev = sum(ev * (sim_biden_margin > 0))) %>%
  ggplot(.,aes(x=dem_ev,fill=dem_ev >= 270)) +
  geom_histogram(binwidth=1) + 
  scale_fill_manual(values=c('TRUE'='blue','FALSE'='red')) +
  scale_y_continuous(labels = function(x){paste0(round(x / max(tipping_point$draw)*100,2),'%')}) +
  labs(x='Democratic electoral votes',y='Probability') +
  theme_minimal() + 
  theme(legend.position = 'none') +
  labs(subtitle = sprintf('p(Democratic win) = %s',
                          tipping_point %>%
                            group_by(draw) %>%
                            summarise(dem_ev = sum(ev * (sim_biden_margin > 0))) %>%
                            ungroup() %>%
                            summarise(dem_ev_majority = round(mean(dem_ev >=270),2)) %>%
                            pull(dem_ev_majority)))

# scenarios
tipping_point %>%
  group_by(draw) %>%
  summarise(dem_ev = sum(ev * (sim_biden_margin > 0)),
            dem_nat_pop_margin = unique(dem_nat_pop_margin)) %>%
  mutate(scenario = 
           case_when(dem_ev >= 270 & dem_nat_pop_margin > 0 ~ 'D EC D vote',
                     dem_ev >= 270 & dem_nat_pop_margin < 0 ~ 'D EC R vote',
                     dem_ev <  270 & dem_nat_pop_margin > 0 ~ 'R EC D vote',
                     dem_ev <  270 & dem_nat_pop_margin < 0 ~ 'R EC R vote',
                     )) %>%
  group_by(scenario) %>%
  summarise(prop = n()) %>%
  mutate(prop = prop / sum(prop))


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










