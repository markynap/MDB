//SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import "./IERC20.sol";
import "./Ownable.sol";
import "./IUniswapV2Router02.sol";

library SafeMath {
    /**
     * @dev Returns the addition of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `+` operator.
     *
     * Requirements:
     *
     * - Addition cannot overflow.
     */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting with custom message on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;

        return c;
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `*` operator.
     *
     * Requirements:
     *
     * - Multiplication cannot overflow.
     */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }

    /**
     * @dev Returns the integer division of two unsigned integers. Reverts on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }

    /**
     * @dev Returns the integer division of two unsigned integers. Reverts with custom message on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold

        return c;
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * Reverts when dividing by zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return mod(a, b, "SafeMath: modulo by zero");
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * Reverts with custom message when dividing by zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b != 0, errorMessage);
        return a % b;
    }
}

abstract contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;
    constructor () {
        _status = _NOT_ENTERED;
    }

    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
}

interface XUSDRoyalty {
    function getFee() external view returns (uint256);
    function getFeeRecipient() external view returns (address);
}

interface IMDBPlus {
    function mintWithBacking(uint256 numTokens, address recipient) external returns (uint256);
}

/**

    Phoenix Plus:
        Basically MDB+
        1% in and out tax
        No maximum holdings, but can be knocked down to a minimum value
        Contract can sell down holders to a minimum value, almost gamified
            Is it individual holders that get booted, or is it everyone at once?
 */
