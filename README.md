# Ascenda

> Privacy-preserving cross-chain derivatives platform for real-world assets 

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![TypeScript](https://img.shields.io/badge/TypeScript-007ACC?logo=typescript&logoColor=white)](https://www.typescriptlang.org/)
[![Solidity](https://img.shields.io/badge/Solidity-363636?logo=solidity&logoColor=white)](https://soliditylang.org/)
[![Etherlink](https://img.shields.io/badge/Etherlink-Layer2-blue)](https://etherlink.com/)
[![1inch](https://img.shields.io/badge/1inch)](https://1inch.io/)

## Overview

Ascenda is a revolutionary derivatives trading platform that brings traditional finance UX to privacy-preserving DeFi. Users can trade derivatives on real-world assets (stocks, commodities, bonds) with complete privacy while enjoying familiar interfaces reminiscent of Interactive Brokers or E*TRADE.

### Core Value Proposition

- **Privacy-First**: All positions and trading activity encrypted using FHEVM
- **Cross-Chain Settlement**: Atomic swaps via 1inch Fusion+ protocol
- **Familiar UX**: Traditional brokerage interface abstracting DeFi complexity
- **Real-World Assets**: Trade derivatives on AAPL, TSLA, MTN, SPY, etc.
- **MEV Protection**: Built-in protection via Etherlink's decentralized sequencing

## Architecture Overview

```mermaid
graph TB
    subgraph "Frontend Layer"
        UI[React Trading Interface]
        Mobile[React Native App]
        API[GraphQL API Gateway]
    end
    
    subgraph "Protocol Layer"
        CF[Confidential Tokens<br/>OpenZeppelin + FHEVM]
        EL[Etherlink L2<br/>MEV Protection]
        LOP[1inch Limit Order Protocol<br/>Advanced Strategies]
        FP[1inch Fusion+<br/>Cross-Chain Settlement]
    end
    
    subgraph "Infrastructure Layer"
        Oracles[Price Oracles<br/>Chainlink + TradFi]
        IPFS[Metadata Storage]
        TheGraph[Indexing & Queries]
    end
    
    UI --> API
    Mobile --> API
    API --> CF
    API --> EL
    CF --> EL
    LOP --> EL
    FP --> EL
    EL --> Oracles
    API --> TheGraph
```

## Technical Stack

### Smart Contracts
- **Solidity ^0.8.24** - Smart contract development
- **OpenZeppelin Confidential Contracts** - Privacy-preserving token standard
- **FHEVM** - Fully homomorphic encryption virtual machine
- **Hardhat** - Development framework and testing
- **Foundry** - Advanced testing and gas optimization

### Layer 2 & Cross-Chain
- **Etherlink** - Primary execution layer with MEV protection
- **1inch Fusion+** - Cross-chain atomic swaps
- **1inch Limit Order Protocol** - Advanced order management
- **Chainlink CCIP** - Additional cross-chain messaging

### Frontend & APIs
- **React 18** - Main trading interface
- **TypeScript** - Type-safe development
- **React Native** - Mobile trading app
- **TradingView Charting Library** - Professional charts

## Development Setup

### Prerequisites

```bash
# Required versions
node >= 18.0.0
npm >= 8.0.0
git >= 2.0.0
hardhat >=1.0.0
```

### Installation

```bash
# Clone the repository
git clone https://github.com/dayo-adewuyi/ascenda.git
cd ascenda-platform

# Install dependencies
npm install

# Install smart contract dependencies
cd packages/contracts
npm install

# Install frontend dependencies  
cd ../frontend
npm install

# Install backend dependencies
cd ../backend
npm install
```

### Environment Configuration

```bash
# Copy environment files
cp .env.example .env.local

# Configure required variables
ETHERLINK_RPC_URL=https://node.mainnet.etherlink.com
PRIVATE_KEY=your_private_key_here
CHAINLINK_API_KEY=your_chainlink_key
FHEVM_GATEWAY_URL=https://gateway.zama.ai
FUSION_API_URL=https://api.1inch.dev/fusion
POSTGRES_URL=postgresql://user:pass@localhost:5432/ascenda
```

### Smart Contract Deployment

```bash
cd packages/contracts

# Compile contracts
npx hardhat compile



# Deploy to Etherlink testnet
npx hardhat ignition deploy ./ignition/modules/ascenda.js --network etherlink


# Deploy to Etherlink mainnet
forge script script/Deploy.s.sol \
  --rpc-url $ETHERLINK_MAINNET_RPC \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify
```

### Frontend Development

```bash
cd packages/frontend

# Start development server
npm run dev

# Build for production
npm run build

# Run tests
npm run test

```

### Backend Services

```bash
cd packages/backend

npm run dev
```



## Contributing

### Development Workflow

1. Fork the repository
2. Create feature branch: `git checkout -b feature/amazing-feature`
3. Make changes and add tests
4. Run test suite: `npm test`
5. Commit changes: `git commit -m 'Add amazing feature'`
6. Push to branch: `git push origin feature/amazing-feature`
7. Create pull request

### Code Style

- **Solidity**: Follow [Solidity Style Guide](https://docs.soliditylang.org/en/latest/style-guide.html)
- **TypeScript**: Use Prettier and ESLint configurations
- **Commits**: Follow [Conventional Commits](https://www.conventionalcommits.org/)


## Links

- **Website**: https://ascenda.vercel.app
- **Documentation**: https://docs.ascenda.vercel.app
- **Twitter**: [@AscendaFinance](https://twitter.com/AscendaFinance)
- **Discord**: https://discord.gg/ascenda
- **Telegram**: https://t.me/ascendafinance

---

.