library(tidyverse)

results <- read_csv('data/prior/potus_results_historical.csv')

usa <- results %>% filter(State == 'Nationwide')
state_results <- results %>% filter(State != 'Nationwide')

# state, make two-party
state_results <- state_results %>%
  gather(year,vote,2:ncol(.)) %>% 
  mutate(party = gsub("[^a-zA-Z]","",year),
         year = gsub("[a-zA-Z]","",year)) %>%
  group_by(State,year) %>%
  spread(party,vote) %>%
  mutate(dem_two_party_share = Dem / (Dem + Rep)) %>%
  as.data.frame() %>%
  ungroup() %>%
  dplyr::select(state=State,year,dem_two_party_share) %>%
  mutate(year = as.numeric(year))

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

results <- state_results 

# recode state
results$state <- c(state.abb,'DC')[match(results$state,c(state.name,'District of Columbia'))]

dc <- results  %>% filter(state == 'DC')

# get everywhere else
results <- read_csv('data/prior/state_pres_results_dan.csv')

# bind with DC
results <- results %>%
  bind_rows(na.omit(dc))  %>%
  dplyr::select(year,state,dem_two_party_share)

# bind on MRP for 2020
mrp <- read_csv('data/mrp_predictions.csv')
mrp <- mrp %>%
  mutate(dem_two_party_share = pres_2020_dem / (pres_2020_dem + pres_2020_rep),
         year = 2020) %>%
  dplyr::select(year,state=state_abb,dem_two_party_share) 


results <- results %>%
  bind_rows(mrp)

# data frame with electoral votes
historical_evs <- read_csv('data/prior/state_evs_historical.csv')


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

results <- results %>%
  left_join(usa)

results <- results %>%
  group_by(year) %>%
  arrange(year,desc(dem_two_party_share)) %>%
  mutate(cumulative_ev = cumsum(ev)) %>%
  filter(cumulative_ev >= evs_to_win) %>%
  filter(row_number()  == 1) %>%
  mutate(dem_two_party_share_national = ifelse(year == 2020, 
                                               0.5303455,
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



