/* ============================================================================
   congressional-elections.sql
   Project: House Election Analysis (urban vs. rural population and margins)

   Overview:
     1. Create database
     2. Fix data-entry errors and sanity-check the source data
     3. Pull general-election results for a sample of districts
        (1992, 2000, 2008, 2016, 2024)
     4. Build dbo.DistrictElectionMargins (one row per district-year)
     5. Explore the Census data and develop the join key
     6. Build dbo.ElectionUrbanizationAnalysis (final analysis table)
     7. Clean up columns
     8. Run summary/validation queries
   ============================================================================ */


/* ----------------------------------------------------------------------------
   SECTION 1: Database setup
   ---------------------------------------------------------------------------- */

CREATE DATABASE House_Election_Analyis;

USE House_Election_Analyis;
GO


/* ----------------------------------------------------------------------------
   SECTION 2: Data quality checks and manual corrections
   ---------------------------------------------------------------------------- */

-- Diagnostic: find rows with a data-entry error where the candidatevotes
-- column contains the text 'DEMOCRAT' instead of a vote count.
-- This surfaced two affected candidates (fixed by the UPDATEs below).
SELECT * 
FROM [dbo].[clean_house_data]
WHERE candidatevotes = 'DEMOCRAT'

-- Manual fix #1: Georgia 2024 (Henry C.). candidatevotes held 'DEMOCRAT'
-- instead of a number. Set party and the correct vote counts.
UPDATE dbo.clean_house_data
SET
    party = 'DEMOCRAT',
    candidatevotes = '278906',
    totalvotes = '348299'
WHERE [year] = 2024
  AND [state] = 'GEORGIA'
  AND candidate LIKE '%HENRY C.%';

-- Manual fix #2: Maryland 2024 (Johnny O.). Same error, same correction.
UPDATE dbo.clean_house_data
SET
    party = 'DEMOCRAT',
    candidatevotes = '223797',
    totalvotes = '384794'
WHERE [year] = 2024
  AND [state] = 'MARYLAND'
  AND candidate LIKE '%JOHNNY O%';

-- Verify both corrections took effect.
SELECT
    [year],
    [state],
    candidate,
    party,
    candidatevotes,
    totalvotes
FROM dbo.clean_house_data
WHERE [year] = 2024
  AND (
      [state] = 'GEORGIA'
      OR [state] = 'MARYLAND'
  )
  AND (
      candidate LIKE '%HENRY C.%'
      OR candidate LIKE '%JOHNNY O%'
  );

-- Overall profile of the dataset: row count and range of election years.
-- TRY_CONVERT returns NULL instead of erroring if [year] has bad text values.
SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT [year]) AS election_years,
    MIN(TRY_CONVERT(INT, [year])) AS first_year,
    MAX(TRY_CONVERT(INT, [year])) AS last_year
FROM dbo.clean_house_data;


/* ----------------------------------------------------------------------------
   SECTION 3: Exploratory pulls (sample states, presidential-cycle years)
   Filters used throughout:
     - stage = 'GEN'        -> general election only (no primaries)
     - special = 'FALSE'    -> exclude special elections
     - party IN (D, R)      -> two-party comparison
   ---------------------------------------------------------------------------- */

-- Version 1: all districts in the 15 sample states, excluding runoffs.
SELECT
    [year],
    [state],
    district,
    party,
    candidatevotes,
    totalvotes
FROM dbo.clean_house_data
WHERE TRY_CONVERT(INT, [year]) IN (1992, 2000, 2008, 2016, 2024)
  AND [state] IN (
      'TEXAS',
      'GEORGIA',
      'ARIZONA',
      'CALIFORNIA',
      'IOWA',
      'MICHIGAN',
      'NEW YORK',
      'NORTH DAKOTA',
      'OKLAHOMA',
      'PENNSYLVANIA',
      'SOUTH CAROLINA',
      'NORTH CAROLINA',
      'SOUTH DAKOTA',
      'VERMONT',
      'WISCONSIN'
  )
  AND stage = 'GEN'
  AND special = 'FALSE'
  AND runoff = 'FALSE'
  AND party IN ('DEMOCRAT', 'REPUBLICAN')
ORDER BY
    TRY_CONVERT(INT, [year]),
    [state],
    TRY_CONVERT(INT, district);

-- Version 2: same as Version 1, but with the runoff filter removed
-- so runoff general elections are included.
SELECT
    [year],
    [state],
    district,
    party,
    candidatevotes,
    totalvotes
