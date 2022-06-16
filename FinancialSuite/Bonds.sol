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
    }
    // User -> ID[]
    mapping ( address => uint256[] ) public userIDs;
    // ID -> Bond
    mapping ( uint256 => Bond ) public bonds;

    // Global ID Nonce
    uint256 public nonce;

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

        // should we let anyone release or only bond user?
            // if anyone -- nothing bad would really happen, no incentive for not claiming bond
            // if restricted -- people could get screwed out of funds if they lose access to wallet

        uint256 nTokens = bonds[bondID].numTokens;
        address recipient = bonds[bondID].recipient;

        require(
            nTokens > 0 &&
            recipient != address(0),
            'Invalid Bond ID'
        );

        require(
            bonds[bondID].unlockBlock <= block.number,
            'Lock Time Has Not Passed'
        );

        // delete storage
        delete bonds[bondID];

        // Maybe remove bondID from user array

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

        // register nonce to user
        userIDs[user].push(nonce);

        // register bond to nonce
        bonds[nonce].recipient = user;
        bonds[nonce].numTokens = received;
        bonds[nonce].unlockBlock = block.number + lockTime;

        // emit event
        emit BondCreated(user, amount, bonds[nonce].unlockBlock, nonce);

        // increment global nonce
        nonce++;
    }

    function _buy(uint amount, uint minOut) internal returns (uint256) {

        uint before = balanceOf();

        router.swapExactETHForTokensSupportingFeeOnTransferTokens(minOut, path, address(this), block.timestamp + 100);

        uint After = balanceOf();
        require(
            After > before,
            'Zero Received'
        );
        uint received = After - before;
        require(
            received >= minOut,
            'Min Out'
        );
        return received;
    }

    function balanceOf() public view returns (uint256) {
        return IERC20(MDB).balanceOf(address(this));
    }
}