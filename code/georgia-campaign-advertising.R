# ============================================================================
# georgia-campaign-ads.R
# Project: Georgia Governor's Race Campaign Advertisement Analysis
#
# Overview:
#   1. Import and inspect the coded advertisement data
#   2. Summarize ads by candidate, theme, message type, and emotional appeal
#   3. Split multi-theme entries and count individual themes by candidate
#   4. Standardize theme labels
#   5. Cross-tabulate candidate presentation
#   6. Export theme counts for Tableau
# ============================================================================


# ----------------------------------------------------------------------------
# SECTION 1: Import and inspect the data
# ----------------------------------------------------------------------------

# Import the coded advertisement data (one row per advertisement)
ads <- read.csv("C:/Users/amare/Downloads/Georgia_Campaign_Ad_Coding.csv",
                stringsAsFactors = FALSE)

# Preview the first rows of the dataset
head(ads)

# Check column names and data types
str(ads)

# Preview the dataset again
head(ads)

# Check column names and data types again
str(ads)

# Count of advertisements per candidate
table(ads$candidate)


# ----------------------------------------------------------------------------
# SECTION 2: Summary tables
# ----------------------------------------------------------------------------

# 1. Total number of advertisements
nrow(ads)

# 2. Advertisements by candidate
table(ads$candidate)

# 3. Main messaging themes by candidate
table(ads$candidate, ads$main_theme)

# 4. Message types by candidate
table(ads$candidate, ads$message_type)

# 5. Emotional appeals by candidate
table(ads$candidate, ads$emotional_appeal)


# ----------------------------------------------------------------------------
# SECTION 3: Count individual themes by candidate
# Some ads were coded with multiple themes in one cell (comma-separated),
# so each theme is split into its own row before counting.
# ----------------------------------------------------------------------------

# Install tidyr (only needs to be run once)
install.packages("tidyr")

# Load packages
library(tidyr)
library(dplyr)

# Split comma-separated themes into separate rows, trim whitespace,
# and count how many times each theme appears for each candidate
themes <- ads %>%
  separate_rows(main_theme, sep = ",\\s*") %>%
  mutate(main_theme = trimws(main_theme)) %>%
  count(candidate, main_theme)

print(themes)


# ----------------------------------------------------------------------------
# SECTION 4: Standardize theme labels
# ----------------------------------------------------------------------------

# Recode labels: "Public Safety" -> "Public safety", "Trump Wins" -> "Trump"
themes <- themes %>%
  mutate(main_theme = case_when(
    main_theme == "Public Safety" ~ "Public safety",
    main_theme == "Trump Wins" ~ "Trump",
    TRUE ~ main_theme
  ))

print(themes)

# Rebuild the theme counts from the raw data, this time converting all
# labels to lowercase and recoding "trump wins" to "trump"
themes <- ads %>%
  separate_rows(main_theme, sep = ",\\s*") %>%
  mutate(
    main_theme = trimws(main_theme),
    main_theme = tolower(main_theme),
    main_theme = case_when(
      main_theme == "trump wins" ~ "trump",
      TRUE ~ main_theme
    )
  ) %>%
  count(candidate, main_theme)

print(themes)


# ----------------------------------------------------------------------------
# SECTION 5: Candidate presentation
# ----------------------------------------------------------------------------

# Cross-tabulation of candidate by candidate presentation style
table(ads$candidate, ads$candidate_presentation, ads$table(ads$candidate, ads$candidate_presentation, ads$))


# ----------------------------------------------------------------------------
# SECTION 6: Export
# ----------------------------------------------------------------------------

# Save the standardized theme counts as a CSV for use in Tableau
write.csv(themes,
          "C:/Users/amare/Downloads/Georgia_Ad_Themes.csv",
          row.names = FALSE)
