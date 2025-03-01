
library(knitr)
library(shinydashboard)

library(tidyverse)
library(stringi)
library(dplyr)
library(DT)
library(shiny)
library(spgs)
library(biomaRt)
library(rsconnect)

options(repos = BiocManager::repositories())

ui <- fluidPage(
  
  # Application title
  titlePanel("Old Faithful Geyser Data"),
  
  # Sidebar with a slider input for number of bins 
  sidebarLayout(
    sidebarPanel(
      textInput(inputId = "primer_list", label = "Enter Primers", value = "rs25 rs16944 rs1884 rs17287498"),
      br(),
      numericInput(inputId = "primer_away", label = "Primer Distance (bp)", value = 50),
      br(),
      sliderInput("primer_right_length", label = h3("Reverse Primer length"), min = 10,
                  max = 40, value = c(10, 15)),
      br(),
      sliderInput("primer_left_length", label = h3("Forward Primer length"), min = 18,
                  max = 40, value = c(18, 20)),
      br()
    ),
    
    # Show a plot of the generated distribution
    mainPanel(
      tableOutput(outputId = "primer_table"),
      textOutput(outputId = "primer_text")
      
    )
  )
)


server <- function(input, output) {
  get_strong1 <- function(x){
    temp <- ""
    target <- str_sub(x , - 3, - 3)
    target <- complement(target)
    if (target == "A") {temp <- "G"} else
      if (target == "G") {temp <- "A"} else
        if (target == "C") {temp <- "T"} else
          if (target == "T") {temp <- "C"}
    substring(x, nchar(x) - 2, nchar(x) - 2) <- temp
    return(x)
  }
  ## Mismatching on Ts
  get_strong2 <- function(x){
    temp <- ""
    target <- str_sub(x , - 3, - 3)
    target <- complement(target)
    if (target == "T") {
      temp <- "T"
      substring(x, nchar(x) - 2, nchar(x) - 2) <- temp
      return(x)}
    else
      return(NULL)
  }
  get_medium1 <- function(x){
    temp <- ""
    target <- str_sub(x , - 3, - 3)
    target <- complement(target)
    if (target == "A") {temp <- "A"} else
      if (target == "G") {temp <- "G"} else
        if (target == "C") {temp <- "C"} else
          return(NULL)
    substring(x, nchar(x) - 2, nchar(x) - 2) <- temp
    return(x)
  }
  get_weak1 <- function(x){
    temp <- ""
    target <- str_sub(x , - 3, - 3)
    target <- complement(target)
    if (target == "C") {temp <- "A"} else
      if (target == "A") {temp <- "C"} else
        if (target == "G") {temp <- "T"} else
          if (target == "T") {temp <- "G"}
    substring(x, nchar(x) - 2, nchar(x) - 2) <- temp
    return(x)
  }
  reverse_chars <- function(string)
  {
    # split string by characters
    string_split = strsplit(string, split = "")
    # reverse order
    rev_order = nchar(string):1
    # reversed characters
    reversed_chars = string_split[[1]][rev_order]
    # collapse reversed characters
    paste(reversed_chars, collapse = "")
  }
  mart_api <- function(primer,
                       primer_away,
                       primer_min,
                       primer_max,
                       primer_left_min,
                       primer_left_max){
    snp_list <- strsplit(primer, " ")[[1]]
    # the length of flanking sequences we will retrieve
    upStream <- c("500")
    downStream <- c("500")
    print("Hi hi  how was your night")
    # use biomaRt to connect to the human snp database
    snpmart <- useMart("ENSEMBL_MART_SNP", dataset = "hsapiens_snp")
    snp_sequence <- getBM(attributes = c('refsnp_id', 'snp'),
                          filters = c('snp_filter', 'upstream_flank', 'downstream_flank'),
                          checkFilters = FALSE,
                          values = list(snp_list, upStream, downStream),
                          mart = snpmart,
                          bmHeader = TRUE)
    snp_sequence_split <- as.data.frame(str_split(snp_sequence$`Variant sequences`, "%"))
    # the data frame just created has each snp in a column, need to name the columns
    colnames(snp_sequence_split) <- snp_sequence$`Variant name`
    # name the rows of the data frame
    rownames(snp_sequence_split) <- c("upstream", "variants", "downstream")
    # want to transpose the data frame so each variant is a row instead of a column
    snps <- t(snp_sequence_split)
    # now work on getting the variants split
    snpsTibble <- as_tibble(snps, rownames = NA)
    vars_split <- str_split(snpsTibble$variants, "/")
    # vars_split now contains the possible variants, but there are possibly different numbers of variants
    # need to make all entries in vars_split the same length
    #n <- max(lengths(vars_split))
    # set n to be the most possible variants we could possibly see at any snp position
    # we'll go with 10, which should be much larger than any number we'll see
    # can get rid of extras later
    n <- 10
    vars_split_uniform <- as.data.frame(lapply(vars_split, `length<-`, n))
    # vars_split_uniform now has each snpID in a column and the possible variants as the rows
    # need to name things to keep that straight
    colnames(vars_split_uniform) <- snp_sequence$`Variant name`
    vars_split_transposed <- t(vars_split_uniform)
    variantsTibble <- as_tibble(vars_split_transposed, rownames = NA)
    varListFinal <- mutate(variantsTibble, snpsTibble)
    varListFinal['snpID'] <- snp_sequence$`Variant name`
    # make it a tibble
    variantsTibbleFinal <- as_tibble(varListFinal, rownames = NA)
    variantsTibbleFinal2 <- pivot_longer(variantsTibbleFinal,
                                         cols = V1:V10,
                                         names_to = "variations",
                                         values_to = "observations")
    # we padded the length of the variants columns earlier to make sure we
    # could handle any length we might see in the pivot_longer
    # now, simply remove any rows that contain NA in the observations column
    variantsTrimmed <- drop_na(variantsTibbleFinal2)
    # variantsTrimmed has everything we need to make the output for calling primer3
    # need to reorder then combine some columns
    # we want one string that is the upstream sequence, then the observation of the snp
    # then the downstream sequence all together in one string
    variantsTrimmed <- variantsTrimmed %>% relocate(snpID)
    variantsTrimmed <- variantsTrimmed %>% relocate(observations, .before = variations)
    variantsTrimmed <- variantsTrimmed %>% relocate(downstream, .before = variations)
    variantsTrimmed <- variantsTrimmed %>% unite("sequence", upstream:downstream, sep = "")
    # add columns for the substrings leading up to and including the variant site
    for (i in primer_left_min:primer_left_max) {
      colname <- paste0("left", i)
      variantsTrimmed <- variantsTrimmed %>%
        mutate(!!colname := str_sub(sequence, 501 - i, 501))
    }
    for (i in primer_min:primer_max) {
      colname <- paste0("right", 500 - primer_away -i)
      variantsTrimmed <- variantsTrimmed %>% mutate(!!colname := str_sub(sequence,
                                                                         500 - primer_away - i,
                                                                         500 - primer_away))
    }
    limit_left_start <- paste("left", primer_left_max, sep = "")
    limit_left_stop <- paste("left", primer_left_min, sep = "")
    limit_right_start <- paste("right", 500 - primer_away - primer_max, sep = "")
    limit_right_stop <- paste("right", 500 - primer_away - primer_min, sep = "")
    # pivot longer so each left primer gets on it's own row in the tibble
    variantsTrimmed2 <- pivot_longer(variantsTrimmed,
                                     cols = limit_left_start:limit_left_stop,
                                     names_to = "Left_side",
                                     values_to = "leftPrimers")
    variantsTrimmed2 <- pivot_longer(variantsTrimmed2,
                                     cols = limit_right_start:limit_right_stop,
                                     names_to = "Right_side",
                                     values_to = "rightPrimers")
    variantsTrimmed2 <- variantsTrimmed2[c(1,4,6,5,7)]
    print("Check 1")
    mismatch_list <- variantsTrimmed2 %>%
      mutate(strong_mismatch_1 = map(leftPrimers, get_strong1),
             strong_mismatch_2 = map(leftPrimers, get_strong2),
             Medium_mismatch = map(leftPrimers, get_medium1),
             Weak_mismatch = map(leftPrimers, get_weak1)) %>%
      pivot_longer(
        cols = c(strong_mismatch_1,
                 strong_mismatch_2,
                 Medium_mismatch,
                 Weak_mismatch),
        names_to = "Mismatch",
        values_to = "primer",
        values_drop_na = TRUE) %>%
      mutate(Identidy = paste(snpID, Left_side, Right_side, Mismatch,sep = " ")) %>%
      as.data.frame() %>%
      dplyr::select(c(8, 7, 5)) %>%
      mutate(rightPrimers = toupper(reverseComplement(rightPrimers)))
    print("Check 2")
    
    source_python("getdata.py")
    #df <- getdata(mismatch_list)
    
    return(mismatch_list)
  }
  
  beta_api <- function(primer,
                       primer_away,
                       primer_min,
                       primer_max,
                       primer_left_min,
                       primer_left_max){
    return(paste(primer,
                 primer_away,
                 primer_min,
                 primer_max,
                 primer_left_min,
                 primer_left_max))
  }
  
  output$primer_table <- renderTable(
    mart_api(input$primer_list,
             input$primer_away,
             input$primer_right_length[1],
             input$primer_right_length[2],
             input$primer_left_length[1],
             input$primer_left_length[2])
  )
  
  output$primer_text <- renderText(
    paste(input$primer_list,
          input$primer_away,
          input$primer_right_length[1],
          input$primer_right_length[2],
          input$primer_left_length[1],
          input$primer_left_length[2])
  )
}

shinyApp(ui, server)


