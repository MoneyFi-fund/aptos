
# MoneyFi Contract

## Architecture

![alt text](docs/architecture.svg)

## Development

### 1. Setup

- Init profile: `aptos init`
- Run `setup.sh` to download dependencies

### 2. Compile & testing

- `aptos move compile`
- `aptos move test`

### 3. Deployment

- Deploy: `aptos move create-object-and-publish-package --address-name moneyfi --included-artifacts none `
- Upgrade: `aptos move upgrade-object-package --object-address $DEPLOYED_ADDRESS --included-artifacts none `
