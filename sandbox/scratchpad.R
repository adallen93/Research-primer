library(tidyverse)
library(mosaic)

mylm <- lm(gasbill ~ month + I(month^2), data = Utilities)
b <- coef(mylm)
Utilities %>% 
  ggplot(aes(x = month, y = gasbill)) +
  geom_point(col = 'navy') +
  stat_function(fun = function(x) b[1] + b[2]*x + b[3]*x^2, col = 'navy') +
  labs(title = 'To ensure I am not insane', x = 'Month', y = 'Monly Gas Bill (USD)') +
  scale_x_continuous(breaks = c(2,5,8,11)) +
  theme_bw() +
  theme(plot.title = element_text(hjust = .5, size = 13, face = 'bold'),
        text = element_text(family = 'serif'))

#afd


