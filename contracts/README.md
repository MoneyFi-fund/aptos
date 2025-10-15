
# MoneyFi Contract

## Development

### 1. Compile & testing

- `aptos move compile`
- `aptos move test`

### 2. Deployment

- Deploy: `aptos move create-object-and-publish-package --address-name moneyfi --included-artifacts none `
- Upgrade: `aptos move upgrade-object-package --object-address $DEPLOYED_ADDRESS --included-artifacts none `
- Create payload: `aptos move build-publish-payload --json-output-file payload.json --included-artifacts none --chunked-publish --override-size-check`
