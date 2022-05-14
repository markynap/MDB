//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./IERC20.sol";
import "./IUniswapV2Router02.sol";

interface IMDB {
    function burn(uint256 amount) external;
}

contract Adjustor {

    // Token Address
    address private immutable token;

    // Address => Can Adjust
    mapping ( address => bool ) private canAdjust;

    // Liquidity Pool Address
    address private immutable LP;

    // Dead Wallet
    address private constant dead = 0x000000000000000000000000000000000000dEaD;

    // DEX Router
    IUniswapV2Router02 private router;

    // Path
    address[] path;

    modifier onlyAdjustor(){
        require(
            canAdjust[msg.sender],
            'Only Adjustors'
        );
        _;
    }

    constructor(
        address token_
    ) {

        // token
        token = token_;

        // permission to adjust
        canAdjust[msg.sender] = true;

        // DEX Router
        router = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);

        // Liquidity Pool Token
        LP = IUniswapV2Factory(router.factory()).getPair(token_, router.WETH());

        // swap path
        path = new address[](2);
        path[0] = router.WETH();
        path[1] = token_;
    }

    function setAdjustor(address adjustor_, bool canAdjust_) external onlyAdjustor {
        canAdjust[adjustor_] = canAdjust_;
    }

    function adjust(uint256 amount, address destination) external onlyAdjustor {
        _adjust(amount, destination);
    }

    function withdrawLP() external onlyAdjustor {
        IERC20(LP).transfer(msg.sender, lpBalance());
    }

    function withdrawToken() external onlyAdjustor {
        IERC20(token).transfer(msg.sender, IERC20(token).balanceOf(address(this)));
    }
    
    function withdraw() external onlyAdjustor {
        (bool s,) = payable(msg.sender).call{value: address(this).balance}("");
        require(s);
    }

    receive() external payable {}

    function _adjust(uint256 amount, address destination) internal {

        // Approve Router For Amount
        IERC20(LP).approve(address(router), amount);

        // Remove `Amount` Liquidity
        router.removeLiquidityETHSupportingFeeOnTransferTokens(
            token, amount, 0, 0, address(this), block.timestamp + 5000000
        );

        // Swap ETH Received For More Tokens
        router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: address(this).balance}(
            0,
            path,
            address(this),
            block.timestamp + 300
        );

        // Forward All Tokens Received
        if (destination == dead) {
            IMDB(token).burn(IERC20(token).balanceOf(address(this)));
        } else {
            IERC20(token).transfer(destination, IERC20(token).balanceOf(address(this)));
        }
    }

    function lpBalance() public view returns (uint256) {
        return IERC20(LP).balanceOf(address(this));
    }
}