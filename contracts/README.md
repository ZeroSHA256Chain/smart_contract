# DEDUAssess - Decentralized EDU Assessment Contract

Install hardhat

https://hardhat.org/hardhat-runner/docs/getting-started

Then:
```shell
yarn
```
or
```shell
npm install .
```

Run tests
```shell
npx hardhat test
```
To deploying and interact with contract on localhost (rpc: http://127.0.0.1:8545/):
```shell
npx hardhat node
npx hardhat ignition deploy ./ignition/modules/DEDUAssess.sol.js --network localhost
```

To deploying contract on testnet you need to provide `API_KEY` and `PRIVATE_KET` in `hardhat.config.js` and run:
```shell
npx hardhat ignition deploy ./ignition/modules/DEDUAssess.sol.js --network polygon_amoy
```

Latest deployed contract address:
```
0x2A4c1D303224A700BA8d7cC2d56fE3112c14D41B
```
On scaner:
https://amoy.polygonscan.com/address/0x2A4c1D303224A700BA8d7cC2d56fE3112c14D41B