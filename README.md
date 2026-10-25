# 🎰 Foundry Smart Contract Lottery (`Raffle.sol`)

![Solidity](https://img.shields.io/badge/Solidity-0.8.19-363636?style=for-the-badge&logo=solidity)
![Foundry](https://img.shields.io/badge/Foundry-Forge%20%7C%20Anvil%20%7C%20Cast-FFDB1C?style=for-the-badge)
![Chainlink VRF](https://img.shields.io/badge/Chainlink-VRF%20v2.5-375BD2?style=for-the-badge&logo=chainlink)
![Chainlink Automation](https://img.shields.io/badge/Chainlink-Automation-375BD2?style=for-the-badge&logo=chainlink)
![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)

An automated smart contract lottery built with Foundry. Players buy entries with ETH, Chainlink Automation decides when a round ends, Chainlink VRF supplies a verifiable random number, and the winner is paid out automatically.

- **Developer and write-ups:** Yuvraj Singh
- **Course:** Built alongside Patrick Collins' Cyfrin Updraft *Foundry Fundamentals* course (Smart Contract Lottery section, `foundry-smart-contract-lottery-cu`). The contract follows the course design. The explanations, diagrams, test breakdowns and the Known Limitations section are my own notes, written while studying it.
- **Stack:** Solidity `0.8.19` | Foundry (`forge`, `anvil`, `cast`) | Chainlink VRF v2.5 (`VRFConsumerBaseV2Plus`) | Chainlink Automation (`AutomationCompatibleInterface`)

---

## 📑 Contents

1. [Overview](#-1-overview)
2. [Architecture](#-2-architecture)
3. [Quickstart](#-3-quickstart)
4. [Tests](#-4-tests)
5. [Gas and security choices](#-5-gas-and-security-choices)
6. [Known limitations](#-6-known-limitations)
7. [Study notes](#-7-study-notes)
   - [7.1 Why a blockchain needs oracles](#-71-why-a-blockchain-needs-oracles)
   - [7.2 Walkthrough of `Raffle.sol`](#-72-walkthrough-of-rafflesol)
   - [7.3 Chainlink VRF v2.5](#-73-chainlink-vrf-v25)
   - [7.4 Chainlink Automation](#-74-chainlink-automation)
   - [7.5 Picking a winner with modulo](#-75-picking-a-winner-with-modulo)
   - [7.6 Deployment scripts](#-76-deployment-scripts)
8. [License](#-8-license)

---

## 🎯 1. Overview

`Raffle.sol` runs lottery rounds with no human in the loop after deployment.

* **Enter:** Anyone can call `enterRaffle()` and send at least `i_entranceFee` in ETH.
* **Timer check:** Chainlink Automation nodes call `checkUpkeep()` to see whether the interval (`i_interval`) has passed, the raffle is open, and there is at least one player and a balance.
* **Lock and request randomness:** When the conditions are met, Automation calls `performUpkeep()`. It sets the state to `CALCULATING`, which blocks new entries, and requests a random number from Chainlink VRF v2.5.
* **Pick, pay, reset:** The VRF coordinator verifies the random number's proof on-chain and calls back into `fulfillRandomWords()`. The contract uses modulo (`%`) to choose a winner from `s_players`, resets the round, sets the state back to `OPEN`, and sends the whole ETH balance to the winner.

---

## 🧱 2. Architecture

### 📐 Execution flow

```text
+-------------------------------------------------------------------------------+
| 1. PLAYERS ENTER THE LOTTERY (RaffleState.OPEN)                               |
|                                                                               |
| User Wallet / Website  --->  enterRaffle() [external payable]                 |
| |-- Check 1: if (msg.value < i_entranceFee) -> Revert!                        |
| |-- Check 2: if (s_raffleState != OPEN)     -> Revert!                        |
| |-- Storage: s_players.push(payable(msg.sender))                              |
| +-- Event:   emit RaffleEnter(msg.sender) [indexed for Frontend logs]         |
+-------------------------------------------------------------------------------+
                                       |
                                       v
+-------------------------------------------------------------------------------+
| 2. CHAINLINK AUTOMATION NODES CHECK CONDITIONS (Off-Chain View Call)          |
|                                                                               |
| Automation node  --->  checkUpkeep("") [public view]                          |
| |-- timePassed = (block.timestamp - s_lastTimeStamp) >= i_interval            |
| |-- isOpen     = (s_raffleState == RaffleState.OPEN)                          |
| |-- hasBalance = (address(this).balance > 0)                                  |
| |-- hasPlayers = (s_players.length > 0)                                       |
| +-- Returns: upkeepNeeded = (timePassed && isOpen && hasBalance && ...)       |
+-------------------------------------------------------------------------------+
                                       |
                        [When upkeepNeeded == true (1)]
                                       |
                                       v
+-------------------------------------------------------------------------------+
| 3. LOCK LOTTERY & REQUEST RANDOM NUMBER (RaffleState.CALCULATING)             |
|                                                                               |
| Automation node  --->  performUpkeep("") [external]                           |
| |-- Re-check: calls checkUpkeep(""); reverts if false (0)                     |
| |-- State lock: s_raffleState = RaffleState.CALCULATING                       |
| |-- Build request: VRFV2PlusClient.RandomWordsRequest memory request          |
| +-- Send request: s_vrfCoordinator.requestRandomWords(request) -> requestId   |
+-------------------------------------------------------------------------------+
                                       |
                [Wait 3 Block Confirmations + Verify VRF Proof]
                                       |
                                       v
+-------------------------------------------------------------------------------+
| 4. CALLBACK & WINNER PAYOUT (Resets Back to RaffleState.OPEN)                 |
|                                                                               |
| VRFCoordinatorV2_5     --->  rawFulfillRandomWords(requestId, randomWords)    |
| |-- Caller check (in VRFConsumerBaseV2Plus): msg.sender == Coordinator        |
| +-- Calls our override: fulfillRandomWords(requestId, randomWords)            |
| |-- Modulo: indexOfWinner = randomWords[0] % s_players.length                 |
| |-- Winner: recentWinner = s_players[indexOfWinner]                           |
| |-- Reset:  s_players = new address payable[](0)                              |
| |           s_raffleState = RaffleState.OPEN                                  |
| |           s_lastTimeStamp = block.timestamp                                 |
| |-- Event:  emit WinnerPicked(recentWinner)                                   |
| +-- Payout: (bool success,) = recentWinner.call{value: bal}("")               |
+-------------------------------------------------------------------------------+
```

### 🧩 Inherited and imported contracts

| Contract / library | Role |
| :--- | :--- |
| **`VRFConsumerBaseV2Plus`** | Inherited by `Raffle`. Provides `s_vrfCoordinator`, the `rawFulfillRandomWords` entry point that checks the caller is the coordinator, and the virtual `fulfillRandomWords` function that `Raffle` overrides. |
| **`IVRFCoordinatorV2Plus`** | The interface type of `s_vrfCoordinator`, the on-chain contract that receives `requestRandomWords`. |
| **`VRFV2PlusClient`** | Library holding the `RandomWordsRequest` struct and `ExtraArgsV1`, which selects how the request is paid for. |
| **`AutomationCompatibleInterface`** | Interface that guarantees the `checkUpkeep` and `performUpkeep` signatures Automation nodes look for. |

### 🚦 State machine (`enum RaffleState { OPEN, CALCULATING }`)

The enum prevents entries while a winner is being chosen.

| `s_raffleState` | `enterRaffle()` | `checkUpkeep()` | `performUpkeep()` | `fulfillRandomWords()` |
| :--- | :--- | :--- | :--- | :--- |
| 🟢 **`OPEN` (`0`)** | ✅ Accepts entries if `msg.value >= i_entranceFee` | ✅ Returns `true` once the interval and player checks pass | ✅ Locks state to `CALCULATING` and requests a random number | Waiting for a request |
| 🟡 **`CALCULATING` (`1`)** | ❌ Reverts with `Raffle__RaffleNotOpen()` | ❌ Always `false`, because `isOpen` is false | ❌ Reverts with `Raffle__UpkeepNotNeeded(...)` | ✅ Picks winner, pays out, resets to `OPEN` |

---

## 🚀 3. Quickstart

### 📂 Project structure

```text
Foundry-Smart-Contract-Lottery/
├── src/
│   └── Raffle.sol                 # Main lottery contract (VRF v2.5 + Automation)
├── script/
│   ├── DeployRaffle.s.sol         # Deployment script, returns (Raffle, HelperConfig)
│   ├── HelperConfig.s.sol         # Chain ID mapping (Sepolia) and Anvil mock deployer
│   └── Interactions.s.sol         # CreateSubscription, FundSubscription, AddConsumer
├── test/
│   ├── unit/RaffleTest.t.sol      # Unit, fuzz, event-log and full lifecycle tests
│   └── mocks/LinkToken.sol        # Local LINK token mock for Anvil funding
├── Makefile                       # Shortcuts for build, test, anvil and Sepolia deploy
└── foundry.toml                   # Foundry configuration and remappings
```

### 🔨 Install and build

```bash
git clone https://github.com/Yuvi8990/Foundry-Smart-Contract-Lottery.git
cd Foundry-Smart-Contract-Lottery
make install
forge build
```

### 🧪 Run the tests

```bash
# Unit and fuzz tests, locally
forge test

# The full end-to-end lottery test with detailed traces
forge test --mt testFulfillRandomWordsPicksAWinnerResetsAndSendsMoney -vvvv

# Tests against a forked Sepolia
forge test --rpc-url $SEPOLIA_RPC_URL

# Gas snapshot and coverage
forge snapshot
forge coverage
```

### 🌐 Deploy

```bash
# Terminal 1: start a local Anvil node
make anvil

# Terminal 2: deploy locally (deploys mocks, creates and funds a subscription, adds the consumer)
make deploy

# Deploy to Sepolia (needs SEPOLIA_RPC_URL and PRIVATE_KEY in .env)
make deploy ARGS="--network sepolia"
```

### 🎟️ Enter the raffle on Sepolia

```bash
cast send <RAFFLE_CONTRACT_ADDRESS> "enterRaffle()" --value 0.01ether --private-key $PRIVATE_KEY --rpc-url $SEPOLIA_RPC_URL
```

---

## 🧪 4. Tests

All 11 tests live in `test/unit/RaffleTest.t.sol`.

| Test | Cheatcodes used | What it verifies | Gas |
| :--- | :--- | :--- | :--- |
| `testRaffleInitializesInOpenState` | None (`view`) | `raffle.getRaffleState() == Raffle.RaffleState.OPEN` right after deployment. | `7,753` |
| `testRaffleRevertsWhenYouDontPayEnough` | `vm.prank`, `vm.expectRevert` | `enterRaffle()` with `0` ETH reverts with `Raffle__SendMoreToEnterRaffle`. | `11,200` |
| `testPerformUpkeepRevertsIfCheckUpkeepIsFalse` | `vm.prank`, `vm.expectRevert` | Calling `performUpkeep("")` too early reverts with `Raffle__UpkeepNotNeeded(balance, numPlayers, rState)`. | `17,399` |
| `testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep` | Fuzz (`uint256 randomRequestId`), `skipFork` | 256 fuzz runs (Foundry's default) pass random fake request IDs to `VRFCoordinatorV2_5Mock` and confirm it reverts. | `18,500` |
| `testCheckUpkeepReturnsFalseIfItHasNoBalance` | `vm.warp`, `vm.roll` | After the interval passes with no balance and no players, `checkUpkeep("")` returns `false`. | `19,096` |
| `testRaffleRecordsPlayersWhenTheyEnter` | `vm.prank` | After `PLAYER` enters with the entrance fee, `raffle.getPlayer(0) == PLAYER`. | `67,500` |
| `testEnteringRaffleEmitsEvent` | `vm.prank`, `vm.expectEmit` | `RaffleEnter(PLAYER)` is emitted when `PLAYER` enters. | `68,752` |
| `testPerformUpkeepCanOnlyRunIfCheckUpkeepIsTrue` | `vm.prank`, `vm.warp`, `vm.roll` | With a player entered and time and block number advanced, `performUpkeep("")` succeeds. | `126,958` |
| `testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId` | `vm.recordLogs`, `vm.getRecordedLogs` | Records logs during `performUpkeep("")`, reads `requestId` from `entries[1].topics[1]`, and checks the state is `CALCULATING`. | `144,057` |
| `testDontAllowPlayersToEnterWhileRaffleIsCalculating` | `vm.prank`, `vm.warp`, `vm.roll`, `vm.expectRevert` | After `performUpkeep("")`, new entries revert with `Raffle__RaffleNotOpen`. | `161,916` |
| `testFulfillRandomWordsPicksAWinnerResetsAndSendsMoney` | `hoax`, `vm.recordLogs`, `skipFork` | End to end: 4 players enter, `performUpkeep("")` runs, the mock fulfills the request, the winner receives the full pot, and the raffle resets to `OPEN`. | `310,543` |

### 📊 Gas used per test

This chart shows how much gas each test consumes when it runs. It reflects how much each test does, not how efficient the contract is. Contract gas costs come from `forge snapshot`.

```text
Test                                                      Gas Used   Bar
--------------------------------------------------------  ---------  ----------------------------------------
testRaffleInitializesInOpenState                              7,753  █
testRaffleRevertsWhenYouDontPayEnough                        11,200  ██
testPerformUpkeepRevertsIfCheckUpkeepIsFalse                 17,399  ███
testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep      18,500  ███
testCheckUpkeepReturnsFalseIfItHasNoBalance                  19,096  ███
testRaffleRecordsPlayersWhenTheyEnter                        67,500  █████████
testEnteringRaffleEmitsEvent                                 68,752  █████████
testPerformUpkeepCanOnlyRunIfCheckUpkeepIsTrue              126,958  ████████████████
testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId        144,057  ███████████████████
testDontAllowPlayersToEnterWhileRaffleIsCalculating         161,916  █████████████████████
testFulfillRandomWordsPicksAWinnerResetsAndSendsMoney       310,543  ████████████████████████████████████████
```

### 🛠️ Cheatcodes used

* **`vm.warp(block.timestamp + interval + 1)` and `vm.roll(block.number + 1)`:** Move time and the block number forward on the local chain so `timePassed` in `checkUpkeep` becomes `true`.
* **`vm.prank(PLAYER)` and `hoax(player, STARTING_BALANCE)`:** `vm.prank` sets `msg.sender` to `PLAYER` for the next call. `hoax` funds an address with ETH (`vm.deal`) and pranks it in one step.
* **`vm.recordLogs()` and `entries[1].topics[1]`:** Capture every event emitted during `performUpkeep("")`. `VRFCoordinatorV2_5Mock` emits its own event first (`entries[0]`), so our `RequestedRaffleWinner(requestId)` is `entries[1]`, and its indexed `requestId` is in `topics[1]`.
* **`skipFork` modifier:** Skips tests that call `VRFCoordinatorV2_5Mock.fulfillRandomWords` when running on a forked Sepolia (`chainId != 31337`), because on a live network only real Chainlink nodes can fulfill VRF requests.

---

## ⚡ 5. Gas and security choices

| Feature in `Raffle.sol` | Why it is used |
| :--- | :--- |
| **Custom errors** (`revert Raffle__...`) | A custom error reverts with a 4-byte selector (plus any arguments) instead of an ABI-encoded error string, which costs less gas to deploy and to revert. |
| **`immutable` and `constant` variables** | `i_entranceFee`, `i_interval`, `i_gasLane`, `i_subscriptionId` and `i_callbackGasLimit` are set once in the constructor, and `REQUEST_CONFIRMATIONS` and `NUM_WORDS` are constants. Both kinds are stored in the contract bytecode instead of in storage slots, so reading them is cheaper. |
| **`calldata` on `randomWords`** | `uint256[] calldata randomWords` is read directly from the call input without copying the array into memory. |
| **`private` state variables with getters** | `s_players`, `s_recentWinner`, `s_raffleState` and `s_lastTimeStamp` are `private`, with `view` getters (`getEntranceFee()`, `getPlayer()`, `getRecentWinner()`, `getRaffleState()`) for what outside code needs. This keeps the contract's interface small. It does not hide the data: everything in storage is readable on-chain, and `private` is not access control. |
| **State changes before the payout** | `performUpkeep` sets `CALCULATING` before requesting randomness, and `fulfillRandomWords` resets `s_players`, the state and the timestamp before sending ETH with `.call`. This follows the checks-effects-interactions pattern, which reduces reentrancy risk. The payout is also only reachable through the coordinator's callback. |

---

## 🚨 6. Known limitations

This contract follows the course design, and I studied it for weaknesses after building it. These are the ones I found. None of them are covered by the current test suite, and I have not changed the contract to fix them.

**1. A failed payout can lock the raffle permanently.**
If the winner is a contract that rejects ETH, `.call` returns `false` and `fulfillRandomWords` reverts with `Raffle__TransferFailed()`. The revert also undoes the state reset, so the raffle stays in `CALCULATING`. `checkUpkeep` then returns `false` for good, and the prize is stuck. A contract with a reverting `receive` function could cause this on purpose by entering and winning.
*Possible fix:* a pull-payment pattern. `fulfillRandomWords` records the prize for the winner, and the winner withdraws it in a separate call. A failed withdrawal would then affect only that winner, not the next round.

**2. No recovery if the VRF request is never fulfilled.**
If the subscription runs out of funds or the callback fails for another reason, the raffle stays in `CALCULATING` and nothing resets it.
*Possible fix:* a timeout after which anyone can reset the round, or an owner-controlled recovery path with refunds to players.

**3. Resetting `s_players` costs gas that grows with the number of players.**
`s_players = new address payable[](0)` clears each stored element, so the gas used in `fulfillRandomWords` rises with the player count. The callback has a limit of 500,000 gas (`i_callbackGasLimit`). If a round gets large enough to exceed it, the callback fails and the raffle gets stuck as in limitation 2. I have not measured the player count at which this happens, and I would test that before relying on it.
*Possible fix:* track rounds with a counter instead of clearing the array, or cap players per round.

**4. Overpayment is not refunded.**
The check is `msg.value < i_entranceFee`, so sending more than the fee still gives one entry, and the extra ETH goes into the prize pool. This is a design choice, but a user could lose money by mistake.
*Possible fix:* require an exact payment, or refund the difference.

**5. The raffle depends on Chainlink services staying available.**
Both VRF and Automation must keep working for rounds to complete. If Automation stops calling `performUpkeep`, entered funds sit in the contract until it resumes.

---

## 📚 7. Study notes

These sections explain the reasoning behind the contract. They are my notes from working through it line by line.

### 🧠 7.1 Why a blockchain needs oracles

**The consensus problem.** Every node that validates a block re-executes its transactions and has to reach the same result. This is why the EVM has no true source of randomness: anything a contract can read, such as block fields or its own storage, is either predictable or chosen by someone. If each node generated its own random number inside Solidity, they would get different winners and could not agree on the block.

**How VRF solves it.** Chainlink VRF generates the random number off-chain together with a cryptographic proof. The coordinator contract verifies that proof on-chain before calling back into `Raffle`, so a changed number is rejected. The verified number is part of the transaction, so every node sees the same value.

**Why not `block.timestamp`.** The block proposer sets the timestamp within the limits the protocol allows, and proposers can see pending transactions. Anything that uses a timestamp or similar block data as a randomness source can therefore be nudged by whoever produces the block, especially when the prize is big enough to be worth it. VRF removes that option.

### 🔍 7.2 Walkthrough of `Raffle.sol`

#### 🎟️ `enterRaffle()`: entrance fee, overpayment and the `s_players` array

* **Immutable entrance fee (`i_entranceFee`):** It is set once in the constructor, so the fee can be chosen at deployment, and reading it is cheap afterwards.
* **Custom error check:** If `msg.value < i_entranceFee`, the function reverts with `Raffle__SendMoreToEnterRaffle()`, which is cheaper than a `require` with a text string. `require` with custom errors arrived in Solidity `0.8.26` (via-IR) and `0.8.27` (default pipeline), while `if` plus `revert` works across `0.8.19` and later.
* **Paying more than the fee:** The check only rejects too little. A caller who sends extra still gets one entry in `s_players`, and the extra ETH stays in the contract and adds to the prize pool.
* **Payable player array (`address payable[] private s_players`):** Players are stored as `payable` addresses so the winner can be paid directly.

#### 📢 Why `RaffleEnter(address indexed player)` is emitted after the storage update

Emitting an event whenever storage changes is standard practice. Here it also has a practical use. Events are written to transaction logs, which a frontend or indexer can query and filter without reading contract storage. Marking `player` as `indexed` makes it a topic, so a website can filter the logs for one wallet and show an "entered" confirmation.

#### 🔄 `constructor` and `fulfillRandomWords`

* **`VRFConsumerBaseV2Plus(vrfCoordinator)` in the constructor header:** It passes the coordinator address to the parent contract, so the inherited code knows which contract to call and accept callbacks from.
* **`fulfillRandomWords` resets the round:** The constructor opens the raffle (`s_raffleState = RaffleState.OPEN`) and starts the clock (`s_lastTimeStamp = block.timestamp`). `fulfillRandomWords` does the same at the end of every round, and also clears `s_players`.

#### 💸 Sending the prize with `.call`

```solidity
(bool success,) = recentWinner.call{value: address(this).balance}("");
if (!success) {
    revert Raffle__TransferFailed();
}
```

* `{value: address(this).balance}` sends the contract's entire balance to `recentWinner`.
* `("")` sends empty calldata, because the goal is only to transfer ETH, not to call a function on the winner's address.
* `(bool success,)` unpacks the two values a `.call` returns: whether it succeeded, and the returned bytes. The empty slot after the comma discards the bytes.
* `if (!success)` reverts with `Raffle__TransferFailed()` when the transfer fails. See [Known limitations](#-6-known-limitations), item 1, for what that means for the raffle.

### 🎲 7.3 Chainlink VRF v2.5

#### 📋 The request struct (`VRFV2PlusClient.RandomWordsRequest`)

Inside `performUpkeep`, the contract fills a `RandomWordsRequest` struct with named fields. It works like an order form that tells VRF exactly what to deliver:

| Field | Value passed in | Meaning |
| :--- | :--- | :--- |
| **`keyHash`** | `i_gasLane` (`bytes32`) | Identifies the gas lane, which sets the maximum gas price (in gwei) the request is willing to pay. |
| **`subId`** | `i_subscriptionId` (`uint256`) | The subscription that pays for the request. A subscription is a funded account that many consumer contracts can draw from. In v2.5 the ID is a `uint256`. |
| **`requestConfirmations`** | `REQUEST_CONFIRMATIONS` (`3`) | How many blocks Chainlink waits before responding. More confirmations are safer, because an attacker would have to reorganize a deeper chain to change the outcome, but they add delay. |
| **`callbackGasLimit`** | `i_callbackGasLimit` (`500,000`) | The most gas VRF may spend calling `fulfillRandomWords`. If the callback needs more, it fails (see [Known limitations](#-6-known-limitations), item 3). |
| **`numWords`** | `NUM_WORDS` (`1`) | How many random `uint256` values to return. "Word" is the EVM's name for a 256-bit value. |
| **`extraArgs`** | `_argsToBytes(ExtraArgsV1({nativePayment: false}))` | Payment mode. `false` pays in LINK, `true` pays in native ETH. |

#### 🛡️ How the caller check works

When Chainlink finishes, it calls `rawFulfillRandomWords` in `VRFConsumerBaseV2Plus`. That function first checks that the caller is `s_vrfCoordinator`, and only then calls our `fulfillRandomWords`. Because every consumer needs different logic, `fulfillRandomWords` is a `virtual` function in the base contract, and `Raffle` overrides it with the winner-picking code.

`uint256[] calldata randomWords` is read directly from the call input without being copied into memory, which saves gas.

### 🤖 7.4 Chainlink Automation

Automation nodes look for two functions from `AutomationCompatibleInterface`.

#### 🔎 `checkUpkeep(bytes memory /* checkData */)`

* **Purpose:** A `view` function that nodes simulate on every block to see whether a winner should be picked.
* **Why the parameter name is commented out:** A function's selector depends only on its name and parameter types, so the `bytes` parameter has to be in the signature for Automation to find it. This contract doesn't use the value, so the name is commented out to avoid an unused-variable warning.
* **Why `public` and not `external`:** `performUpkeep` also calls `checkUpkeep("")` internally, which `external` would not allow.
* **The conditions:** Four booleans (`timePassed`, `isOpen`, `hasBalance`, `hasPlayers`) are combined with `&&`:

```solidity
upkeepNeeded = (timePassed && isOpen && hasBalance && hasPlayers);
return (upkeepNeeded, "0x0");
```

  `upkeepNeeded` is `true` only if all four are true. The second return value is a placeholder. `"0x0"` is the three ASCII characters `0`, `x`, `0` converted to bytes, not an empty value, and Automation ignores it here.

#### ⚡ `performUpkeep(bytes calldata /* performData */)`

* **Purpose:** When `checkUpkeep` returns `true`, an Automation node sends a real transaction calling `performUpkeep("")`.
* **On-chain re-check:** The function calls `(bool upkeepNeeded,) = checkUpkeep("");` and reverts with `Raffle__UpkeepNotNeeded(address(this).balance, s_players.length, uint256(s_raffleState))` if it is `false`. This matters because anyone can call `performUpkeep` directly, not only Automation nodes. If the check passes, the function sets `CALCULATING` and requests the random number.

### ➗ 7.5 Picking a winner with modulo

`fulfillRandomWords` receives the random number as `randomWords[0]` and picks the winner with the modulo operator:

```solidity
uint256 indexOfWinner = randomWords[0] % s_players.length;
address payable recentWinner = s_players[indexOfWinner];
```

**Why the index is always valid**

1. **Remainder rule:** If `s_players.length` is $x$, then `randomWords[0] % x` is at least $0$ and at most $x - 1$.
2. **Array index rule:** Array indices start at $0$, so the highest valid index in `s_players` is also $x - 1$.
3. **Result:** The remainder always lands on an existing index, so the lookup cannot go out of bounds.

**Fairness.** Because `randomWords[0]` is a verified random 256-bit number, each index is chosen with essentially equal probability. Modulo can introduce a slight bias when the range doesn't divide evenly into $2^{256}$, but with a player count far smaller than $2^{256}$ that bias is negligible.

### 🔧 7.6 Deployment scripts

#### 🌐 Local Anvil and live testnets

On a live testnet such as Sepolia, the VRF coordinator, the LINK token and the Automation network already exist. On local Anvil (`chainId == 31337`) none of them do, so the scripts deploy mock contracts (`VRFCoordinatorV2_5Mock` and `LinkToken`) and the tests call those mocks directly to simulate Chainlink.

#### ⚙️ `script/HelperConfig.s.sol`

`HelperConfig` inherits `Script` and an abstract `CodeConstants` contract (chain IDs and mock constants), and returns the right `NetworkConfig` for whichever chain it runs on.

* **Sepolia:** `getSepoliaEthConfig()` is a `pure` function because Sepolia already has a live VRF coordinator (`0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B`), a gas lane and a LINK address. The constructor stores it with `networkConfigs[ETH_SEPOLIA_CHAIN_ID] = getSepoliaEthConfig();`. When `getConfigByChainId` runs on Sepolia, it finds a non-zero `vrfCoordinatorV2_5` address and returns that config immediately.
* **Anvil:** The constructor leaves `31337` out of the mapping, so its coordinator address defaults to `0` and the first check fails. The `else if (chainId == LOCAL_CHAIN_ID)` branch then calls `getOrCreateAnvilEthConfig()`. It deploys `new VRFCoordinatorV2_5Mock(...)` and `new LinkToken()` between `vm.startBroadcast()` and `vm.stopBroadcast()`, stores the result in `localNetworkConfig` so repeated calls don't deploy duplicate mocks, and returns it.
* **Anything else:** For an unsupported chain ID both checks fail and the call reverts with `HelperConfig__InvalidChainId()`.

#### 🚀 `script/DeployRaffle.s.sol`

`deployContract()` creates a `new HelperConfig()`, calls `helperConfig.getConfig()` for the current chain, deploys `Raffle` between `vm.startBroadcast()` and `vm.stopBroadcast()` using that config, and returns `(raffle, helperConfig)`. The test file runs this same script in `setUp()` and reads the network values from the returned `HelperConfig`.

#### 🔗 `script/Interactions.s.sol`

If `config.subscriptionId == 0`, `DeployRaffle` uses three script contracts to set up the VRF subscription:

1. **`CreateSubscription`:** Calls `createSubscription()` on the VRF coordinator to get a new `subId`.
2. **`FundSubscription`:** Funds the subscription with `3 ether` (3 LINK). On Anvil it calls `VRFCoordinatorV2_5Mock.fundSubscription(subId, FUND_AMOUNT)`. On Sepolia it calls `LinkToken(link).transferAndCall(vrfCoordinatorV2_5, FUND_AMOUNT, abi.encode(subId))`.
3. **`AddConsumer`:** Gets the most recent `Raffle` deployment with `DevOpsTools.get_most_recent_deployment("Raffle", block.chainid)` and calls `addConsumer(subId, raffleAddress)`, so the coordinator accepts requests from this contract.

---

## 📜 8. License

Distributed under the **MIT License**.
