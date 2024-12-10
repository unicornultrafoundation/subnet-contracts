import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@openzeppelin/hardhat-upgrades";
import "@nomicfoundation/hardhat-verify";

const privateKey = process.env.PRIVATE_KEY

const config: HardhatUserConfig = {
  networks: {
    hardhat: {
    },
    nebulas: {
      url: "https://rpc-nebulas-testnet.u2u.xyz",
      accounts: privateKey ? [privateKey] : []
    },
    u2u: {
      url: "https://rpc-mainnet.u2u.xyz",
      accounts: privateKey ? [privateKey] : []
    }
  },
  etherscan: {
    apiKey: {
      nebulas: "1",
      u2u: "1"
    },
    customChains: [
      {
        network: "nebulas",
        chainId: 2484,
        urls: {
          apiURL: "https://testnet.u2uscan.xyz/api",
          browserURL: "https://testnet.u2uscan.xyz",
        }
      },
      {
        network: "u2u",
        chainId: 39,
        urls: {
          apiURL: "https://u2uscan.xyz/api",
          browserURL: "https://u2uscan.xyz",
        }
      }
    ]
  },
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
      viaIR: true, // Enable intermediate representation
    },
  }
};

export default config;
