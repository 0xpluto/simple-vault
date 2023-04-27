# Simple Vault

Users can deposit eth into the contract to lock for minimum a week. There are week long time periods for users to deposit eth and collect rewards from.

This was just a fun silly little experiment. This contract should not be used in production (it doesn't make any money)

## Notes

* Rewards will not finish collecting until team calls releaseRewards. Only until then will a new collecting period start

* If the team does not releaseRewards after a week of collecting during the current period then users will keep depositing into the previous week

## Security Considerations

* Contract owner should submit the releaseRewards transaction to a private bundle to prevent sandwiching this transaction and collecting majority of rewards for given time period. For example, there is 10 total eth in a time period lock up. The owner submits the tx to release rewards. Searcher front runs this with a majority allocation deposit of eth. After the rewards released they claim their rewards and other users unknowningly get very little rewards.
