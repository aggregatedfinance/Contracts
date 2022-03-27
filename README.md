# Contracts
All smart contracts for the [aggregated.finance](https://aggregated.finance/) (AGFI) project.

[Follow the AGFI blog for updates](https://blog.aggregated.finance/).

## Deployed Contracts

### Audit

[Certik Audit](https://www.certik.com/projects/aggregated-finance)

### Aggregated Finance Token

Verified Contract: [0x0BE4447860DdF283884BBaa3702749706750b09e](https://etherscan.io/address/0x0be4447860ddf283884bbaa3702749706750b09e#code)

Deployer: [0xfEB8f237873e846d9Ddbf8A9477519AE3219984c](https://etherscan.io/address/0xfeb8f237873e846d9ddbf8a9477519ae3219984c)

#### Known Issues

* There are some minor audit findings for this contract. These have to be accepted as the contract is already deployed on mainnet.
* The marketing wallet address is not modifiable.
* [getRValues](https://github.com/aggregatedfinance/Contracts/blob/main/contracts/AggregatedFinance.sol#L408) does not sub `tFee` from `rTransferAmount`. Without a significant percentage of supply allocated to the burn address at launch this can cause supply inflation.
* [uniswapV2Pair](https://github.com/aggregatedfinance/Contracts/blob/main/contracts/AggregatedFinance.sol#L254) defined in `transfer` accounts for the liquidity pair but not all later Uniswap routers, and so some `buy` transfers on the Uniswap pair may be accidentally treated as `sell` transfers and be taxed incorrectly.

### Timelock

Verified Contract: [0x55E5db7bFEd89541720bEB66150bc3cfdC76362F](https://etherscan.io/address/0x55e5db7bfed89541720beb66150bc3cfdc76362f)

Deployer: [0xfEB8f237873e846d9Ddbf8A9477519AE3219984c](https://etherscan.io/address/0xfeb8f237873e846d9ddbf8a9477519ae3219984c)

### AGFI Governor

Verified Contract: [0x96491ac1F680c76EB8610b4389b8Dfa6F3a3C872](https://etherscan.io/address/0x96491ac1F680c76EB8610b4389b8Dfa6F3a3C872)

Deployer: [0xfEB8f237873e846d9Ddbf8A9477519AE3219984c](https://etherscan.io/address/0xfeb8f237873e846d9ddbf8a9477519ae3219984c)

#### Known Issues

* Delegation does not permit delegation to other addresses, so therefore it does not actually delegate. Proper delegation will be added in future versions.
