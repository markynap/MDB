//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

interface ITrigger {
    function trigger() external;
}

interface IMDB {
    function getOwner() external view returns (address);
    function sellFeeRecipient() external view returns (address);
    function buyFeeRecipient() external view returns (address);
    function transferFeeRecipient() external view returns (address);
}

contract ReceiverTrigger {

    // Address => Can Call Trigger
    mapping ( address => bool ) public approved;

    // MDB Token
    IMDB public immutable MDB;

    // Events
    event Approved(address caller, bool isApproved);

    // Ownership
    modifier onlyOwner(){
        require(
            msg.sender == IMDB(token).getOwner(),
            'Only MDB Owner'
        );
        _;
    }

    constructor(address MDB_) {
        approved[msg.sender] = true;
        MDB = IMDB(MDB_);
    }

    function triggerAll() external {
        if (!approved[msg.sender]) {
            return;
        }

        address o1 = MDB.sellFeeRecipient();
        address o2 = MDB.buyFeeRecipient();
        address o3 = MDB.transferFeeRecipient();

        if (o1 != address(0)) {
            ITrigger(o1).trigger();
        }
        if (o2 != address(0)) {
            ITrigger(o2).trigger();
        }
        if (o3 != address(0)) {
            ITrigger(o3).trigger();
        }
    }

    function setApproved(address caller, bool isApproved) external onlyOwner {
        approved[caller] = isApproved;
        emit Approved(caller, isApproved);
    }

}