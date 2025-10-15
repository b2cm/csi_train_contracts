# csi_train_contracts

Smart contracts for the train delay protection. The smart contracts implement a complete insurance lifecycle using real-world train data via Chainlink oracles and the Generic Insurance Framework (GIF).

## Oracles

### What are Oracles?

Oracles are services that connect blockchains to external data sources, enabling smart contracts to access real-world information. In our system, oracles provide:

- **Route risk metrics** for pricing calculations
- **Real-time arrival information** for delay detection

### Chainlink Integration

This project uses [Chainlink](https://chain.link/) as the oracle solution for reliable external data access.

**Important Notice**: The Chainlink protocol is under active development. Newer versions may be available with enhanced features and security improvements. Always refer to the latest documentation:

- [Chainlink Documentation](https://docs.chain.link/)
- [Chainlink GitHub Repository](https://github.com/smartcontractkit/chainlink)

### Oracle Architecture

The system implements a **two-phase oracle strategy**:

1. **Ratings Oracle** (`TrainRatingsOracle`): Evaluates route risk and calculates potential payouts
2. **Status Oracle** (`TrainStatusOracle`): Monitors actual train arrivals and delays

## Generic Insurance Framework (GIF)

### What is GIF?

The [Generic Insurance Framework](https://etherisc-gif-manual.readthedocs.io/en/latest/index.html) is a decentralized protocol that provides standardized infrastructure for building insurance products on blockchain. GIF handles:

- **Policy Management**: Application, underwriting, and lifecycle management
- **Premium Collection**: Automated payment processing and treasury management
- **Claims Processing**: Standardized claim creation and payout mechanisms
- **Risk Pool Management**: Capital allocation and risk distribution

### Documentation and Resources

- [GIF Manual](https://etherisc-gif-manual.readthedocs.io/en/latest/index.html)
- [GIF Contracts Repository](https://github.com/etherisc/gif-contracts)

_Note: This repository only contains the smart contracts for the train delay protection product. For full documentation and deployment instructions, please refer to the [GIF Contracts Repository](https://github.com/etherisc/gif-contracts)._

## Repository Structure

```
├── contracts/
│   ├── TrainProduct.sol          # Main insurance logic and policy lifecycle
│   ├── TrainRiskpool.sol         # Risk pool management and investor capital
│   ├── TrainStatusOracle.sol     # Real-time train delay monitoring
│   ├── TrainRatingsOracle.sol    # Route risk assessment and pricing
│   ├── ChainlinkOracle.sol       # Abstract base for Chainlink integration
│   ├── EuroCoin.sol              # Mock EUR token for testing
└── README.md                     # This documentation
```

### Contract Descriptions

#### Core Insurance Contracts

- **`TrainProduct.sol`**: The main insurance contract implementing the complete policy lifecycle from application through payout. Handles risk assessment, underwriting, monitoring, and claims processing.

- **`TrainRiskpool.sol`**: Manages the insurance risk pool where investors provide capital to back policies. Implements role-based access control for investors and handles capital allocation.

#### Oracle Contracts

- **`TrainRatingsOracle.sol`**: Evaluates route risk profiles and calculates appropriate payout amounts based on historical data and risk factors.

- **`TrainStatusOracle.sol`**: Monitors real-time train arrivals and delays using Chainlink Keepers for automated scheduling. Provides delay data for claims processing.

- **`ChainlinkOracle.sol`**: Abstract base contract providing common Chainlink functionality for oracle implementations. Handles LINK token management and request configuration.

#### Supporting Contracts

- **`EuroCoin.sol`**: Mock EUR token for testing and development.


## Business Logic

### Policy Lifecycle

1. **Application**: Customer applies with journey details and selects coverage level
2. **Risk Assessment**: Ratings oracle evaluates route risk and calculates payout
3. **Underwriting**: Policy is approved and premium is collected
4. **Monitoring**: Status oracle monitors train arrival after scheduled time
5. **Claims Processing**: Automatic payout if delay exceeds 60 minutes
6. **Settlement**: Policy expires and is closed


### Payout Conditions

- **Minimum Delay**: 60 minutes or more
- **Monitoring Window**: 12 hours after scheduled arrival (pilot phase)
- **Excluded Routes**: Rail replacement services (RPS) & buses
- **Risk Threshold**: Routes with >40% delay probability excluded

## ⚠️ Important Notice

This repository contains smart contract code that may be deprecated due to updates in the Chainlink or Generic Insurance Framework (GIF) protocols. Always refer to the latest documentation and protocol specifications before using this code in production environments.
