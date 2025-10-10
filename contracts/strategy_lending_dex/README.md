![](../docs/deploy_strategy.png)

## Deploy

```sh
LENDING_ADDR=0x111
DEX_ADDR=0x222
aptos move deploy-object --address-name strategy_lending_dex --named-addresses "moneyfi_lending=$LENDING_ADDR,moneyfi_dex=$DEX_ADDR"
```
