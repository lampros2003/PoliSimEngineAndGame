# Stage S16: after the third playtest

## Context

The owner played the S15 game on 2026-11-16 and reported:

1. **A big error:** political capital is not visible on the main screen. (S14.1 took it and
   approval off the top bar as doubles of the centre. That was wrong: capital is what every
   decision is paid in, and the centre is covered whenever a popup is open.)
2. **Belief groups** should rest on actual data, even if broad. Their sizes were judgements.
3. The interface needs **a pass to improve and polish** it.
4. Ideas for what else to add (answered in conversation, not built in this stage).

## Decisions

| Question | Decision |
|---|---|
| Political capital | Back on the top bar, always: what there is, and beside it what the bills waiting will cost. It turns red when the bills waiting cannot all be paid for. Approval returns beside it. The centre keeps both |
| What a popup shows of it | Every place a bill can be made (a policy's popup, the Add policy sheet) shows capital before and after |
| Belief groups' sizes | From More in Common's "Seven Segments" of the British public (Shattered Britain, July 2025): Progressive Activists 12%, Incrementalist Left 21%, Established Liberals 9%, Sceptical Scrollers 10%, Rooted Patriots 20%, Traditional Conservatives 8%, Dissenting Disruptors 20%. Each belief group is a stated mix of segments, and the segments' published profiles by age, income and place shape who is in it. Patriots also use YouGov's "very patriotic" by age (32% of adults; 15% of those aged 18 to 24, 49% of those over 60). The mapping from segments to groups is a judgement and is written down as one; the sizes and profiles are the publishers' |
| Balance after it | The stances' strength is tuned again so the strategies stay where S15.2 left them |
| Group names | Tried once more: short names set along each arc's outer edge, for all groups or none at a window size |
| The polish pass | Every screen and state is photographed at 1366x768 and 1920x1080 and gone through against one checklist: alignment to a spacing scale, a type scale with no text under 12 px, contrast, one word for one thing ("statistic", not "indicator" in one place and "statistic" in another), a visible response to every pointer and key, targets no smaller than 32 px, numbers formatted one way, nothing clipped or orphaned. What is found is listed, fixed, and photographed again |

## Stages

| # | Stage | Lane | Done when |
|---|---|---|---|
| S16.1 | Capital and approval on the top bar; the polish pass | Client | A check that capital is on the top bar with a popup open and turns red when bills cannot be paid; the list of faults found and fixed; every check passes |
| S16.2 | Belief groups from published segments | Model, in a private copy | Sources opened and cited; the base month and hindcast unchanged; the strategies within ten seats of S15.2's |

## Status

| # | Status |
|---|---|
| S16.1 | Done. Approval and political capital lead the top bar again, capital with what the bills waiting will cost, red with "N short" when they cost more than there is; they are the last figures to give way and the bar is drawn above every popup and sheet. A policy's popup and each Add policy row say what a bill would leave (`tests/capital_check.gd` proves the bar readable over a popup and every sheet at 1366x768 and 1920x1080). Group names along the arcs were tried again and left off: only 22 of 26 fit even in two rows, and they run under the statistics' labels. The polish pass photographed thirty states at two sizes, listed 24 faults and fixed 20: the top bar no longer pushes its buttons off a narrow window; a game that has ended says so; a popup no longer half covers its node's tag; folds have triangles that can be seen; a question's first answer no longer looks recommended; menu rows are 32 px; "statistic" and "group of voters" are the words everywhere; tooltips name their keys; empty states say something. Left: the other headline figures give way to approval and capital (Budget balance and Debt to GDP even at 1920 wide); the Budget's totals are indented with spaces; no measured contrast check, spacing audit or focus-order walk was done |
| S16.2 | Done. The six belief groups are stated mixes of More in Common's seven segments (`tools/uk/segments.toml`): Socialists 23.4% of adults (20% before), Capitalists 13.8% (15%), Liberals 26.4% (25%), Conservatives 32.0% (30%), Environmentalists 17.9% (12%), Patriots 30.4% (25%), Patriots also shaped by YouGov's age gradient. The segments' sizes are the publisher's; who holds each by age, income and region is a reading of the publisher's descriptions, and the mix per group is a judgement (`models/uk/politics/README.md`). `belief_effect` is 0.25; one clear move on order gives Conservatives +1.5, Liberals -1.3, Patriots +2.2. Every strategy is within ten seats of S15.2; law and order 358. Not opened: the full report's demographic tables, British Social Attitudes |
