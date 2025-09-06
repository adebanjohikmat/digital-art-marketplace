# Digital Art Marketplace

A comprehensive smart contract system for digital art NFT marketplace built with Clarity on the Stacks blockchain.

## 🎨 Overview

This project implements a complete digital art marketplace ecosystem consisting of three interconnected smart contracts that enable artists to mint NFTs, list them for sale, and manage royalty distribution automatically.

## 📋 Smart Contracts

### 1. NFT Minting Contract (`nft-minting.clar`)
- **Purpose**: Handles the creation and management of digital art NFTs
- **Features**:
  - Mint unique digital art tokens with metadata
  - Store artwork metadata (title, URL, creator, royalty percentage)
  - Implement supply caps and minting restrictions
  - Owner-based access control for special operations

### 2. Marketplace Contract (`marketplace.clar`)
- **Purpose**: Facilitates buying and selling of NFTs
- **Features**:
  - List NFTs for sale with custom pricing
  - Execute secure peer-to-peer transactions
  - Handle escrow and ownership transfers
  - Cancel active listings
  - Built-in marketplace fee structure

### 3. Royalty Splitter Contract (`royalty-splitter.clar`)
- **Purpose**: Manages royalty distribution among stakeholders
- **Features**:
  - Configure royalty splits for each NFT
  - Automatic STX distribution to artists and stakeholders
  - Update royalty structures
  - Track and verify payment distributions

## 🏗️ Architecture

The contracts work together to provide a seamless marketplace experience:

1. **Artists** use the NFT Minting contract to create digital art tokens
2. **Sellers** list their NFTs on the Marketplace contract
3. **Buyers** purchase NFTs through secure marketplace transactions
4. **Royalties** are automatically distributed via the Royalty Splitter contract

## 🚀 Getting Started

### Prerequisites

- [Clarinet](https://docs.hiro.so/clarinet) - Stacks smart contract development tool
- [Node.js](https://nodejs.org/) - For running tests and scripts
- [Git](https://git-scm.com/) - Version control

### Installation

1. Clone this repository:
```bash
git clone https://github.com/adebanjohikmat/digital-art-marketplace.git
cd digital-art-marketplace
```

2. Install dependencies:
```bash
npm install
```

3. Verify contract syntax:
```bash
clarinet check
```

4. Run tests:
```bash
clarinet test
```

## 📖 Contract APIs

### NFT Minting Contract

- `mint(recipient, metadata-url, title, royalty-bps)` - Mint new NFT
- `set-base-uri(new-uri)` - Update base metadata URI
- `get-token-metadata(token-id)` - Retrieve token metadata
- `get-total-supply()` - Get current supply count

### Marketplace Contract

- `list-nft(token-id, price)` - List NFT for sale
- `buy-nft(token-id)` - Purchase listed NFT
- `cancel-listing(token-id)` - Remove NFT from sale
- `get-listing(token-id)` - View listing details

### Royalty Splitter Contract

- `register-split(nft-id, artist, stakeholders, percentages)` - Set up royalty distribution
- `payout(nft-id, total-amount)` - Distribute royalties
- `update-split(nft-id, new-split)` - Modify existing split
- `get-split-info(nft-id)` - View current split configuration

## 🧪 Testing

The project includes comprehensive unit tests for all contract functions:

```bash
# Run all tests
clarinet test

# Check syntax only
clarinet check

# Run specific test file
clarinet test tests/nft-minting_test.ts
```

## 🔧 Development

### Adding New Features

1. Create feature branch from `development`:
```bash
git checkout development
git pull origin development
git checkout -b feature/your-feature-name
```

2. Make changes and test:
```bash
clarinet check
clarinet test
```

3. Commit and push:
```bash
git add .
git commit -m "feat: add your feature description"
git push origin feature/your-feature-name
```

4. Create pull request to `development` branch

### Contract Deployment

1. Configure network settings in `settings/` directory
2. Deploy contracts in order:
   - NFT Minting contract first
   - Marketplace contract second  
   - Royalty Splitter contract last

## 🛡️ Security Considerations

- All contracts implement proper access controls
- Input validation on all public functions
- Safe arithmetic operations to prevent overflow
- Secure fund handling with escrow mechanisms
- No cross-contract dependencies to minimize attack surface

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'feat: add AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 📞 Contact

- **Project Lead**: adebanjohikmat
- **GitHub**: [https://github.com/adebanjohikmat](https://github.com/adebanjohikmat)
- **Issues**: [https://github.com/adebanjohikmat/digital-art-marketplace/issues](https://github.com/adebanjohikmat/digital-art-marketplace/issues)

## 🙏 Acknowledgments

- Built with [Clarinet](https://docs.hiro.so/clarinet) by Hiro
- Powered by [Stacks](https://stacks.co) blockchain
- Inspired by the NFT and DeFi communities

---

*This project demonstrates a production-ready smart contract system for digital art marketplaces with comprehensive testing, documentation, and security best practices.*
