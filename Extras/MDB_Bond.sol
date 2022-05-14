//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./IERC20.sol";
import "./IUniswapV2Router02.sol";

contract MDBBond {

    IUniswapV2Router02 router = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);
    uint lockTime = 1728000;
    IERC20 MDB = IERC20(0x0557a288A93ed0DF218785F2787dac1cd077F8f3);
    address[] path;

    struct BondUser {
        uint amount;
        uint unlockBlock;
    }
    mapping ( address => BondUser) bonds;

    constructor(){
        path = new address[](2);
        path[0] = router.WETH();
        path[1] = address(MDB);
    }

    function _swap() internal returns (uint) {
        uint before = MDB.balanceOf(address(this));
        router.swapExactETHForTokens{value: address(this).balance}(
            0,
            path,
            address(this),
            block.timestamp + 300
        );
        uint after = MDB.balanceOf(address(this));
        require(after > before, 'Zero Received');
        return after - before;
    }

    function claim() external {
        uint amount = bonds[msg.sender].amount;
        require(
            amount > 0,
            'No Bond Registered'
        );
        require(
            bonds[msg.sender].unlockBlock <= block.number,
            'Not Time To Claim'
        );
        delete bonds[msg.sender];
        MDB.transfer(msg.sender, amount);
    }

    receive() external payable {
        require(
            msg.value > 0,
            'Zero value'
        )
        require(
            bonds[msg.sender].amount == 0,
            'Already Owns A Bond'
        );
        uint received = _swap();
        bonds[msg.sender].amount = received;
        bonds[msg.sender].unlockBlock = block.number + lockTime;
    }

}