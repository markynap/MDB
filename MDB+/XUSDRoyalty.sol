//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./Ownable.sol";

contract XUSDRoyalty is Ownable {

    uint256 private fee;
    address private feeRecipient;

    function setFee(uint newFee) external onlyOwner {
        require(
            newFee <= 50,
            'Fee Too High'
        );
        fee = newFee;
    }

    function setFeeRecipient(address recipient) external onlyOwner {
        require(
            recipient != address(0),
            'Zero Address'
        );
        feeRecipient = recipient;
    }

    function getFee() external view returns (uint256) {
        return fee;
    }

    function getFeeRecipient() external view returns (address) {
        return feeRecipient;
    }


}