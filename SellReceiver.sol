//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./IERC20.sol";
import "./IUniswapV2Router02.sol";

interface IMDB {
    function getOwner() external view returns (address);
}

contract SellReceiver {

    // MDB token
    address public immutable token;

    // router
    IUniswapV2Router02 router = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);

    // Recipients Of Fees
    address public trustFund;
    address public multisig;

    // Token -> BNB
    address[] path;

    modifier onlyOwner(){
        require(
            msg.sender == IMDB(token).getOwner(),
            'Only MDB Owner'
        );
        _;
    }

    constructor(address token_) {
        require(
            token_ != address(0),
            'Zero Address'
        );

        // Initialize Token
        token = token_;

        // Sell Path
        path = address[](2);
        path[0] = token_;
        path[1] = router.WETH();
    }

    function trigger() external {

        // MDB Balance In Contract
        uint balance = IERC20(token).balanceOf(address(this));
        
        if (balance > 0) {
            // sell MDB in contract for BNB
            IERC20(token).approve(address(router), balance);
            router.swapExactTokensForETHSupportingFeeOnTransferTokens(balance, 0, path, address(this), block.timestamp + 300);
        }

        if (address(this).balance > 0) {
            // fraction out bnb received
            uint part1 = address(this).balance * 95/ 100;
            uint part2 = address(this).balance - part1;

            // send to destinations
            _send(trustFund, part1);
            _send(multisig, part2);
        }
    }

    function setTrustFund(address tFund) external onlyOwner {
        require(tFund != address(0));
        trustFund = tFund;
    }
    function setMultisig(address multisig_) external onlyOwner {
        require(multisig_ != address(0));
        multisig = multisig_;
    }
    function withdraw() external onlyOwner {
        (bool s,) = payable(owner).call{vaule: amount}("");
        require(s);
    }
    function withdraw(address token) external onlyOwner {
        IERC20(token).transfer(owner, IERC20(token).balanceOf(address(this)));
    }
    receive() external payable {}
    function _send(address recipient, uint amount) internal {
        (bool s,) = payable(recipient).call{vaule: amount}("");
        require(s);
    }
}