FROM dbo.clean_house_data
WHERE TRY_CONVERT(INT, [year]) IN (1992, 2000, 2008, 2016, 2024)
  AND [state] IN (
      'TEXAS',
      'GEORGIA',
      'ARIZONA',
      'CALIFORNIA',
      'IOWA',
      'MICHIGAN',
      'NEW YORK',
      'NORTH DAKOTA',
      'OKLAHOMA',
      'PENNSYLVANIA',
      'SOUTH CAROLINA',
      'NORTH CAROLINA',
      'SOUTH DAKOTA',
      'VERMONT',
      'WISCONSIN'
  )
  AND stage = 'GEN'
  AND special = 'FALSE'
  AND party IN ('DEMOCRAT', 'REPUBLICAN')
ORDER BY
    TRY_CONVERT(INT, [year]),
    [state],
    TRY_CONVERT(INT, district);

-- Version 3: narrowed to 3 hand-picked districts per state.
-- District 0 = at-large state (ND, SD, VT).
SELECT
    [year],
    [state],
    district,
    party,
    candidatevotes,
    totalvotes
FROM dbo.clean_house_data
WHERE TRY_CONVERT(INT, [year]) IN (1992, 2000, 2008, 2016, 2024)
  AND stage = 'GEN'
  AND special = 'FALSE'
  AND party IN ('DEMOCRAT', 'REPUBLICAN')
  AND (
      ([state] = 'TEXAS' AND district IN (2, 10, 18))
      OR ([state] = 'GEORGIA' AND district IN (2, 8, 12))
      OR ([state] = 'ARIZONA' AND district IN (1, 6, 9))
      OR ([state] = 'CALIFORNIA' AND district IN (12, 15, 50))
      OR ([state] = 'IOWA' AND district IN (1, 2, 4))
      OR ([state] = 'MICHIGAN' AND district IN (3, 8, 13))
      OR ([state] = 'NEW YORK' AND district IN (8, 20, 23))
      OR ([state] = 'NORTH DAKOTA' AND district = 0)
      OR ([state] = 'OKLAHOMA' AND district IN (1, 3, 5))
      OR ([state] = 'PENNSYLVANIA' AND district IN (3, 10, 13))
      OR ([state] = 'SOUTH CAROLINA' AND district IN (1, 3, 6))
      OR ([state] = 'NORTH CAROLINA' AND district IN (1, 4, 13))
      OR ([state] = 'SOUTH DAKOTA' AND district = 0)
      OR ([state] = 'VERMONT' AND district = 0)
      OR ([state] = 'WISCONSIN' AND district IN (2, 4, 8))
  )
ORDER BY
    TRY_CONVERT(INT, [year]),
    [state],
    district,
    party;


/* ----------------------------------------------------------------------------
   SECTION 4: Build DistrictElectionMargins
   Pivots the two-party rows into one row per district-year, then computes
   the winner and the margin (in votes and as % of total votes).
   ---------------------------------------------------------------------------- */

WITH DistrictVotes AS (
    SELECT
        TRY_CONVERT(INT, [year]) AS election_year,
        [state],
        TRY_CONVERT(INT, district) AS district,

        -- Pivot: one column of votes per party. MAX() collapses the
        -- long format (one row per candidate) into a single value.
        MAX(CASE WHEN party = 'DEMOCRAT'
            THEN TRY_CONVERT(BIGINT, candidatevotes) END) AS dem_votes,

        MAX(CASE WHEN party = 'REPUBLICAN'
            THEN TRY_CONVERT(BIGINT, candidatevotes) END) AS rep_votes,

        MAX(TRY_CONVERT(BIGINT, totalvotes)) AS total_votes

    FROM dbo.clean_house_data

    WHERE TRY_CONVERT(INT, [year]) IN (1992, 2000, 2008, 2016, 2024)
      AND stage = 'GEN'
      AND special = 'FALSE'
      AND party IN ('DEMOCRAT', 'REPUBLICAN')

      -- Same 3-districts-per-state sample as Section 3, Version 3
      AND (
          ([state] = 'TEXAS' AND district IN (2, 10, 18))
          OR ([state] = 'GEORGIA' AND district IN (2, 8, 12))
          OR ([state] = 'ARIZONA' AND district IN (1, 6, 9))
          OR ([state] = 'CALIFORNIA' AND district IN (12, 15, 50))
          OR ([state] = 'IOWA' AND district IN (1, 2, 4))
          OR ([state] = 'MICHIGAN' AND district IN (3, 8, 13))
          OR ([state] = 'NEW YORK' AND district IN (8, 20, 23))
          OR ([state] = 'NORTH DAKOTA' AND district = 0)
          OR ([state] = 'OKLAHOMA' AND district IN (1, 3, 5))
          OR ([state] = 'PENNSYLVANIA' AND district IN (3, 10, 13))
          OR ([state] = 'SOUTH CAROLINA' AND district IN (1, 3, 6))
          OR ([state] = 'NORTH CAROLINA' AND district IN (1, 4, 13))
          OR ([state] = 'SOUTH DAKOTA' AND district = 0)
          OR ([state] = 'VERMONT' AND district = 0)
          OR ([state] = 'WISCONSIN' AND district IN (2, 4, 8))
      )

    GROUP BY
        TRY_CONVERT(INT, [year]),
        [state],
        TRY_CONVERT(INT, district)
)

