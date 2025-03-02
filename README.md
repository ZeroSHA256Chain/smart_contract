# Decentralized Auction 

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
npx hardhat ignition deploy ./ignition/modules/Auction.js --network localhost
```

To deploying contract on testnet you need to provide `API_KEY` and `PRIVATE_KET` in `.env` or hardcode in `hardhat.config.js` and run:
```shell
npx hardhat ignition deploy ./ignition/modules/Auction.js --network polygon_amoy
```
