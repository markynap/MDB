//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./IERC20.sol";

interface IXUSD {
    function resourceCollector() external view returns (address);
    function getOwner() external view returns (address);
}

contract FeeReceiver {

    address public XUSD = 0x324E8E649A6A3dF817F97CdDBED2b746b62553dD;
    IERC20 public BUSD = IERC20(0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56);

    uint public oAmt  = 10;
    uint public xAmt  = 50;
    uint public rAmt  = 40;

    modifier onlyOwner() {
        require(msg.sender == IXUSD(XUSD).getOwner(), 'Only Owner');
        _;
    }

    function setAmounts(
        uint _oAmt,
        uint _xAmt,
        uint _rAmt
    ) external onlyOwner {
        require(
            _oAmt + _xAmt + _rAmt == 100,
            'Invalid Amounts'
        );
        oAmt = _oAmt;
        xAmt = _xAmt;
        rAmt = _rAmt;
    }

    function trigger() external {

        uint bal = BUSD.balanceOf(address(this));
        if (bal > 0) {
            BUSD.transfer(
                IXUSD(XUSD).getOwner(),
                ( bal * oAmt ) / 100
            );

            BUSD.transfer(
                XUSD,
                ( bal * xAmt ) / 100
            );

            BUSD.transfer(
                IXUSD(XUSD).resourceCollector(),
                BUSD.balanceOf(address(this))
            );
        }
    }

    function withdraw(IERC20 token) external onlyOwner {        
        token.transfer(msg.sender, token.balanceOf(address(this)));
    }
}