SELECT
    election_year,
    [state],
    district,
    dem_votes,
    rep_votes,
    total_votes,

    -- Winner = party with more votes (ties flagged explicitly)
    CASE
        WHEN dem_votes > rep_votes THEN 'DEMOCRAT'
        WHEN rep_votes > dem_votes THEN 'REPUBLICAN'
        ELSE 'TIE'
    END AS winning_party,

    -- Raw vote margin between the two parties
    ABS(dem_votes - rep_votes) AS margin_votes,

    -- Margin as a % of ALL votes cast (including third parties).
    -- NULLIF avoids divide-by-zero; 100.0 forces decimal division.
    CAST(
        ABS(dem_votes - rep_votes) * 100.0 /
        NULLIF(total_votes, 0)
        AS DECIMAL(6,2)
    ) AS margin_percentage

INTO dbo.DistrictElectionMargins   -- materialize result as a new table

FROM DistrictVotes
-- Drop districts lacking a D or R candidate (e.g., uncontested races)
WHERE dem_votes IS NOT NULL
  AND rep_votes IS NOT NULL;

-- Confirm how many district-year rows were created
SELECT COUNT(*) AS total_records
FROM dbo.DistrictElectionMargins;

-- Spot-check the first 20 rows
SELECT TOP 20 *
FROM dbo.DistrictElectionMargins
ORDER BY election_year, [state], district;


/* ----------------------------------------------------------------------------
   SECTION 5: Explore the Census data and develop the join key
   Census_info is keyed by GEOID_CD11820 (state FIPS + district number,
   stored as an integer, e.g., 4802 = Texas district 2).
   ---------------------------------------------------------------------------- */

-- List all tables in the database (quick inventory)
SELECT TABLE_NAME
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_TYPE = 'BASE TABLE'
ORDER BY TABLE_NAME;

-- Inspect how GEOIDs are structured by padding/splitting them.
-- This exploration informed the CASE-based join key used further below.
SELECT
    GEOID_CD11820,
    RIGHT('000' + CAST(GEOID_CD11820 AS VARCHAR(3)), 3) AS geoid_formatted,
    LEFT(RIGHT('000' + CAST(GEOID_CD11820 AS VARCHAR(3)), 3), 2) AS state_fips,
    RIGHT(RIGHT('000' + CAST(GEOID_CD11820 AS VARCHAR(3)), 3), 1) AS district_code,
    BLK_POP_CD,
    URBAN_BLK_POP,
    URBAN_BLK_POP_PCT
FROM dbo.Census_info;

-- FIRST join attempt: matches on district number only (state is not part of
-- the key), so it does not link rows to the correct state. Replaced by the
-- state-aware join in the next query.
SELECT
    e.election_year,
    e.[state],
    e.district,
    e.winning_party,
    e.margin_percentage,
    c.BLK_POP_CD AS total_population,
    c.URBAN_BLK_POP AS urban_population,
    c.URBAN_BLK_POP_PCT AS urban_population_pct,
    c.RURAL_BLK_POP_PCT AS rural_population_pct
FROM dbo.DistrictElectionMargins e
LEFT JOIN dbo.Census_info c
    ON RIGHT('000' + CAST(c.GEOID_CD11820 AS VARCHAR(3)), 2)
       = RIGHT('00' + CAST(e.district AS VARCHAR(2)), 2)
ORDER BY e.election_year, e.[state], e.district;

-- SECOND join attempt (state-aware): build the GEOID from state FIPS * 100
-- plus district number. FIPS codes: AZ=04, CA=06, GA=13, IA=19, MI=26,
-- NY=36, NC=37, ND=38, OK=40, PA=42, SC=45, SD=46, TX=48, VT=50, WI=55.
-- At-large states (ND, SD, VT) use FIPS*100 with no district added.
SELECT
    e.election_year,
    e.[state],
    e.district,
    e.winning_party,
    e.margin_percentage,
    c.BLK_POP_CD AS total_population,
    c.URBAN_BLK_POP AS urban_population,
    c.URBAN_BLK_POP_PCT AS urban_population_pct,
    c.RURAL_BLK_POP_PCT AS rural_population_pct
