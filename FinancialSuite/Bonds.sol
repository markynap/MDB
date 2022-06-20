//SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import "./IERC20.sol";
import "./IUniswapV2Router02.sol";
import "./Ownable.sol";

/** 
    Tax Free MDB Purchases
    Locks Up Funds For 60 Days
    Minimum Amount To Purchase
 */
contract MDBBonds is Ownable {

    // MDB Token
    address public constant MDB = 0x0557a288A93ed0DF218785F2787dac1cd077F8f3;

    // PCS Router
    IUniswapV2Router02 public constant router = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);

    // Lock Time In Blocks
    uint256 public lockTime = 28800 * 60;

    // Minimum Value To Buy Bond
    uint256 public minimumValue = 10 * 10**18; // 10 BNB

    // Bond Structure
    struct Bond {
        address recipient;
        uint256 numTokens;
        uint256 unlockBlock;
        uint256 indexInUserArray;
    }
    // User -> ID[]
    mapping ( address => uint256[] ) public userIDs;
    // ID -> Bond
    mapping ( uint256 => Bond ) public bonds;

    // Global ID Nonce
    uint256 public nonce;

    // Number of active bonds
    uint256 public numberOfActiveBonds;

    // Swap Path
    address[] private path;

    // Events
    event BondCreated(address indexed user, uint amount, uint unlockBlock, uint bondID);

    constructor(){
        path = new address[](2);
        path[0] = router.WETH();
        path[1] = MDB;
    }

    function setLockTime(uint newLockTime) external onlyOwner {
        require(
            newLockTime < 28800 * 366,
            'Lock Time Too Long'
        );
        
        lockTime = newLockTime;
    }

    function setMinimumValue(uint newMinimum) external onlyOwner {
        require(
            newMinimum > 0,
            'Minimum too small'
        );

        minimumValue = newMinimum;
    }

    receive() external payable {
        _purchaseBond(msg.sender, msg.value, 0);
    }

    function purchaseBond() external payable {
        _purchaseBond(msg.sender, msg.value, 0);
    }

    function purchaseBond(uint minOut) external payable {
        _purchaseBond(msg.sender, msg.value, minOut);
    }

    function purchaseBondForUser(address user, uint minOut) external payable {
        _purchaseBond(user, msg.value, minOut);
    }

    function releaseBond(uint256 bondID) external {
        _releaseBond(bondID);
    }

    function releaseBonds(uint256[] calldata bondIDs) external {
        uint len = bondIDs.length;
        for (uint i = 0; i < len;) {
            _releaseBond(bondIDs[i]);
            unchecked { ++i; }
        }
    }

    function _releaseBond(uint256 bondID) internal {
        require(
            bondID < nonce,
            'Invalid Bond ID'
        );
        require(
            bonds[bondID].unlockBlock <= block.number,
            'Lock Time Has Not Passed'
        );

        // number of MDB tokens bond ID has held
        uint256 nTokens = bonds[bondID].numTokens;

        // recipient of the MDB Tokens held by bond ID
        address recipient = bonds[bondID].recipient;

        // Ensure ID Has Not Already Been Released
        require(
            nTokens > 0 &&
            recipient != address(0),
            'Bond has already been released'
        );

        // Maybe remove bondID from user array
        _removeBond(bondID);

        // send tokens back to recipient
        if (nTokens > balanceOf()) {
            nTokens = balanceOf();
        }
        require(
            IERC20(MDB).transfer(
                recipient,
                nTokens
            ),
            'Failure On Token Transfer'
        );
    }

    function _purchaseBond(address user, uint amount, uint minOut) internal {
        require(
            user != address(0),
            'Zero User'
        );
        require(
            amount >= minimumValue,
            'Amount Less Than Minimum'
        );

        // buy MDB
        uint received = _buy(amount, minOut);

        // register bond to nonce
        bonds[nonce].recipient = user;
        bonds[nonce].numTokens = received;
        bonds[nonce].unlockBlock = block.number + lockTime;
        bonds[nonce].indexInUserArray = userIDs[user].length;

        // register nonce to user
        userIDs[user].push(nonce);

        // emit event
        emit BondCreated(user, amount, bonds[nonce].unlockBlock, nonce);

        // increment global nonce
        nonce++;
        numberOfActiveBonds++;
    }

    function _buy(uint amount, uint minOut) internal returns (uint256) {

        // MDB balance before buy
        uint before = balanceOf();

        // swap BNB to MDB
        router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: amount}(minOut, path, address(this), block.timestamp + 100);

        // MDB balance after buy
        uint After = balanceOf();
        
        // ensure tokens were received
        require(
            After > before,
            'Zero Received'
        );

        // ensure minOut was preserved
        uint received = After - before;
        require(
            received >= minOut,
            'Min Out'
        );

        // return number of tokens purchased
        return received;
    }

    function _removeBond(uint256 bondID) internal {

        // index of bond ID we are removing
        uint rmIndex = bonds[bondID].indexInUserArray;
        // user who owns the bond ID
        address user = bonds[bondID].recipient;
        // length of user bond ID array
        uint userIDLength = userIDs[user].length;

        // set index of last element to be removed index
        bonds[
            userIDs[user][userIDLength - 1]
        ].indexInUserArray = rmIndex;

        // set removed element to be last element of user array
        userIDs[user][
            rmIndex
        ] = userIDs[user][userIDLength - 1];

        // pop last element off user array
        userIDs[user].pop();

        // decrement number of active bonds
        numberOfActiveBonds--;

        // remove bond data
        delete bonds[bondID];
    }

    function balanceOf() public view returns (uint256) {
        return IERC20(MDB).balanceOf(address(this));
    }
    
    function timeUntilUnlock(uint256 bondID) public view returns (uint256) {
        return bonds[bondID].unlockBlock <= block.number ? 0 : bonds[bondID].unlockBlock - block.number;
    }

    function numBonds(address user) public view returns (uint256) {
        return userIDs[user].length;
    }

    function fetchBondIDs(address user) external view returns (uint256[] memory) {
        return userIDs[user];
    }

    function fetchTotalTokensToClaim(address user) external view returns (uint256 total) {
        uint nBonds = numBonds(user);
        for (uint i = 0; i < nBonds; i++) {
            total += bonds[userIDs[user][i]].numTokens;
        }
    }

    function fetchTotalTokensToClaimThatCanBeClaimed(address user) external view returns (uint256 total) {
        (, uint256[] memory tokens) = fetchIDsAndNumTokensThatCanBeClaimed(user);
        for (uint i = 0; i < tokens.length; i++) {
            total += tokens[i];
        }
    }

    function fetchIDsAndNumTokensAndLockDurations(address user) external view returns (uint256[] memory, uint256[] memory, uint256[] memory) {
        uint nBonds = numBonds(user);
        uint256[] memory tokens = new uint256[](nBonds);
        uint256[] memory unlockDurations = new uint256[](nBonds);

        for (uint i = 0; i < nBonds; i++) {
            tokens[i] = bonds[userIDs[user][i]].numTokens;
            unlockDurations[i] = timeUntilUnlock(userIDs[user][i]);
        }
        return (userIDs[user], tokens, unlockDurations);
    }

    function fetchIDsAndNumTokensThatCanBeClaimed(address user) public view returns (uint256[] memory, uint256[] memory) {
        uint nBonds = numBonds(user);

        uint count = 0;
        for (uint i = 0; i < nBonds; i++) {
            if (timeUntilUnlock(userIDs[user][i]) == 0) {
                count++;
            }
        }

        uint256[] memory tokens = new uint256[](count);
        uint256[] memory IDs = new uint256[](count);

        uint uCount = 0;
        for (uint i = 0; i < nBonds; i++) {
            if (timeUntilUnlock(userIDs[user][i]) == 0) {
                tokens[uCount] = bonds[userIDs[user][i]].numTokens;
                IDs[uCount] = userIDs[user][i];
                uCount++;
            }
        }

        return (IDs, tokens);
    }

    function fetchIDsThatCanBeClaimed(address user) public view returns (uint256[] memory) {
        uint nBonds = numBonds(user);

        uint count = 0;
        for (uint i = 0; i < nBonds; i++) {
            if (timeUntilUnlock(userIDs[user][i]) == 0) {
                count++;
            }
        }

        uint256[] memory IDs = new uint256[](count);

        uint uCount = 0;
        for (uint i = 0; i < nBonds; i++) {
            if (timeUntilUnlock(userIDs[user][i]) == 0) {
                IDs[uCount] = userIDs[user][i];
                uCount++;
            }
        }

        return (IDs);
    }
}