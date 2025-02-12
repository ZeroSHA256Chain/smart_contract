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
npx hardhat ignition deploy ./ignition/modules/DEDUAssess.js --network localhost
```

To deploying contract on testnet you need to provide `API_KEY` and `PRIVATE_KET` in `.env` or hardcode in `hardhat.config.js` and run:
```shell
npx hardhat ignition deploy ./ignition/modules/DEDUAssess.js --network polygon_amoy
```

Latest deployed contract address:
```
0xC3B6ECF9E480c27A9492A975710Bb976ED008e7b
```
On scaner:
https://amoy.polygonscan.com/address/0xC3B6ECF9E480c27A9492A975710Bb976ED008e7b
