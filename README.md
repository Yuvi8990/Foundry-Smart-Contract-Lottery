# 🎰 Foundry Smart Contract Lottery (`Raffle.sol`) 🎲✨

![Solidity](https://img.shields.io/badge/Solidity-0.8.19-363636?style=for-the-badge&logo=solidity)
![Foundry](https://img.shields.io/badge/Foundry-Forge%20%7C%20Anvil%20%7C%20Cast-FFDB1C?style=for-the-badge)
![Chainlink VRF](https://img.shields.io/badge/Chainlink-VRF%20v2.5-375BD2?style=for-the-badge&logo=chainlink)
![Chainlink Automation](https://img.shields.io/badge/Chainlink-Automation-375BD2?style=for-the-badge&logo=chainlink)
![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)

👨‍💻 **Developer & Technical Explanations:** **Yuvraj Singh**
🎓 **Course & Tutorial Guidance:** Built alongside **Patrick Collins' Cyfrin Updraft — Foundry Fundamentals (Smart Contract Lottery)** curriculum (`foundry-smart-contract-lottery-cu`), with my own original line-by-line architectural & math breakdowns documented below.
🔗 **Core Stack:** Solidity `0.8.19` • Foundry (`Forge`, `Anvil`, `Cast`) • Chainlink VRF v2.5 (`VRFConsumerBaseV2Plus`) • Chainlink Automation (`AutomationCompatibleInterface`)

---

## 📑 Table of Contents

| #️⃣ | Section | What Is Covered Inside |
| :--- | :--- | :--- |
| **1️⃣** | **🎯 Project Overview** | What `Raffle.sol` does from ticket purchase to automatic prize payout |
| **2️⃣** | **🧠 Why Blockchain Needs Oracles** | Node consensus, why Solidity can't make random numbers, and `block.timestamp` manipulation |
| **3️⃣** | **🏗️ System Architecture & Visual Flowcharts** | Boxed ASCII execution flow, and `RaffleState` state machine |
| **4️⃣** | **🔍 Deep Dive: `src/Raffle.sol`** | Entrance fee checks, payable `s_players` array, indexed events for websites, and `.call` payouts |
| **5️⃣** | **🎲 Deep Dive: Chainlink VRF v2.5** | The VRF "Order Form" (`RandomWordsRequest`), gas lanes vs. gas limits, and the `rawFulfillRandomWords` bouncer |
| **6️⃣** | **🤖 Deep Dive: Chainlink Automation** | How off-chain Keeper bots run `checkUpkeep` and trigger `performUpkeep` |
| **7️⃣** | **➗ The Math Behind Picking a Winner** | How the modulo (`%`) remainder operator maps a huge random number onto `s_players` |
| **8️⃣** | **🛠️ Scripts & Multi-Chain Setup** | `HelperConfig.s.sol` (Sepolia vs. Anvil mocks), `DeployRaffle.s.sol`, and `Interactions.s.sol` |
| **9️⃣** | **⚡ Gas Optimizations & Security Choices** | Custom errors, `immutable`/`constant` variables, `calldata`, `private` getters, and state locking |
| **🔟** | **🧪 Testing Showcase & Gas Profile** | Full test table, ASCII gas bar chart, `vm.warp`/`vm.roll`, `vm.recordLogs`, and `skipFork` |
| **1️⃣1️⃣** | **🚀 Quickstart & Deployment Commands** | How to clone, build, test, and deploy locally on Anvil or live on Sepolia |

---

## 🎯 1. Project Overview

`Raffle.sol` is an automated, provably fair smart contract lottery built with Foundry 🛠️.
* 💰 **Enter the Lottery:** Any user can enter by calling `enterRaffle()` and paying at least the minimum `i_entranceFee` in ETH.
* ⏱️ **Automatic Timer Check:** Off-chain **Chainlink Automation** bots watch the contract on every block to check if the time interval (`i_interval`) has passed, the raffle is open, and players have entered.
* 🔒 **Lock & Request Randomness:** Once the timer is up, Chainlink Automation triggers `performUpkeep()`, which switches the raffle state to `CALCULATING` (blocking new entries) and sends an order for a random number to **Chainlink VRF v2.5**.
* 🏆 **Pick Winner, Pay Prize & Reset:** Chainlink VRF generates a random number + a mathematical proof off-chain, verifies the proof on-chain, and sends the random number back to `fulfillRandomWords()`. The contract uses modulo math (`%`) to pick a random index from `s_players`, resets the lottery back to `OPEN`, and sends the entire ETH balance to the winner! 🎉

---

## 🧠 2. Why Blockchain Needs Oracles for Randomness & Automation

### 🤝 The Consensus Problem (Why Solidity Cannot Generate Random Numbers Alone)
A blockchain is made up of many independent computers (nodes) that provide computational power to verify transactions 🖥️. When nodes calculate something like an account balance, every node runs the exact same hardcoded math on the same input data, gets the exact same result, and reaches **consensus** ✅.

If we tried to build a random number generator inside Solidity itself, different nodes verifying the block would get *different* random numbers and pick *different* winners ❌. Because the validator nodes would disagree on the result, consensus could not be reached and the transaction would fail.

**How Chainlink VRF Solves This 🔗:** Chainlink acts as an external decentralized oracle network (an outside agency). It generates the random number off-chain along with a cryptographic mathematical proof and returns it to our contract in a single transaction. Our `IVRFCoordinatorV2Plus` contract checks that mathematical proof on-chain—if anyone changed even a tiny bit of the number, the proof will not match and the call is rejected 🛡️. Because the verified random number is written into the transaction, every blockchain node receives the exact same random number, keeping consensus intact while ensuring every player has a fair, equal chance of winning! ⚖️

### 🕵️‍♂️ Blocks, Mempools & Why `block.timestamp` Can Be Manipulated
Whenever users make function calls or transactions, they are grouped together, verified, and added to the blockchain as a **block** 📦. We cannot use `block.timestamp` as our source of randomness because any participant can also be a validator node. A validator can see all pending transactions and data before the block is finalized—if they see that a specific timestamp would make their own address win the lottery, they can manipulate the block timing or when they propose the block for personal gain 🚨. Using Chainlink VRF prevents validators from gaming the lottery outcome.

---

## 🏗️ 3. System Architecture & Visual Flowcharts

## 📐 Architectural Box Diagram (ASCII Flowchart)

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
| 2. CHAINLINK AUTOMATION BOTS CHECK CONDITIONS (Off-Chain View Call)           |
|                                                                               |
| Chainlink Keeper Bots  --->  checkUpkeep("") [public view]                    |
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
| 3. LOCK LOTTERY & ORDER RANDOM NUMBER (RaffleState.CALCULATING)               |
|                                                                               |
| Chainlink Keeper Bots  --->  performUpkeep("") [external]                     |
| |-- Security Re-Check: calls checkUpkeep(""); reverts if false (0)            |
| |-- State Lock: s_raffleState = RaffleState.CALCULATING                       |
| |-- Build Order Form: VRFV2PlusClient.RandomWordsRequest memory request       |
| +-- Send Order: s_vrfCoordinator.requestRandomWords(request) -> requestId     |
+-------------------------------------------------------------------------------+
                                       |
                [Wait 3 Block Confirmations + Verify VRF Proof]
                                       |
                                       v
+-------------------------------------------------------------------------------+
| 4. THE SECURITY BOUNCER & WINNER PAYOUT (Resets Back to RaffleState.OPEN)     |
|                                                                               |
| VRFCoordinatorV2_5     --->  rawFulfillRandomWords(requestId, randomWords)    |
| |-- Bouncer Check (in VRFConsumerBaseV2Plus): msg.sender == Coordinator       |
| +-- Calls our override: fulfillRandomWords(requestId, randomWords)            |
| |-- Modulo Math: indexOfWinner = randomWords[0] % s_players.length            |
| |-- Pick Winner: recentWinner = s_players[indexOfWinner]                      |
| |-- Reset State: s_players = new address payable[](0)                         |
| |                s_raffleState = RaffleState.OPEN                             |
| |                s_lastTimeStamp = block.timestamp                            |
| |-- Emit Event:  emit WinnerPicked(recentWinner)                              |
| +-- Transfer:    (bool success,) = recentWinner.call{value: bal}("")          |
+-------------------------------------------------------------------------------+
```

### 🧩 Contract Inheritance & Imported Files

| Imported Contract / Library | Role in Our Architecture |
| :--- | :--- |
| 🛡️ **`VRFConsumerBaseV2Plus`** | Inherited by `Raffle`. Gives us communication logic with Chainlink VRF, provides `s_vrfCoordinator` (the actual coordinator contract reference), checks incoming random number security via `rawFulfillRandomWords`, and gives us the virtual `fulfillRandomWords` function to override. |
| 📡 **`IVRFCoordinatorV2Plus`** | The interface type of `s_vrfCoordinator`—the actual on-chain contract address where we send our `requestRandomWords` transaction. |
| 📋 **`VRFV2PlusClient`** | Library that holds the `RandomWordsRequest` struct (the "order form" containing all required inputs for `requestRandomWords`) and `ExtraArgsV1` for choosing the gas payment mode. |
| 🤖 **`AutomationCompatibleInterface`** | Interface that makes sure our contract includes the exact `checkUpkeep` and `performUpkeep` function signatures that Chainlink Automation bots are hardcoded to look for. |

### 🚦 State Machine Table (`enum RaffleState`)

We created a custom human-readable `enum RaffleState { OPEN, CALCULATING }` to prevent people from entering while a winner is being chosen:

| Current `s_raffleState` | `enterRaffle()` | `checkUpkeep()` | `performUpkeep()` | `fulfillRandomWords()` |
| :--- | :--- | :--- | :--- | :--- |
| 🟢 **`OPEN` (`0`)** | ✅ Allows players to enter if `msg.value >= i_entranceFee` | ✅ Returns `true` (`1`) once time interval & player checks pass | ✅ Locks state to `CALCULATING` & orders random number | 💤 Waiting for a request |
| 🟡 **`CALCULATING` (`1`)** | 🚫 Reverts with `Raffle__RaffleNotOpen()` | ❌ Always returns `false` (`0`) because `isOpen` is false | 🚫 Reverts with `Raffle__UpkeepNotNeeded(...)` | 🏆 Picks winner, sends ETH & resets state back to `OPEN` |

---

## 🔍 4. Deep Dive: Core Smart Contract (`src/Raffle.sol`)

### 🎟️ 1. `enterRaffle()` — Entrance Fee, Overpayment Brainstorm & `s_players` Array
* **Immutable Entrance Fee (`i_entranceFee`):** Set once inside the `constructor` so we can choose the fee on deployment while saving gas every time it is read.
* **Custom Error Check:** If `msg.value < i_entranceFee`, the function reverts with our custom error `Raffle__SendMoreToEnterRaffle()`, which saves gas compared to storing a `require` text string (note: in Solidity `0.8.26+`, `require` can also use custom errors, while `if + revert` works across `0.8.19+`).
* 💡 **What Happens If Someone Pays *More* Than the Entrance Fee?** Because the check is `if (msg.value < i_entranceFee)` and `s_players.push(payable(msg.sender))` only runs **once** per function call without refunding extra ETH, paying extra still gives that caller **one single entry** in the `s_players` array while the extra ETH stays in the contract balance and adds to the total prize pool.
* **Payable Player Array (`address payable[] private s_players`):** We store players in a `payable` address array so that when one of them wins, we can directly transfer the ETH prize to their address.

### 📢 2. Why We Emit `RaffleEnter(address indexed player)` After Updating Storage
Whenever we update the `s_players` storage array, we emit `emit RaffleEnter(msg.sender);`. Beyond being a best practice when updating storage, there is a practical frontend reason 🌐:
* In a real-world project, users enter the lottery through a website (frontend).
* A normal web2 frontend cannot pay gas to run transactions just to check state, whereas **events** are emitted as blockchain logs that websites can listen to and read for free! 🆓
* We marked the `player` address parameter as `indexed` (making it a **Topic**). This highlights and separates the player's address from raw low-level event data so the website can easily filter for that specific user's wallet and display a *"Raffle Entered!"* confirmation popup on their screen 🎯.

### 🔄 3. `constructor` vs. `fulfillRandomWords` (The Reset Button)
* **Why `VRFConsumerBaseV2Plus(vrfCoordinator)` Is in the Constructor Header:** When deploying `Raffle`, we pass `vrfCoordinator` into the parent `VRFConsumerBaseV2Plus` constructor so our inherited contract knows which VRF Coordinator address (`s_vrfCoordinator`) to talk to later when picking a winner.
* **`fulfillRandomWords` Is Essentially the Constructor on Repeat 🔁:** Just like the constructor opens the raffle (`s_raffleState = RaffleState.OPEN`) and starts the clock (`s_lastTimeStamp = block.timestamp`) when deployed, `fulfillRandomWords` resets `s_players = new address payable[](0)`, sets `s_raffleState = RaffleState.OPEN` again so the `if` check in `enterRaffle` lets new players in, and updates `s_lastTimeStamp = block.timestamp` for the next round!

### 💸 4. Sending the Prize with Low-Level `.call` & Boolean Logic
To pay the winner at the end of `fulfillRandomWords`, we execute Solidity's low-level `.call` on the `payable` winner address:

```solidity
(bool success,) = recentWinner.call{value: address(this).balance}("");
if (!success) {
    revert Raffle__TransferFailed();
}
```

* `{value: address(this).balance}` activates the ETH transfer and sends the entire balance of the raffle contract to `recentWinner`.
* `("")` is left empty because we only want to send ETH and do not want to trigger any extra function on the winner's address.
* `(bool success,)` unpacks the two items Solidity returns after a `.call`: the first variable `success` stores `true` (`1`) or `false` (`0`), and leaving the space after the comma empty catches and throws away the extra byte data we don't need.
* `if (!success)` checks if `success` is `0` (meaning the transfer failed) and reverts with our custom error `Raffle__TransferFailed()`.

---

## 🎲 5. Deep Dive: Chainlink VRF v2.5 & The Order Form

### 📋 Struct Instantiation & Named Arguments (`VRFV2PlusClient.RandomWordsRequest`)
Inside `performUpkeep`, we create an instance of the `RandomWordsRequest` struct from `VRFV2PlusClient` and store it in a `request` variable using curly brackets `{ ... }` to name each field clearly. Think of this struct as an **order form** 📝 that tells Chainlink VRF all the details about the random number we are ordering:

| Struct Field | Variable Passed In | What It Means in Simple Terms |
| :--- | :--- | :--- |
| ⛽ **`keyHash`** | `i_gasLane` (`bytes32`) | **The Gas Lane (Max Gas Price Tier):** A `bytes32` hash representing the maximum **gas price tier** (in Gwei) we are willing to pay when asking for the random number. |
| 🏦 **`subId`** | `i_subscriptionId` (`uint256`) | **Our Chainlink Bank Account Number:** Chainlink VRF is a single service used by thousands of contracts worldwide. To keep everyone's funds separate, we open a Subscription ID (like a bank account funded with LINK/ETH) to pay for our VRF transactions. (In VRF v2.5, this is a `uint256`). |
| 🧱 **`requestConfirmations`** | `REQUEST_CONFIRMATIONS` (`3`) | **Security Block Wait Time:** How many blocks Chainlink waits after our order before returning the random word. More blocks = more secure (since a malicious miner would have to mine more blocks in reverse to alter history, which is too costly), though waiting more blocks takes slightly more time. |
| 🛑 **`callbackGasLimit`** | `i_callbackGasLimit` (`500,000`) | **Callback Gas Unit Limit:** The limit on how much gas (how much of our subscription money) Chainlink VRF is allowed to spend when calling `fulfillRandomWords` to send the random number back to us. |
| 🔢 **`numWords`** | `NUM_WORDS` (`1`) | **How Many Random Numbers We Want:** Tells Chainlink how many `uint256` random numbers ("words" is the technical EVM term for 256-bit values) to put in the returned array. We only need `1`. |
| 💳 **`extraArgs`** | `_argsToBytes(ExtraArgsV1({nativePayment: false}))` | **Gas Payment Currency Mode:** Decides which currency our subscription uses to pay for gas (`false` = pay in LINK tokens, `true` = pay in native ETH). |

### 🛡️ How `rawFulfillRandomWords` Acts as a Security Bouncer
When we order the random number via `s_vrfCoordinator.requestRandomWords(request)`, Chainlink gives us back a unique receipt ID (`requestId`). When Chainlink finishes generating the random number, it calls `rawFulfillRandomWords` inside `VRFConsumerBaseV2Plus`.
* **The Bouncer:** `rawFulfillRandomWords` checks security first (making sure the caller is really the `s_vrfCoordinator` contract).
* **The Virtual Override (`fulfillRandomWords`):** Because every developer needs to do something different with their random number, Chainlink created `fulfillRandomWords` as a virtual function in the base contract so we can `override` it and write our own winner-picking logic inside `Raffle.sol`!
* **Direct `calldata` Input:** The array `uint256[] calldata randomWords` is marked `calldata` so Chainlink can pass the random number directly for us to read without Solidity wasting gas copying the array into memory.

---

## 🤖 6. Deep Dive: Chainlink Automation (`checkUpkeep` & `performUpkeep`)

Chainlink Automation uses off-chain node bots that are hardcoded to recognize and execute two specific functions from `AutomationCompatibleInterface` (separate from the VRF interface):

### 🔎 1. `checkUpkeep(bytes memory /* checkData */)`
* **Purpose:** A `view`-only function that off-chain bots simulate on every block to check if all conditions are met to pick a winner.
* **Why the Input Is Commented Out (`/* checkData */`):** At the low level, the oracle bots look for the exact `checkUpkeep(bytes)` function signature they were coded for. We don't need any custom `bytes` input, so we leave the `bytes memory` slot in the signature and comment out the parameter name—satisfying both the bots and the Solidity compiler!
* **Why `public` Instead of `external`:** We mark `checkUpkeep` as `public` (not `external`) because we also have to call `checkUpkeep("")` internally inside `performUpkeep`.
* **How the `&&` Boolean Logic Works:** We check four boolean conditions (`timePassed`, `isOpen`, `hasBalance`, `hasPlayers`). Each condition stores `true` (`1`) if met, and we combine all four using `&&` (logical AND):
  ```solidity
  upkeepNeeded = (timePassed && isOpen && hasBalance && hasPlayers);
  return (upkeepNeeded, "0x0");
  ```
  `upkeepNeeded` will only store `true` (`1`) if **all four** variables are `true` (`1`), and we return an empty `"0x0"` placeholder for the second `bytes memory` return slot that we don't need.

### ⚡ 2. `performUpkeep(bytes calldata /* performData */)`
* **Purpose:** Once `checkUpkeep` returns `true` (`1`), the Chainlink Automation bot broadcasts a real on-chain transaction calling `performUpkeep("")` (marked `external` to save gas).
* **On-Chain Guard Check:** First, we call `(bool upkeepNeeded,) = checkUpkeep("");` (storing the true/false result in a local `bool` variable in memory and throwing away the unused byte string after the comma). We then check `if (!upkeepNeeded)`—if it is `0` (`false`), we immediately revert with `Raffle__UpkeepNotNeeded(address(this).balance, s_players.length, uint256(s_raffleState))`. If it passes, we lock `s_raffleState = RaffleState.CALCULATING` and order the random word!

---

## ➗ 7. The Mathematics of Fair Winner Selection

When Chainlink calls `fulfillRandomWords`, it places our random number at the `0th` index of the `randomWords` array (`randomWords[0]`). We then pick the winner index using the **modulo (`%`)** operator:

```solidity
uint256 indexOfWinner = randomWords[0] % s_players.length;
address payable recentWinner = s_players[indexOfWinner];
```

### 🧮 Why `randomWords[0] % s_players.length` Always Works
1. **Remainder Rule:** Suppose `s_players.length` is $x$. When we divide `randomWords[0]` by $x$ and use the modulo (`%`) operator to get the remainder, basic math rules say the remainder will **at most be one less than the divisor ($x - 1$)**, giving a number from $0$ to $x - 1$.
2. **Array Index Rule:** In Solidity, array indices start at $0$, so the highest index in `s_players` is also **one less than the length ($x - 1$)**.
3. **Guaranteed Match + Randomness:** Because both the modulo remainder and the `s_players` array indices go from $0$ to $x - 1$, `indexOfWinner` will **always** be a valid index that exists inside `s_players`! And because one of the two numbers in the arithmetic operation (`randomWords[0]`) was random, the resulting `indexOfWinner` is also completely random 🎲.

---

## 🛠️ 8. Scripts & Multi-Chain Setup (`HelperConfig`, `DeployRaffle`, & `Interactions`)

### 🌐 1. Local Anvil vs. Live Testnets (Like Sepolia)
On a live testnet like **Sepolia**, Chainlink's VRF Coordinator contract, LINK token, and Automation bots already exist and are integrated into the network. On our local **Foundry Anvil** sandbox network (`chainId == 31337`), none of those Chainlink contracts or bots exist, so we deploy local **Mock** contracts (`VRFCoordinatorV2_5Mock` and `LinkToken`) and use our own scripts and tests to simulate their calls!

### ⚙️ 2. `script/HelperConfig.s.sol` (Why Sepolia & Anvil Work Differently)
`HelperConfig` inherits `Script` and an abstract contract `CodeConstants` (which stores our chain IDs and mock fee constants) so our deployment script can automatically get the right `NetworkConfig` struct for whichever chain we are on:
* **Why Sepolia Uses the `constructor` Mapping:** `getSepoliaEthConfig()` is a `pure` function because Sepolia already has a live VRF Coordinator address (`0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B`), gas lane, and LINK address. Inside the `constructor`, we map `networkConfigs[ETH_SEPOLIA_CHAIN_ID] = getSepoliaEthConfig();`. When `getConfigByChainId` runs on Sepolia, the first `if (networkConfigs[chainId].vrfCoordinatorV2_5 != address(0))` check sees that the address is not `0` and returns the Sepolia config right away.
* **Why Anvil Uses `getOrCreateAnvilEthConfig()` & `localNetworkConfig`:** Because Anvil is an isolated local environment without Chainlink VRF, we cannot just return hardcoded addresses in a `pure` function—we have to actually deploy `new VRFCoordinatorV2_5Mock(...)` and `new LinkToken()` using `vm.startBroadcast()` and `vm.stopBroadcast()`. In the constructor, we leave Anvil (`31337`) out of the mapping so its address defaults to `0`. When `getConfigByChainId(31337)` runs on Anvil, the first `if` check fails (since the mapping address is `0`), and the `else if (chainId == LOCAL_CHAIN_ID)` branch calls `getOrCreateAnvilEthConfig()`, which deploys the mocks, stores the config in the `localNetworkConfig` storage variable so we don't deploy duplicate mocks on repeat calls, and returns it! If an unsupported `chainId` is passed, both `if` checks fail and it reverts with `HelperConfig__InvalidChainId()`.

### 🚀 3. `script/DeployRaffle.s.sol` (Connecting Configs to Tests)
In `DeployRaffle.s.sol`, `deployContract()` creates a `new HelperConfig()`, calls `helperConfig.getConfig()` to get the `NetworkConfig memory config` for the current chain, deploys `Raffle` using `vm.startBroadcast()` with the inputs from `config`, and returns `(raffle, helperConfig)`. Returning both `Raffle` and `HelperConfig` allows our test file (`RaffleTest.t.sol`) to run the exact same deployment script in `setUp()` and grab all network variables directly from `HelperConfig`!

### 🔗 4. `script/Interactions.s.sol` (Automating VRF Subscriptions)
If `config.subscriptionId == 0` when deploying, `DeployRaffle` uses three helper script contracts from `Interactions.s.sol` to set up our Chainlink VRF "bank account" automatically:
1. 🆕 **`CreateSubscription`:** Calls `createSubscription()` on the VRF Coordinator to generate a new `subId`.
2. 💰 **`FundSubscription`:** Funds that `subId` with `3 ether` (3 LINK). On local Anvil (`31337`), it calls `VRFCoordinatorV2_5Mock.fundSubscription(subId, FUND_AMOUNT)`. On Sepolia, it calls `LinkToken(link).transferAndCall(vrfCoordinatorV2_5, FUND_AMOUNT, abi.encode(subId))`.
3. ➕ **`AddConsumer`:** Uses `DevOpsTools.get_most_recent_deployment("Raffle", block.chainid)` (or the newly deployed `Raffle` address) and calls `addConsumer(subId, raffleAddress)` on the VRF Coordinator so Chainlink recognizes our `Raffle` contract as an authorized caller.

---

## ⚡ 9. Gas Optimizations & Security Choices

| Feature Used in `Raffle.sol` | Why We Used It (Gas & Security Benefit) |
| :--- | :--- |
| 🚨 **Custom Errors (`revert Raffle__...`)** | Saves gas compared to `require(..., "error string")` because Solidity only stores a tiny error code instead of a full sentence string. |
| 🪨 **`immutable` & `constant` Variables** | Variables set once in the constructor (`i_entranceFee`, `i_interval`, `i_gasLane`, `i_subscriptionId`, `i_callbackGasLimit`) and constants (`REQUEST_CONFIRMATIONS`, `NUM_WORDS`) are baked directly into bytecode instead of expensive storage slots. |
| 📥 **`calldata` on `randomWords`** | Marking `uint256[] calldata randomWords` in `fulfillRandomWords` lets Solidity read the array directly from the call input instead of copying it into memory. |
| 🔒 **`private` State Variables + Getters** | State variables (`s_players`, `s_recentWinner`, `s_raffleState`, `s_lastTimeStamp`) are marked `private` with dedicated `view` getter functions (`getEntranceFee()`, `getPlayer()`, `getRecentWinner()`, `getRaffleState()`) for clean access control. |
| 🛡️ **State Locking & Resetting Before Payout** | `performUpkeep` locks `s_raffleState = CALCULATING` before ordering the random number, and `fulfillRandomWords` resets `s_players`, sets `s_raffleState = OPEN`, and updates `s_lastTimeStamp` *before* sending ETH via `.call`, preventing reentrancy attacks. |

---

## 🧪 10. Testing Showcase & Gas Execution Profile (`test/unit/RaffleTest.t.sol`)

### 📊 Visual Gas Consumption Profile Across All 11 Tests (ASCII Bar Chart)

```
Test Function Name (RaffleTest.t.sol)                     Gas Used   Visual Bar
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

### 🧾 Complete Test Suite Breakdown

| Full Test Name in `RaffleTest.t.sol` | Cheatcodes Used | What the Test Verifies | Gas |
| :--- | :--- | :--- | :--- |
| `testRaffleInitializesInOpenState` | None (`view`) | Checks that `raffle.getRaffleState() == Raffle.RaffleState.OPEN` right after deployment. | `7,753` |
| `testRaffleRevertsWhenYouDontPayEnough` | `vm.prank`, `vm.expectRevert` | Checks that calling `enterRaffle()` with `0` ETH reverts with `Raffle__SendMoreToEnterRaffle`. | `11,200` |
| `testPerformUpkeepRevertsIfCheckUpkeepIsFalse` | `vm.prank`, `vm.expectRevert` | Checks that calling `performUpkeep("")` early reverts with `Raffle__UpkeepNotNeeded(balance, numPlayers, rState)`. | `17,399` |
| `testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep` | Fuzz (`uint256 randomRequestId`), `skipFork` | Runs 256 fuzz tests passing random fake `requestId` numbers to `VRFCoordinatorV2_5Mock` to make sure it reverts. | `18,500` |
| `testCheckUpkeepReturnsFalseIfItHasNoBalance` | `vm.warp`, `vm.roll` | Fast-forwards time past `interval` with 0 balance/players and checks that `checkUpkeep("")` returns `false`. | `19,096` |
| `testRaffleRecordsPlayersWhenTheyEnter` | `vm.prank` | Enters with `PLAYER` and `entranceFee`, then checks `raffle.getPlayer(0) == PLAYER`. | `67,500` |
| `testEnteringRaffleEmitsEvent` | `vm.prank`, `vm.expectEmit` | Verifies that `emit RaffleEnter(PLAYER)` is emitted when `PLAYER` enters the raffle. | `68,752` |
| `testPerformUpkeepCanOnlyRunIfCheckUpkeepIsTrue` | `vm.prank`, `vm.warp`, `vm.roll` | Enters a player, advances `block.timestamp` and `block.number`, and confirms `performUpkeep("")` succeeds. | `126,958` |
| `testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId` | `vm.recordLogs`, `vm.getRecordedLogs` | Records emitted events during `performUpkeep("")`, grabs `requestId` from `entries[1].topics[1]`, and checks `raffleState == 1`. | `144,057` |
| `testDontAllowPlayersToEnterWhileRaffleIsCalculating` | `vm.prank`, `vm.warp`, `vm.roll`, `vm.expectRevert` | Runs `performUpkeep("")` to put the raffle in `CALCULATING` state and verifies new entries revert with `Raffle__RaffleNotOpen`. | `161,916` |
| `testFulfillRandomWordsPicksAWinnerResetsAndSendsMoney` | `hoax`, `vm.recordLogs`, `skipFork` | Full end-to-end test: adds 4 players, runs `performUpkeep("")`, triggers `VRFCoordinatorV2_5Mock.fulfillRandomWords`, and checks that the winner receives the full prize pot and the raffle resets to `OPEN`. | `310,543` |

### 🛠️ How Our Key Foundry Cheatcodes Work
* ⏰ **`vm.warp(block.timestamp + interval + 1)` & `vm.roll(block.number + 1)`:** Simulates time passing and a new block being mined on our local chain so `timePassed` in `checkUpkeep` becomes `true`.
* 🎭 **`vm.prank(PLAYER)` & `hoax(player, STARTING_BALANCE)`:** `vm.prank` sets `msg.sender` to `PLAYER` for the next call, while `hoax` both funds an address with ETH (`vm.deal`) and pranks it in a single step.
* 📜 **`vm.recordLogs()` & `entries[1].topics[1]`:** Captures all events emitted during `performUpkeep("")`. Because the `VRFCoordinatorV2_5Mock` emits its own event first (`entries[0]`), our `RequestedRaffleWinner(requestId)` event is at `entries[1]`, and its `indexed` `requestId` sits at `topics[1]`.
* 🔀 **`skipFork` Modifier:** Skips tests that call `VRFCoordinatorV2_5Mock.fulfillRandomWords` when running on a forked Sepolia network (`chainId != 31337`), because on live Sepolia only real Chainlink nodes can fulfill VRF requests.

---

## 🚀 11. Repository Structure & Quickstart

### 📂 Project Files

```
foundry-smart-contract-lottery-cu/
├── src/
│   └── Raffle.sol                 # 🎰 Main Lottery smart contract (VRF v2.5 + Automation)
├── script/
│   ├── DeployRaffle.s.sol         # 🚀 Deployment script returning (Raffle, HelperConfig)
│   ├── HelperConfig.s.sol         # ⚙️ ChainId mapping (Sepolia) & Anvil mock deployer
│   └── Interactions.s.sol         # 🔗 CreateSubscription, FundSubscription, AddConsumer
├── test/
│   ├── unit/RaffleTest.t.sol      # 🧪 Unit, fuzz, event log & full lifecycle tests
│   └── mocks/LinkToken.sol        # 🪙 Local LINK token mock for Anvil funding
├── Makefile                       # ⚡ Shortcuts for build, test, anvil & sepolia deploy
└── foundry.toml                   # 🛠️ Foundry configuration & remappings
```

### 💻 Installation & Testing Commands

1️⃣ **Clone the repo and install dependencies:**
```bash
git clone https://github.com/Yuvi8990/Foundry-Smart-Contract-Lottery.git
cd Foundry-Smart-Contract-Lottery
make install
forge build
```

2️⃣ **Run the test suite:**
```bash
# Run all unit and fuzz tests locally
forge test

# Run the full end-to-end lottery test with detailed traces
forge test --mt testFulfillRandomWordsPicksAWinnerResetsAndSendsMoney -vvvv

# Run forked tests against Sepolia
forge test --rpc-url $SEPOLIA_RPC_URL

# Check gas usage and test coverage
forge snapshot
forge coverage
```

3️⃣ **Deploy locally on Anvil or live on Sepolia:**
```bash
# Terminal 1: Start local Anvil node
make anvil

# Terminal 2: Deploy locally (automatically deploys mocks, creates/funds sub & adds consumer)
make deploy

# Deploy to Sepolia Testnet (requires SEPOLIA_RPC_URL and PRIVATE_KEY in .env)
make deploy ARGS="--network sepolia"
```

4️⃣ **Enter the Raffle on Sepolia using `cast`:**
```bash
cast send <RAFFLE_CONTRACT_ADDRESS> "enterRaffle()" --value 0.01ether --private-key $PRIVATE_KEY --rpc-url $SEPOLIA_RPC_URL
```

---

## 📜 License & Acknowledgements

* 📄 **License:** MIT License
* 🙏 **Acknowledgements:** Built by **Yuvraj Singh** with guidance from **Patrick Collins** and the **Cyfrin Updraft Foundry Fundamentals** course (`foundry-smart-contract-lottery-cu`). All architectural walkthroughs and mathematical explanations in this README are based on my personal study notes written while building the project. 

---
