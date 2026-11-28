# Data licences for the first country (United Kingdom)

The roadmap makes the first country conditional on being allowed to ship what we derive
from its data in a commercial game. The owner chose the United Kingdom on 2026-11-14.

**Status on 2026-11-14: passed for the sources stage S3 needs.** The publishers' own pages
were read on that date (they were reachable once the environment allowed their hosts),
and the relevant sentences are quoted below. Sources marked as closed or unchecked must not
be used until that changes.

## Rule for all sources

- Every input has a line in the provenance manifest (`models/uk/data/MANIFEST.toml` from
  stage S3.0): what it is, where it came from, the licence, the attribution wording, the
  release date and a checksum.
- Open Government Licence data may be shipped, including extracts, with the attribution
  statement. The game's credits screen and the repository carry it.
- Survey microdata are never shipped and are not used without the owner's written
  permission. The household sample is synthetic, built from published tables.

## Confirmed from the publisher's page

| Source | Needed for | Licence | Commercial reuse | What the page says (2026-11-14) |
|---|---|---|---|---|
| Office for National Statistics: all time-series datasets (UK Economic Accounts, Quarterly National Accounts, Public Sector Finances, Labour Market Statistics), population estimates and projections, input-output tables | Sector accounts, public finances, labour market, cohort table, industries | Open Government Licence v3.0 | **Yes**, with attribution | "Most content on this website is subject to Crown copyright protection and is published under the Open Government Licence (OGL)." The exemptions listed are third-party photographs, illustrations and videos. ([ONS terms](https://www.ons.gov.uk/help/termsandconditions)) |
| Open Government Licence v3.0 itself | The terms above | — | — | "You are free to … exploit the Information commercially and non-commercially … You must … acknowledge the source … If the Information Provider does not provide a specific attribution statement, you must use the following: Contains public sector information licensed under the Open Government Licence v3.0." Not covered: personal data, logos, third-party rights. ([OGL v3](https://www.nationalarchives.gov.uk/doc/open-government-licence/version/3/)) |
| ONS geography (boundaries and lookups) | Regions; and, from stage S18.4, the map of the country the game draws (`models/uk/map`, the ITL1 boundaries of January 2025) | OGL v3.0 | **Yes**, with "Source: Office for National Statistics licensed under the Open Government Licence v.3.0" and, for boundaries, "Contains OS data © Crown copyright and database right [year]" (read again on 2026-11-28: "Digital boundary products and reference maps are supplied under the Open Government Licence. You must use the following copyright statements when you reproduce or use this material"). Both are in the map file and shown in the game. Postcode products need Royal Mail attribution, and Northern Ireland postcodes need a separate commercial licence; the map uses neither | ([ONS geography licences](https://www.ons.gov.uk/methodology/geography/licences)) |
| Nomis (ONS labour market and census tables) | Regional labour market and population | OGL v3.0 | **Yes**: "anyone wishing to use or re-use ONS material, whether commercially or privately, may do so freely without a specific application for a licence, subject to the conditions of the OGL" | ([Nomis copyright](https://www.nomisweb.co.uk/home/copyright.asp)) |
| Office for Budget Responsibility: forecasts, ready reckoners, the published macroeconomic model code | Validation targets, borrowed behavioural equations | OGL | **Yes**: "You may use and re-use the information featured on this website (not including logos) free of charge in any format or medium, under the terms of the Open Government Licence." The model code is provided "as is" and its results "do not constitute the views of the OBR" | ([OBR copyright](https://obr.uk/copyright/), [OBR model](https://obr.uk/forecasts-in-depth/obr-macroeconomic-model/)) |
| Bank of England Database (interest rates, money and credit) | Bank Rate, gilt yields, lending | OGL | **Yes, for the database**: "Reproduction of data in the Database is subject to the terms of the UK Open Government Licence." Excluded: "selected exchange rate data and series … reproduced by the Bank under licence from third parties" | ([Bank of England legal](https://www.bankofengland.co.uk/legal)) |
| House of Commons election results | The 2024 general election by constituency (stage S5): votes by party only, candidates' names dropped as personal data | Open Parliament Licence | **Yes**, conditions not yet read: "Re-use our content freely and flexibly with only a few conditions under the Open Parliament Licence." The licence text is on parliament.uk, which this environment does not reach (refused again on 2026-11-14). **Owner to confirm** that the Open Parliament Licence, like the OGL it follows, allows commercial reuse with the attribution "Contains Parliamentary information licensed under the Open Parliament Licence v3.0" | ([election results](https://electionresults.parliament.uk/)) |
| ONS Census 2021 by 2024 Westminster constituency (custom datasets API) | Age and economic activity by constituency, for the voters' age pattern (stage S5) | OGL v3.0 | **Yes**, under the ONS terms above | ([ONS create a custom dataset](https://www.ons.gov.uk/datasets/create)) |

## Closed or restricted

| Source | Status | Consequence |
|---|---|---|
| Bank of England website content other than the database (working papers, including its stock-flow model of the UK; publications; charts) | **Non-commercial only without permission**: "You may … download, display or print the Resources for personal use or internal use within an individual organisation for non-commercial purposes." | Read for ideas; do not reproduce text, figures or code from it |
| Family Resources Survey microdata (UK Data Service) | Commercial use needs the data owner's approval (catalogue records, not re-read) | Not used. The household sample is built from published tables |
| British Election Study survey data | Commercial use needs permission (catalogue records, not re-read) | Not used unless the owner obtains permission. Voter behaviour is estimated from published results and tables |

## Not checked yet

- The Open Parliament Licence's conditions (parliament.uk is not on the environment's
  allowed hosts; needed before stage S5).
- HM Revenue and Customs and Department for Work and Pensions statistics on gov.uk
  (reachable now; expected OGL; check when a series from them is first used).
- National Records of Scotland and NISRA for Scottish and Northern Irish census tables.
- Eurostat and OECD tables for the trading blocs (hosts not allowed yet; needed in S6).
