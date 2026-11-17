# Mountain rating history

`ratings` holds each voter's current score for a candidacy on the mountain's
0–500 scale. An update records the previous score in `rating_archives`.
Clearing a saved score records its final persisted value with reason
`Removed rating` before deleting the current row. The archive and deletion
share a transaction, so a failed or rolled-back removal leaves neither change.

Draft adjustments do not create archives. Saving the draft applies its changes
and clears to the stored ratings. Approval still means that the saved score is
strictly greater than that voter's saved baseline for the race.

Deleting a voter removes their personal rating archives. Deleting a candidacy
also removes its archives under the existing association policy. Those cascading
removals do not create new archives.

This history remains in Ascent. No transmission to Rizz or new history endpoint
is added. Future permissioned transmission of general app observations is tracked
in [MIC-70](https://linear.app/micrizz/issue/MIC-70/connect-app-owned-rating-history-to-rizz-preferences-after-sharing-is);
votes and voting baselines are excluded from that feed. A dedicated vote ledger
is separate work from this score-history fix.
