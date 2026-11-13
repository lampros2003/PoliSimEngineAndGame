# Data licences for the provisional first country (United Kingdom)

The roadmap makes the choice of first country conditional on being allowed to ship what
we derive from its data in a commercial game. This is the state of that check on
2026-11-13.

**Status: not yet passed.** Nothing found blocks the United Kingdom, but every row below
rests on a search-result summary of the publisher's page, not on a reading of the page or
the licence text. Each must be opened and confirmed, and the confirmation recorded here,
before any real data enters the repository (stage S3).

## Rule for all sources

Ship derived parameters and a synthetic population generated from published tables. Never
ship a third party's raw tables or survey microdata. Keep one line per input here: what
it is, where it came from, the licence, the attribution wording, and the date checked.

## Sources

| Source | Needed for | Licence found | Commercial reuse | Confidence | Action |
|---|---|---|---|---|---|
| Office for National Statistics: national and sector accounts, supply-use and input-output tables, population estimates and projections, census tables, labour market, regional accounts | sector balance sheets, industries, cohort table, regions | Crown copyright, Open Government Licence v3.0, with a published list of exemptions | permitted with attribution | search summary of [ONS terms](https://www.ons.gov.uk/help/terms-conditions) and the [Statistics Authority copyright page](https://uksa.statisticsauthority.gov.uk/copyright) | Read the exemptions list. The Statistics Authority page distinguishes reuse from repackaging and redistributing; confirm that shipping derived parameters is plain reuse. |
| ONS geography products (region and constituency boundaries, lookups) | regions, electoral map | Open Government Licence v3.0 with extra notices | permitted, but some products carry Ordnance Survey and Royal Mail rights, and Northern Ireland postcodes need a separate commercial licence | search summary of [ONS geography licences](https://www.ons.gov.uk/methodology/geography/licences) | Use boundary and lookup products only; avoid postcode products. |
| Bank of England statistical database | interest rates, money and credit, the published stock-flow model as a reference | Open Government Licence for data in the Bank's database | permitted with attribution; third-party series (such as LSEG data) excluded | search summary of the [Bank's legal page](https://www.bankofengland.co.uk/legal) | Check each series used is the Bank's own. |
| Office for Budget Responsibility: forecasts, ready reckoners, macro model documentation and code | validation targets, borrowed behavioural equations | publications under Open Government Licence v3.0 unless stated otherwise | permitted for publications | search summary of an OBR publication's licence notice; the terms for the model code were **not found** | Read the [OBR legal pages](https://obr.uk/legal-pages/) for the model code specifically. |
| House of Commons Library election results, 1918 onwards | back-casting elections, constituency structure | Open Parliament Licence | permitted with attribution | search summary of the [election results site](https://electionresults.parliament.uk/) | Read the Open Parliament Licence text. |
| OECD inter-country input-output tables | industry structure, trade with partner blocs | OECD content from 1 July 2024 is CC BY 4.0 by default; earlier content on similar terms | permitted with attribution by default | search summary of the [OECD open-by-default policy](https://oecd.org/en/about/oecd-open-by-default-policy.html); **no licence statement found for this dataset itself** | Read the dataset's ReadMe at [oe.cd/icio](http://oe.cd/icio). |
| Family Resources Survey microdata (UK Data Service) | household incomes and benefits at record level | End User Licence; a Secure Access version also exists | **not without the data owner's approval**; the Secure Access version forbids it | search summary of UK Data Service catalogue records | **Do not use.** Build the household sample from published tables instead. |
| British Election Study survey data | voter attitudes by demographic group | BES terms plus UK Data Service licence | **not without the data owner's permission** | search summary of [BES terms](https://britishelectionstudy.com/terms-and-conditions-of-data-use) and UK Data Service records | **Do not use without written permission.** Either ask the BES team, or estimate voter behaviour from published results and published tables only. |

## Not checked yet

- HM Revenue and Customs and Department for Work and Pensions published statistics (tax
  receipts by band, benefit caseloads and rates). Expected to be Open Government Licence;
  not searched.
- Scotland's and Northern Ireland's census publishers (National Records of Scotland,
  NISRA). Their tables are separate from the ONS census for England and Wales.
- Eurostat tables for the partner blocs.
- The open synthetic population of England mentioned in the research report, and the
  licence of the rule definitions in open tax-benefit models. The research report notes
  that one such engine is AGPL, which rules out linking it into a closed game; reading it
  as a reference is a separate question.
- Whether estimating parameters offline from a research-only dataset, without shipping
  the data, counts as commercial use. The UK Data Service definition found in the search
  (research with a direct objective of generating revenue) suggests it does. This is a
  legal question and should be treated as closed until answered.

## What this means for the design

1. The aggregate side of a UK model (accounts, industries, demography, regions, election
   results) looks buildable from openly licensed official statistics.
2. The household sample must be synthetic, generated from published tables. That was the
   plan already; the Family Resources Survey terms make it a requirement.
3. The voter model cannot lean on the British Election Study without permission. Election
   back-casts can still use the Commons Library results.
4. The United Kingdom has 12 top-level statistical regions (ITL1), which sits at the low
   end of the 10 to 50 band the ballot asked for. This figure is from memory, not from
   the searches above.