FROM dbo.DistrictElectionMargins e
LEFT JOIN dbo.Census_info c
    ON c.GEOID_CD11820 =
       CASE e.[state]
           WHEN 'ARIZONA' THEN 400 + e.district
           WHEN 'CALIFORNIA' THEN 600 + e.district
           WHEN 'GEORGIA' THEN 1300 + e.district
           WHEN 'IOWA' THEN 1900 + e.district
           WHEN 'MICHIGAN' THEN 2600 + e.district
           WHEN 'NEW YORK' THEN 3600 + e.district
           WHEN 'NORTH CAROLINA' THEN 3700 + e.district
           WHEN 'NORTH DAKOTA' THEN 3800
           WHEN 'OKLAHOMA' THEN 4000 + e.district
           WHEN 'PENNSYLVANIA' THEN 4200 + e.district
           WHEN 'SOUTH CAROLINA' THEN 4500 + e.district
           WHEN 'SOUTH DAKOTA' THEN 4600
           WHEN 'TEXAS' THEN 4800 + e.district
           WHEN 'VERMONT' THEN 5000
           WHEN 'WISCONSIN' THEN 5500 + e.district
       END
ORDER BY e.election_year, e.[state], e.district;

-- Diagnostic: show election rows that FAILED to match a census row.
-- Any results here point to bad GEOIDs or districts missing from Census_info.
SELECT
    e.election_year,
    e.[state],
    e.district,
    e.winning_party,
    e.margin_percentage
FROM dbo.DistrictElectionMargins e
LEFT JOIN dbo.Census_info c
    ON c.GEOID_CD11820 =
       CASE e.[state]
           WHEN 'ARIZONA' THEN 400 + e.district
           WHEN 'CALIFORNIA' THEN 600 + e.district
           WHEN 'GEORGIA' THEN 1300 + e.district
           WHEN 'IOWA' THEN 1900 + e.district
           WHEN 'MICHIGAN' THEN 2600 + e.district
           WHEN 'NEW YORK' THEN 3600 + e.district
           WHEN 'NORTH CAROLINA' THEN 3700 + e.district
           WHEN 'NORTH DAKOTA' THEN 3800
           WHEN 'OKLAHOMA' THEN 4000 + e.district
           WHEN 'PENNSYLVANIA' THEN 4200 + e.district
           WHEN 'SOUTH CAROLINA' THEN 4500 + e.district
           WHEN 'SOUTH DAKOTA' THEN 4600
           WHEN 'TEXAS' THEN 4800 + e.district
           WHEN 'VERMONT' THEN 5000
           WHEN 'WISCONSIN' THEN 5500 + e.district
       END
WHERE c.BLK_POP_CD IS NULL
ORDER BY e.[state], e.district, e.election_year;

-- Check how the at-large states (ND=38xx, SD=46xx, VT=50xx) are coded in
-- Census_info, since they were the most likely to fail the join.
SELECT
    GEOID_CD11820,
    BLK_POP_CD,
    URBAN_BLK_POP,
    URBAN_BLK_POP_PCT
FROM dbo.Census_info
WHERE GEOID_CD11820 BETWEEN 3800 AND 3899
   OR GEOID_CD11820 BETWEEN 4600 AND 4699
   OR GEOID_CD11820 BETWEEN 5000 AND 5099
ORDER BY GEOID_CD11820;

-- Peek at the lowest GEOIDs to confirm the numbering scheme
SELECT TOP 30
    GEOID_CD11820
FROM dbo.Census_info
ORDER BY GEOID_CD11820;

-- Full look at the census table (all columns)
SELECT * 
FROM dbo.Census_info


/* ----------------------------------------------------------------------------
   SECTION 6: Build the final analysis table
   Joins election results with district urban/rural population and land
   area, using the validated GEOID mapping from Section 5.
   ---------------------------------------------------------------------------- */

