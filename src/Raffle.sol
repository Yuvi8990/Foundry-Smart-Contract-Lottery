//SPDX-License-Identifier:MIT

pragma solidity 0.8.19;

/* Errors */
   error Raffle__Didnot_send_enough_raffleFee();

// having natSpec is a great way to annotate your smart contracts for devs and stuff and it also shows that you know what you are doing
/**
 * @title Raffle contract
 * @author Yuvraj Singh
 * @notice This contract creates a sample raffle.
 * @dev Implements Chainlink VRFv2.5
 */

contract Raffle {

    uint256 private immutable i_entranceFee;

    address payable[] private s_players; //since one of the addresses stored inside here wins, and will needs to be paid the prize so payable

    constructor(uint256 entranceFee) {
        i_entranceFee = entranceFee;
    }

    function enterRaffle() public payable {
        if (msg.value < i_entranceFee) {
            revert Raffle__Didnot_send_enough_raffleFee();
            }
        s_players.push(payable(msg.sender));    
    }

    function pickWinner() public {

    }

    /** Getter Functions */
    function getEntranceFee() public view returns(uint256){
        return i_entranceFee;
    }
}    

// rule of thumb -- we always emit an event whenever we update something in storage.
// events make -- migration easier(easy storage movement during redoplyment) and makes front end "indexing" easier