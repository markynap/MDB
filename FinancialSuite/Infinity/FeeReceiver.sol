//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./IERC20.sol";
import "./IUniswapV2Router02.sol";

interface IMDB {
    function getOwner() external view returns (address);
}

contract FeeReceiver {

    // MDB token
    address public immutable token;

    // router
    IUniswapV2Router02 router = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);

    // Recipients Of Fees
    address public trustFund;
    address public marketing;

    // Token -> BNB
    address[] path;

    /**
        Minimum Amount Of MDB In Contract To Trigger `trigger` Unless `approved`
            If Set To A Very High Number, Only Approved May Call Trigger Function
            If Set To A Very Low Number, Anybody May Call At Their Leasure
     */
    uint256 public minimumTokensRequiredToTrigger;

    // Trust Fund Allocation
    uint256 public trustFundPercentage;

    // Address => Can Call Trigger
    mapping ( address => bool ) public approved;

    // Events
    event Approved(address caller, bool isApproved);

    modifier onlyOwner(){
        require(
            msg.sender == IMDB(token).getOwner(),
            'Only MDB Owner'
        );
        _;
    }

    constructor(address token_, address trustFund_, address marketing_) {
        require(
            token_ != address(0) &&
            trustFund_ != address(0) &&
            marketing_ != address(0),
            'Zero Address'
        );

        // Initialize Addresses
        token = token_;
        trustFund = trustFund_;
        marketing = marketing_;

        // Sell Path
        path = new address[](2);
        path[0] = token_;
        path[1] = router.WETH();

        // set initial approved
        approved[msg.sender] = true;

        // trust fund percentage
        trustFundPercentage = 80;

        // only approved can trigger at the start
        minimumTokensRequiredToTrigger = 10**30;
    }

    function trigger() external {

        // MDB Balance In Contract
        uint balance = IERC20(token).balanceOf(address(this));

        if (balance < minimumTokensRequiredToTrigger && !approved[msg.sender]) {
            return;
        }
        
        // sell MDB in contract for BNB
        IERC20(token).approve(address(router), balance);
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(balance, 0, path, address(this), block.timestamp + 300);

        if (address(this).balance > 0) {
            // fraction out bnb received
            uint part1 = address(this).balance * trustFundPercentage / 100;
            uint part2 = address(this).balance - part1;

            // send to destinations
            _send(trustFund, part1);
            _send(marketing, part2);
        }
    }

    function setTrustFund(address tFund) external onlyOwner {
        require(tFund != address(0));
        trustFund = tFund;
    }
    function setMarketing(address marketing_) external onlyOwner {
        require(marketing_ != address(0));
        marketing = marketing_;
    }
    function setApproved(address caller, bool isApproved) external onlyOwner {
        approved[caller] = isApproved;
        emit Approved(caller, isApproved);
    }
    function setMinTriggerAmount(uint256 minTriggerAmount) external onlyOwner {
        minimumTokensRequiredToTrigger = minTriggerAmount;
    }
    function setTrustFundPercentage(uint256 newAllocatiton) external onlyOwner {
        trustFundPercentage = newAllocatiton;
    }
    function withdraw() external onlyOwner {
        (bool s,) = payable(msg.sender).call{value: address(this).balance}("");
        require(s);
    }
    
    function withdraw(address _token) external onlyOwner {
        IERC20(_token).transfer(msg.sender, IERC20(_token).balanceOf(address(this)));
    }
    receive() external payable {}
    function _send(address recipient, uint amount) internal {
        (bool s,) = payable(recipient).call{value: amount}("");
        require(s);
    }
}