SELECT
    -- Election results
    e.election_year,
    e.[state],
    e.district,
    e.dem_votes,
    e.rep_votes,
    e.total_votes,
    e.winning_party,
    e.margin_votes,
    e.margin_percentage,

    -- Population: total, urban, rural
    c.BLK_POP_CD AS total_population,
    c.URBAN_BLK_POP AS urban_population,
    c.RURAL_BLK_POP AS rural_population,

    CAST(ROUND(c.URBAN_BLK_POP_PCT, 2) AS DECIMAL(5,2))
        AS urban_population_pct,

    CAST(ROUND(c.RURAL_BLK_POP_PCT, 2) AS DECIMAL(5,2))
        AS rural_population_pct,

    -- Land area: total, urban, rural (sq mi and % of district)
    c.AREALAND_SQMI AS total_land_sqmi,
    c.URBAN_AREALAND_SQMI AS urban_land_sqmi,
    c.URBAN_AREALAND_PCT AS urban_land_pct,
    c.RURAL_AREALAND_SQMI AS rural_land_sqmi,
    c.RURAL_AREALAND_PCT AS rural_land_pct

INTO dbo.ElectionUrbanizationAnalysis

FROM dbo.DistrictElectionMargins e

-- LEFT JOIN keeps every election row even if census data is missing,
-- so unmatched rows show up as NULLs rather than silently disappearing.
-- Note: Census_info uses the 2018-2020 district boundaries
-- (GEOID_CD11820), so the same census profile is applied to every
-- election year in the sample.
LEFT JOIN dbo.Census_info c
    ON c.GEOID_CD11820 =
       CASE e.[state]
           WHEN 'ARIZONA' THEN 400 + e.district
           WHEN 'CALIFORNIA' THEN 600 + e.district
           WHEN 'GEORGIA' THEN 1300 + e.district
           WHEN 'IOWA' THEN 1900 + e.district
           WHEN 'MICHIGAN' THEN 2600 + e.district
           WHEN 'NEW YORK' THEN 3600 + e.district
           WHEN 'NORTH CAROLINA' THEN 3700 + e.district
           WHEN 'NORTH DAKOTA' THEN 3800
           WHEN 'OKLAHOMA' THEN 4000 + e.district
           WHEN 'PENNSYLVANIA' THEN 4200 + e.district
           WHEN 'SOUTH CAROLINA' THEN 4500 + e.district
           WHEN 'SOUTH DAKOTA' THEN 4600
           WHEN 'TEXAS' THEN 4800 + e.district
           WHEN 'VERMONT' THEN 5000
           WHEN 'WISCONSIN' THEN 5500 + e.district
       END;

-- Quick check: 20 districts with the lowest urban share, with margins
SELECT TOP 20
    [state],
    district,
    urban_population_pct,
    rural_population_pct,
    margin_percentage
FROM dbo.ElectionUrbanizationAnalysis
ORDER BY urban_population_pct;

-- Preview the new table
SELECT TOP 10 *
FROM dbo.ElectionUrbanizationAnalysis;


/* ----------------------------------------------------------------------------
   SECTION 7: Table cleanup
   ---------------------------------------------------------------------------- */

-- Set land percentages to two decimal places
ALTER TABLE dbo.ElectionUrbanizationAnalysis
ALTER COLUMN urban_land_pct DECIMAL(5,2) NULL;

ALTER TABLE dbo.ElectionUrbanizationAnalysis
ALTER COLUMN rural_land_pct DECIMAL(5,2) NULL;

-- Remove square-mile columns (percentages are enough for analysis)
ALTER TABLE dbo.ElectionUrbanizationAnalysis
DROP COLUMN
    total_land_sqmi,
    urban_land_sqmi,
    rural_land_sqmi;

-- Confirm the final column layout
SELECT TOP 20 *
FROM dbo.ElectionUrbanizationAnalysis;


/* ----------------------------------------------------------------------------
   SECTION 8: Summary / validation queries
   ---------------------------------------------------------------------------- */

-- Overall validation:
--   total_records vs. matched_records shows how many rows found census data
--   (COUNT(column) skips NULLs, so a gap means unmatched joins).
SELECT
    COUNT(*) AS total_records,
    COUNT(urban_population_pct) AS matched_records,
    COUNT(DISTINCT election_year) AS election_cycles,
    COUNT(DISTINCT [state]) AS states,
    AVG(margin_percentage) AS average_margin,
    MIN(margin_percentage) AS smallest_margin,
    MAX(margin_percentage) AS largest_margin
FROM dbo.ElectionUrbanizationAnalysis;

-- Same validation, broken out by election year
SELECT
    election_year,
    COUNT(*) AS election_records,
    COUNT(urban_population_pct) AS matched_records,
    AVG(margin_percentage) AS average_margin
FROM dbo.ElectionUrbanizationAnalysis
GROUP BY election_year
ORDER BY election_year;

-- Final full dump of the analysis table, in a readable order
SELECT *
FROM dbo.ElectionUrbanizationAnalysis
ORDER BY election_year, [state], district;