contract PhoenixPlus is IERC20, Ownable, ReentrancyGuard {
    
    using SafeMath for uint256;

    // token data
    string private constant _name = "Phoenix+";
    string private constant _symbol = "PHOENIX+";
    uint8 private constant _decimals = 18;
    uint256 private constant precision = 10**18;
    
    // 1 initial supply
    uint256 private _totalSupply = 10**18; 
    
    // balances
    mapping (address => uint256) private _balances;
    mapping (address => mapping (address => uint256)) private _allowances;

    // address -> Fee Exemption
    mapping ( address => bool ) public isTransferFeeExempt;

    // Token Activation
    bool public tokenActivated;

    // Dead Wallet
    address private constant DEAD = 0x000000000000000000000000000000000000dEaD;

    // MDB Plus
    address public constant MDBPlus = 0x9f8BB16f49393eeA4331A39B69071759e54e16ea;

    // PCS Router
    IUniswapV2Router02 private router = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);

    // Royalty Data Fetcher
    XUSDRoyalty private constant royaltyTracker = XUSDRoyalty(0x4b4e239342E0BEf29FccbFe662Dd30029f21F7fF);

    // Swap Path From BNB -> BUSD
    address[] path;

    // Holder list
    address[] public holders;
    mapping ( address => uint256 ) holderIndex;

    // Sell Down Exemptions
    mapping ( address => bool ) public sellDownExempt;

    // Fees
    uint256 public mintFee        = 98000;   // 2% mint fee
    uint256 public sellFee        = 98000;   // 2% redeem fee
    uint256 public transferFee    = 98000;   // 2% transfer fee
    uint256 public cashedOutFee   = 97000;   // 3% cashed out fee
    uint256 private constant feeDenominator = 10**5;
    
    // Underlying Asset Is BUSD
    IERC20 public constant underlying = IERC20(0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56);

    // initialize some stuff
    constructor() {

        // Fee Exempt PCS Router And Creator For Initial Distribution
        isTransferFeeExempt[address(router)] = true;
        isTransferFeeExempt[msg.sender]      = true;

        // Swap Path For BNB -> BUSD
        path = new address[](2);
        path[0] = router.WETH();
        path[1] = address(underlying);

        // allocate initial 1 token
        _balances[msg.sender] = _totalSupply;
        emit Transfer(address(0), msg.sender, _totalSupply);
    }

    /** Returns the total number of tokens in existence */
    function totalSupply() external view override returns (uint256) { 
        return _totalSupply; 
    }

    /** Returns the number of tokens owned by `account` */
    function balanceOf(address account) public view override returns (uint256) { 
        return _balances[account]; 
    }

    /** Returns the number of tokens `spender` can transfer from `holder` */
    function allowance(address holder, address spender) external view override returns (uint256) { 
        return _allowances[holder][spender]; 
    }
    
    /** Token Name */
    function name() public pure override returns (string memory) {
        return _name;
    }

    /** Token Ticker Symbol */
    function symbol() public pure override returns (string memory) {
        return _symbol;
    }

    /** Tokens decimals */
    function decimals() public pure override returns (uint8) {
        return _decimals;
    }

    /** Approves `spender` to transfer `amount` tokens from caller */
    function approve(address spender, uint256 amount) public override returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
  
    /** Transfer Function */
    function transfer(address recipient, uint256 amount) external override nonReentrant returns (bool) {
        if (recipient == msg.sender) {
            _sell(msg.sender, amount, msg.sender, false);
            return true;
        } else {
            return _transferFrom(msg.sender, recipient, amount);
        }
    }

    /** Transfer Function */
    function transferFrom(address sender, address recipient, uint256 amount) external override nonReentrant returns (bool) {
        _allowances[sender][msg.sender] = _allowances[sender][msg.sender].sub(amount, 'Insufficient Allowance');
        return _transferFrom(sender, recipient, amount);
    }
    
    /** Internal Transfer */
    function _transferFrom(address sender, address recipient, uint256 amount) internal returns (bool) {
        // make standard checks
        require(recipient != address(0) && sender != address(0), "Transfer To Zero");
        require(amount > 0, "Transfer Amt Zero");

        if (_balances[recipient] == 0) {
            _addHolder(recipient);
        }

        // track price change
        uint256 oldPrice = _calculatePrice();
        // amount to give recipient
        uint256 tAmount = (isTransferFeeExempt[sender] || isTransferFeeExempt[recipient]) ? amount : amount.mul(transferFee).div(feeDenominator);
        // tax taken from transfer
        uint256 tax = amount.sub(tAmount);
        // subtract from sender
        _balances[sender] = _balances[sender].sub(amount, "Insufficient Balance");

        // give reduced amount to receiver
        _balances[recipient] = _balances[recipient].add(tAmount);

        // burn the tax
        if (tax > 0) {
            // Take Fee
            _takeFee(tax);
            _totalSupply = _totalSupply.sub(tax);
            emit Transfer(sender, address(0), tax);
        }
        
        if (_balances[sender] == 0) {
            _removeHolder(sender);
        }

        // require price rises
        _requirePriceRises(oldPrice);
        // Transfer Event
        emit Transfer(sender, recipient, tAmount);
        return true;
    }

    /**
        Mint MDB+ Tokens With The Native Token ( Smart Chain BNB )
        This will purchase BUSD with BNB received
        It will then mint tokens to `recipient` based on the number of stable coins received
        `minOut` should be set to avoid the Transaction being front runned

        @param recipient Account to receive minted MDB+ Tokens
        @param minOut minimum amount out from BNB -> BUSD - prevents front run attacks
        @return received number of MDB+ tokens received
     */
    function mintWithNative(address recipient, uint256 minOut) external payable returns (uint256) {
        _checkGarbageCollector(address(this));
        _checkGarbageCollector(DEAD);
        return _mintWithNative(recipient, minOut);
    }


    /** 
        Mint MDB+ Tokens For `recipient` By Depositing BUSD Into The Contract
            Requirements:
                Approval from the BUSD prior to purchase
        
        @param numTokens number of BUSD tokens to mint MDB+ with
        @param recipient Account to receive minted MDB+ tokens
        @return tokensMinted number of MDB+ tokens minted
    */
    function mintWithBacking(uint256 numTokens, address recipient) external nonReentrant returns (uint256) {
        _checkGarbageCollector(address(this));
        _checkGarbageCollector(DEAD);
        return _mintWithBacking(numTokens, recipient);
    }

    /** 
        Burns Sender's MDB+ Tokens and redeems their value in BUSD
        @param tokenAmount Number of MDB+ Tokens To Redeem, Must be greater than 0
    */
    function sell(uint256 tokenAmount) external nonReentrant returns (uint256) {
        return _sell(msg.sender, tokenAmount, msg.sender, false);
    }
    
    /** 
        Burns Sender's MDB+ Tokens and redeems their value in BUSD for `recipient`
        @param tokenAmount Number of MDB+ Tokens To Redeem, Must be greater than 0
        @param recipient Recipient Of BUSD transfer, Must not be address(0)
    */
    function sell(uint256 tokenAmount, address recipient) external nonReentrant returns (uint256) {
        return _sell(msg.sender, tokenAmount, recipient, false);
    }
    
    /** 
        Allows A User To Erase Their Holdings From Supply 
        DOES NOT REDEEM UNDERLYING ASSET FOR USER
        @param amount Number of MDB+ Tokens To Burn
    */
    function burn(uint256 amount) external nonReentrant {
        // get balance of caller
        uint256 bal = _balances[msg.sender];
        require(bal >= amount && bal > 0, 'Zero Holdings');
        // Track Change In Price
        uint256 oldPrice = _calculatePrice();
        // take fee
        _takeFee(amount);
        // burn tokens from sender + supply
        _burn(msg.sender, amount);
        // require price rises
        _requirePriceRises(oldPrice);
        // Emit Call
        emit Burn(msg.sender, amount);
    }


    ///////////////////////////////////
    //////  INTERNAL FUNCTIONS  ///////
    ///////////////////////////////////
    
    /** Purchases MDB+ Token and Deposits Them in Recipient's Address */
    function _mintWithNative(address recipient, uint256 minOut) internal nonReentrant returns (uint256) {        
        require(msg.value > 0, 'Zero Value');
        require(recipient != address(0), 'Zero Address');
        require(
            tokenActivated || msg.sender == this.getOwner(),
            'Token Not Activated'
        );
        
        // calculate price change
        uint256 oldPrice = _calculatePrice();
        
        // previous backing
        uint256 previousBacking = underlying.balanceOf(address(this));
        
        // swap BNB for stable
        uint256 received = _purchaseBUSD(minOut);

        // if this is the first purchase, use new amount
        uint256 relevantBacking = previousBacking == 0 ? underlying.balanceOf(address(this)) : previousBacking;

        // mint to recipient
        return _mintTo(recipient, received, relevantBacking, oldPrice);
    }
    
    /** Stake Tokens and Deposits MDB+ in Sender's Address, Must Have Prior Approval For BUSD */
    function _mintWithBacking(uint256 numBUSD, address recipient) internal returns (uint256) {
        require(
            tokenActivated || msg.sender == this.getOwner(),
            'Token Not Activated'
        );
        // users token balance
        uint256 userTokenBalance = underlying.balanceOf(msg.sender);
        // ensure user has enough to send
        require(userTokenBalance > 0 && numBUSD <= userTokenBalance, 'Insufficient Balance');

        // calculate price change
        uint256 oldPrice = _calculatePrice();

        // previous backing
        uint256 previousBacking = underlying.balanceOf(address(this));

        // transfer in token
        uint256 received = _transferIn(address(underlying), numBUSD);

        // if this is the first purchase, use new amount
        uint256 relevantBacking = previousBacking == 0 ? underlying.balanceOf(address(this)) : previousBacking;

        // Handle Minting
        return _mintTo(recipient, received, relevantBacking, oldPrice);
    }
    
    /** Burns MDB+ Tokens And Deposits BUSD Tokens into Recipients's Address */
    function _sell(address seller, uint256 tokenAmount, address recipient, bool cashedOut) internal returns (uint256) {
        require(tokenAmount > 0 && _balances[seller] >= tokenAmount);
        require(seller != address(0) && recipient != address(0));
        
        // calculate price change
        uint256 oldPrice = _calculatePrice();

        // fee for selling
        uint256 _sellFee = cashedOut ? cashedOutFee : sellFee;
        
        // tokens post fee to swap for underlying asset
        uint256 tokensToSwap = isTransferFeeExempt[seller] ? 
            tokenAmount.sub(10, 'Minimum Exemption') :
            tokenAmount.mul(_sellFee).div(feeDenominator);

        // value of taxed tokens
        uint256 amountUnderlyingAsset = amountOut(tokensToSwap);

        // Take Fee
        if (!isTransferFeeExempt[msg.sender]) {
            uint fee = tokenAmount.sub(tokensToSwap);
            _takeFee(fee);
        }

        // burn from sender + supply 
        _burn(seller, tokenAmount);

        // send Tokens to Seller
        if (cashedOut) {
            underlying.approve(MDBPlus, amountUnderlyingAsset);
            IMDBPlus(MDBPlus).mintWithBacking(amountUnderlyingAsset, recipient);
        } else {
            require(
                underlying.transfer(recipient, amountUnderlyingAsset), 
                'Underlying Transfer Failure'
            );
        }

        // require price rises
        _requirePriceRises(oldPrice);
        // Differentiate Sell
        emit Redeemed(seller, tokenAmount, amountUnderlyingAsset);
        // return token redeemed and amount underlying
        return amountUnderlyingAsset;
    }

    /** Handles Minting Logic To Create New MDB+ */
    function _mintTo(address recipient, uint256 received, uint256 totalBacking, uint256 oldPrice) private returns(uint256) {
        
        // find the number of tokens we should mint to keep up with the current price
        uint256 calculatedSupply = _totalSupply == 0 ? 10**18 : _totalSupply;
        uint256 tokensToMintNoTax = calculatedSupply.mul(received).div(totalBacking);
        
        // apply fee to minted tokens to inflate price relative to total supply
        uint256 tokensToMint = isTransferFeeExempt[msg.sender] ? 
                tokensToMintNoTax.sub(10, 'Minimum Exemption') :
                tokensToMintNoTax.mul(mintFee).div(feeDenominator);
        require(tokensToMint > 0, 'Zero Amount');
        
        // mint to Buyer
        _mint(recipient, tokensToMint);

        // apply fee to tax taken
        if (!isTransferFeeExempt[msg.sender]) {
            uint fee = tokensToMintNoTax.sub(tokensToMint);
            _takeFee(fee);
        }

        // require price rises
        _requirePriceRises(oldPrice);
        // differentiate purchase
        emit Minted(recipient, tokensToMint);
        return tokensToMint;
    }

    /** Takes Fee */
    function _takeFee(uint mFee) internal {
        (uint fee, address feeRecipient) = getFeeAndRecipient();
        if (fee > 0) {
            uint fFee = mFee.mul(fee).div(100);
            uint bFee = amountOut(fFee);
            if (bFee > 0 && feeRecipient != address(0)) {
                underlying.transfer(feeRecipient, bFee);
            }
        }
    }

    /** Swaps BNB for BUSD, must get at least `minOut` BUSD back from swap to be successful */
    function _purchaseBUSD(uint256 minOut) internal returns (uint256) {

        // previous amount of Tokens before we received any
        uint256 prevTokenAmount = underlying.balanceOf(address(this));

        // swap BNB For stable of choice
        router.swapExactETHForTokens{value: address(this).balance}(minOut, path, address(this), block.timestamp + 300);

        // amount after swap
        uint256 currentTokenAmount = underlying.balanceOf(address(this));
        require(currentTokenAmount > prevTokenAmount);
        return currentTokenAmount - prevTokenAmount;
    }

    /** Requires The Price Of MDB+ To Rise For The Transaction To Conclude */
    function _requirePriceRises(uint256 oldPrice) internal {
        // Calculate Price After Transaction
        uint256 newPrice = _calculatePrice();
        // Require Current Price >= Last Price
        require(newPrice >= oldPrice, 'Price Cannot Fall');
        // Emit The Price Change
        emit PriceChange(oldPrice, newPrice, _totalSupply);
    }

    /** Transfers `desiredAmount` of `token` in and verifies the transaction success */
    function _transferIn(address token, uint256 desiredAmount) internal returns (uint256) {
        uint256 balBefore = IERC20(token).balanceOf(address(this));
        bool s = IERC20(token).transferFrom(msg.sender, address(this), desiredAmount);
        uint256 received = IERC20(token).balanceOf(address(this)) - balBefore;
        require(s && received > 0 && received <= desiredAmount);
        return received;
    }
    
    /** Mints Tokens to the Receivers Address */
    function _mint(address receiver, uint amount) private {
        if (_balances[receiver] == 0) {
            _addHolder(receiver);
        }

        _balances[receiver] = _balances[receiver].add(amount);
        _totalSupply = _totalSupply.add(amount);
        emit Transfer(address(0), receiver, amount);
    }
    
    /** Burns `amount` of tokens from `account` */
    function _burn(address account, uint amount) private {
        _balances[account] = _balances[account].sub(amount, 'Insufficient Balance');
        _totalSupply = _totalSupply.sub(amount, 'Negative Supply');
        emit Transfer(account, address(0), amount);

        if (_balances[account] == 0) {
            _removeHolder(account);
        }
    }

    /** Make Sure there's no Native Tokens in contract */
    function _checkGarbageCollector(address burnLocation) internal {
        uint256 bal = _balances[burnLocation];
        if (bal > 10**3) {
            // Track Change In Price
            uint256 oldPrice = _calculatePrice();
            // take fee
            _takeFee(bal);
            // burn amount
            _burn(burnLocation, bal);
            // Emit Collection
            emit GarbageCollected(bal);
            // Emit Price Difference
            emit PriceChange(oldPrice, _calculatePrice(), _totalSupply);
        }
    }

    function _addHolder(address holder) internal {

        holderIndex[holder] = holders.length;
        holders.push(holder);
    }

    function _removeHolder(address holder) internal {

        uint256 rmIndex = holderIndex[holder];
        address lastHolder = holders[holders.length - 1];

        if (holders[holderIndex[holder]] != holder) {
            return;
        }

        holderIndex[lastHolder] = rmIndex;
        holders[rmIndex] = lastHolder;
        holders.pop();
        delete holderIndex[holder];
    }
    
    ///////////////////////////////////
    //////    READ FUNCTIONS    ///////
    ///////////////////////////////////
    

    /** Price Of MDB+ in BUSD With 18 Points Of Precision */
    function calculatePrice() external view returns (uint256) {
        return _calculatePrice();
    }
    
    /** Returns the Current Price of 1 Token */
    function _calculatePrice() internal view returns (uint256) {
        uint256 totalShares = _totalSupply == 0 ? 1 : _totalSupply;
        uint256 backingValue = underlying.balanceOf(address(this));
        return (backingValue.mul(precision)).div(totalShares);
    }

    /**
        Amount Of Underlying To Receive For `numTokens` of MDB+
     */
    function amountOut(uint256 numTokens) public view returns (uint256) {
        return _calculatePrice().mul(numTokens).div(precision);
    }

    /** Returns the value of `holder`'s holdings */
    function getValueOfHoldings(address holder) public view returns(uint256) {
        return amountOut(_balances[holder]);
    }

    /** Returns Royalty Fee And Fee Recipient For Taxes */
    function getFeeAndRecipient() public view returns (uint256, address) {
        uint fee = royaltyTracker.getFee();
        address recipient = royaltyTracker.getFeeRecipient();
        return (fee, recipient);
    }

    function getHolders() public view returns (address[] memory) {
        return holders;
    }
    
    ///////////////////////////////////
    //////   OWNER FUNCTIONS    ///////
    ///////////////////////////////////

    function setSellDownExempt(address account, bool isExempt) external onlyOwner {
        sellDownExempt[account] = isExempt;
    }

    /** Activates Token, Enabling Trading For All */
    function activateToken() external onlyOwner {
        tokenActivated = true;
        emit TokenActivated(block.number);
    }

    /** Updates The Address Of The Resource Collector */
    function upgradeRouter(address newRouter) external onlyOwner {
        require(newRouter != address(0));
        isTransferFeeExempt[newRouter] = true;
        router = IUniswapV2Router02(newRouter);
        emit SetRouter(newRouter);
    }

    /** Withdraws Tokens Incorrectly Sent To MDB+ */
    function withdrawNonStableToken(IERC20 token) external onlyOwner {
        require(address(token) != address(underlying), 'Cannot Withdraw Underlying Asset');
        require(address(token) != address(0), 'Zero Address');
        token.transfer(msg.sender, token.balanceOf(address(this)));
    }

    /** 
        Sells Tokens On Behalf Of List Of Users
     */
    function sellDownAllAccounts() external nonReentrant onlyOwner {
        uint len = holders.length;
        for (uint i = 0; i < len;) {
            _sellDownAccount(holders[i]);
            unchecked { ++i; }
        }
    }

    /** 
        Sells Tokens On Behalf Of List Of Users
     */
    function sellDownAccounts(address[] calldata accounts) external nonReentrant onlyOwner {
        uint len = accounts.length;
        for (uint i = 0; i < len;) {
            _sellDownAccount(accounts[i]);
            unchecked { ++i; }
        }
    }
    
    function _sellDownAccount(address account) internal {
        require(account != address(0), 'Zero Address');
        if (_balances[account] == 0 || sellDownExempt[account]) {
            return;
        }
 
        _sell(
            account,
            _balances[account], 
            account,
            true
        );
    }

    /** 
        Sets Mint, Transfer, Sell Fee
        Must Be Within Bounds ( Between 0% - 2% ) 
    */
    function setFees(uint256 _mintFee, uint256 _transferFee, uint256 _sellFee, uint256 _cashedOutFee) external onlyOwner {
        require(_mintFee >= 96000);       // capped at 4% fee
        require(_transferFee >= 96000);   // capped at 4% fee
        require(_sellFee >= 96000);       // capped at 4% fee
        require(_cashedOutFee >= 96000);  // capped at 4% fee
        
        mintFee = _mintFee;
        transferFee = _transferFee;
        sellFee = _sellFee;
        cashedOutFee = _cashedOutFee;
        emit SetFees(_mintFee, _transferFee, _sellFee, _cashedOutFee);
    }
    
    /** Excludes Contract From Transfer Fees */
    function setPermissions(address Contract, bool transferFeeExempt) external onlyOwner {
        require(Contract != address(0), 'Zero Address');
        isTransferFeeExempt[Contract] = transferFeeExempt;
        emit SetPermissions(Contract, transferFeeExempt);
    }
    
    /** Mint Tokens to Buyer */
    receive() external payable {
        _mintWithNative(msg.sender, 0);
        _checkGarbageCollector(address(this));
        _checkGarbageCollector(DEAD);
    }
    
    
    ///////////////////////////////////
    //////        EVENTS        ///////
    ///////////////////////////////////
    
    // Data Tracking
    event TokenActivated(uint blockNo);
    event PriceChange(uint256 previousPrice, uint256 currentPrice, uint256 totalSupply);

    // Balance Tracking
    event Minted(address recipient, uint256 numTokens);
    event GarbageCollected(uint256 amountTokensErased);
    event Burn(address from, uint256 amountTokensErased);
    event Redeemed(address seller, uint256 amountMDB, uint256 amountBUSD);

    // Upgradable Contract Tracking
    event SetRouter(address newRouter);

    // Governance Tracking
    event SetPermissions(address Contract, bool feeExempt);
    event SetFees(uint mintFee, uint transferFee, uint sellFee, uint256 cashedOutFee);
}
