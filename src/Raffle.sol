//SPDX-License-Identifier:MIT

pragma solidity 0.8.19;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

/* Errors */
   error Raffle__Didnot_send_enough_raffleFee();
   error Raffle__NotEnoughTimeHasPassedForDraw();

// having natSpec is a great way to annotate your smart contracts for devs and stuff and it also shows that you know what you are doing
/**
 * @title Raffle contract
 * @author Yuvraj Singh
 * @notice This contract creates a sample raffle.
 * @dev Implements Chainlink VRFv2.5
 */

contract Raffle is VRFConsumerBaseV2Plus {
    uint256 private immutable i_entranceFee;
    uint256 private immutable i_interval;
    bytes32 private immutable i_keyHash;
    uint256 private immutable i_subscriptionId;
    address payable[] private s_players; //since one of the addresses stored inside here wins, and will needs to be paid the prize so payable
    uint256 private s_lastTimeStamp;
   

    /* Events */
    event RaffleEntered(address indexed player);

    constructor(uint256 entranceFee, uint256 interval, address vrfCoordinator,
        bytes32 gasLane, uint256 subscriptionId) 
    VRFConsumerBaseV2Plus(vrfCoordinator) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        i_keyHash = gasLane;
        i_subscriptionId = subscriptionId;
        s_lastTimeStamp = block.timestamp;
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
            revert Raffle__NotEnoughTimeHasPassedForDraw();
        }
        // Get our random number from blockchain

        VRFV2PlusClient.RandomWordsRequest request = VRFV2PlusClient.RandomWordsRequest({
                keyHash: i_keyHash,
                subId: i_subscriptionId,
                requestConfirmations: requestConfirmations,
                callbackGasLimit: callbackGasLimit,
                numWords: numWords,
                extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: false}))
            });

        uint256 requestId = s_vrfCoordinator.requestRandomWords(
               request
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