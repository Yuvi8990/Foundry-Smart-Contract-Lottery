//SPDX-License-Identifier:MIT

pragma solidity 0.8.19;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";

/* Errors */
   error Raffle__Didnot_send_enough_raffleFee();
   error Rffle__NotEnoughTimeHasPassedForDraw();

// having natSpec is a great way to annotate your smart contracts for devs and stuff and it also shows that you know what you are doing
/**
 * @title Raffle contract
 * @author Yuvraj Singh
 * @notice This contract creates a sample raffle.
 * @dev Implements Chainlink VRFv2.5
 */

contract Raffle is VRFConsumerBaseV2Plus {
    uint256 private immutable i_entranceFee;
    // @dev The duration (in seconds) between start and picking a winner of lottery
    uint256 private immutable i_interval;
    address payable[] private s_players; //since one of the addresses stored inside here wins, and will needs to be paid the prize so payable
    uint256 private s_lastTimeStamp;

    /* Events */
    event RaffleEntered(address indexed player);

    constructor(uint256 entranceFee, uint256 interval, address vrfCoordinator) 
    VRFConsumerBaseV2Plus(vrfCoordinator) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        s_lastTimeStamp = block.timestamp;
        s_vrfCoordinator.requestRandomWords();
    }

    function enterRaffle() external payable {
        if (msg.value < i_entranceFee) {
            revert Raffle__Didnot_send_enough_raffleFee();
            }
        s_players.push(payable(msg.sender));    
        emit RaffleEntered(msg.sender);
    }

    // 1. Get a random number
    // 2. use that random number to pick a player
    // 3. this function needs to be automatically called
    function pickWinner() external {
        //first we check if enough time has passed before picking a winner.
        if(block.timestamp - s_lastTimeStamp < i_interval) {
            revert Rffle__NotEnoughTimeHasPassedForDraw();
        }
        // Get our random number from blockchain
        requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: s_keyHash,
                subId: s_subscriptionId,
                requestConfirmations: requestConfirmations,
                callbackGasLimit: callbackGasLimit,
                numWords: numWords,
                // Set nativePayment to true to pay for VRF requests with Sepolia ETH instead of LINK
                extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: false}))
            })
        );
    }

    /** Getter Functions */
    function getEntranceFee() public view returns(uint256){
        return i_entranceFee;
    }
}    

// rule of thumb -- we always emit an event whenever we update something in storage.
// events make -- migration easier(easy storage movement during redoplyment) and makes front end "indexing" easier 
// block.timestamp is the active time after deployment of contract on blockchain and this global variable gives it