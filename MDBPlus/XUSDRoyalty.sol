//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

interface IXUSD {
    function getOwner() external view returns (address);
}

contract XUSDRoyalty {

    address public constant XUSD = 0x324E8E649A6A3dF817F97CdDBED2b746b62553dD;
    uint256 private fee;
    address private feeRecipient;

    modifier onlyOwner(){
        require(msg.sender == IXUSD(XUSD).getOwner(), 'Only Owner');
        _;
    }

    constructor(uint fee_, address recipient_) {
        fee = fee_;
        feeRecipient = recipient_;
    }

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