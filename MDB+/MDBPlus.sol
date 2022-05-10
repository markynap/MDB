//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./IERC20.sol";
import "./Ownable.sol";
import "./SafeMath.sol";
import "./IUniswapV2Router02.sol";
import "./ReentrantGuard.sol";

//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

interface IXUSD {
    function flashLoanProvider() external view returns (address);
    function xSwapRouter() external view returns (address);
    function resourceCollector() external view returns (address);
}

interface XUSDRoyalty {
    function getFee() external view returns (uint256);
    function getFeeRecipient() external view returns (address);
}

/**
 * Contract: MDB+ Powered by XUSD
 * Appreciating Stable Coin Inheriting The IP Of XUSD by xSurge
 * Visit MDB.fund and xsurge.net to learn more about appreciating stable coins
 */
contract MDBPlus is IERC20, Ownable, ReentrancyGuard {
    
    using SafeMath for uint256;
    using Address for address;

    // token data
    string private constant _name = "MDB+";
    string private constant _symbol = "MDB+";
    uint8 private constant _decimals = 18;
    uint256 private constant precision = 10**18;
    
    // 1 initial supply
    uint256 private _totalSupply = 10**18; 
    
    // balances
    mapping (address => uint256) _balances;
    mapping (address => mapping (address => uint256)) _allowances;

    // address -> Fee Exemption
    mapping ( address => bool ) public isTransferFeeExempt;

    // Token Activation
    mapping ( address => bool ) public canTransactPreLaunch;
    bool public tokenActivated;

    // Dead Wallet
    address private constant DEAD = 0x000000000000000000000000000000000000dEaD;

    // PCS Router
    IUniswapV2Router02 private router = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);

    // Royalty Data Fetcher
    XUSDRoyalty private immutable royaltyTracker;

    // Fees
    uint256 public mintFee        = 99250;            // 0.75% mint fee
    uint256 public sellFee        = 99750;            // 0.25% redeem fee 
    uint256 public transferFee    = 99750;            // 0.25% transfer fee
    uint256 private constant feeDenominator = 10**5;

    // Maximum Holdings
    uint256 public max_holdings = 50_000 * 10**18;
    uint256 public constant min_max_holdings = 20_000 * 10**18;
    
    // Underlying Asset Is BUSD
    IERC20 public constant underlying = IERC20(0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56);

    // initialize some stuff
    constructor(address royalty) {
        require(
            royalty != address(0),
            'Zero Address'
        );

        // init royalty system
        royaltyTracker = XUSDRoyalty(royalty);

        // Fee Exempt PCS Router And Creator For Initial Distribution
        isTransferFeeExempt[address(router)] = true;
        isTransferFeeExempt[msg.sender]      = true;

        // Allows Mint Access Pre Activation
        canTransactPreLaunch[msg.sender] = true;

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
    function transfer(address recipient, uint256 amount) external override returns (bool) {
        if (recipient == msg.sender) {
            require(_status != _ENTERED, "Reentrant call");
            _sell(msg.sender, amount, msg.sender);
            return true;
        } else {
            return _transferFrom(msg.sender, recipient, amount);
        }
    }

    /** Transfer Function */
    function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
        _allowances[sender][msg.sender] = _allowances[sender][msg.sender].sub(amount, 'Insufficient Allowance');
        return _transferFrom(sender, recipient, amount);
    }
    
    /** Internal Transfer */
    function _transferFrom(address sender, address recipient, uint256 amount) internal returns (bool) {
        // make standard checks
        require(recipient != address(0) && sender != address(0), "Transfer To Zero");
        require(amount > 0, "Transfer Amt Zero");
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
            // Take XUSD Fee
            _takeFee(tax);
            _totalSupply = _totalSupply.sub(tax);
            emit Transfer(sender, address(0), tax);
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
    function mintWithNative(address recipient, uint256 minOut) external override payable returns (uint256) {
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
    function mintWithBacking(uint256 numTokens, address recipient) external override nonReentrant returns (uint256) {
        _checkGarbageCollector(address(this));
        _checkGarbageCollector(DEAD);
        return _mintWithBacking(backingToken, numTokens, recipient);
    }

    /** 
        Burns Sender's MDB+ Tokens and redeems their value in BUSD
        @param tokenAmount Number of MDB+ Tokens To Redeem, Must be greater than 0
    */
    function sell(uint256 tokenAmount) external notEntered returns (uint256) {
        return _sell(msg.sender, tokenAmount, msg.sender);
    }
    
    /** 
        Burns Sender's MDB+ Tokens and redeems their value in BUSD for `recipient`
        @param tokenAmount Number of MDB+ Tokens To Redeem, Must be greater than 0
        @param recipient Recipient Of BUSD transfer, Must not be address(0)
    */
    function sell(uint256 tokenAmount, address recipient) external notEntered returns (uint256) {
        return _sell(msg.sender, tokenAmount, recipient);
    }

    /**
        Exchanges TokenIn For TokenOut 1:1 So Long As:
            - TokenIn  is an approved XUSD stable and not address(0) or tokenOut
            - TokenOut is an approved XUSD stable and not address(0) or tokenIn
            - TokenIn and TokenOut have the same decimal count
        
        The xSwap Router is the only contract with permission to this function
        It is up to the xSwap Router to charge a fee for this service that will
        benefit XUSD in some capacity, either through donation or to the Treasury

        @param tokenIn - Token To Give XUSD in exchange for TokenOut
        @param tokenOut - Token To receive from swap
        @param tokenInAmount - Amount of `tokenIn` to exchange for tokenOut
        @param recipient - Recipient of `tokenOut` tokens
     */
    function exchange(address tokenIn, address tokenOut, uint256 tokenInAmount, address recipient) external override notEntered {
        require(
            tokenIn != address(0) && 
            tokenOut != address(0) && 
            recipient != address(0) &&
            tokenIn != tokenOut &&
            tokenInAmount > 0,
            'Invalid Params'
        );
        // add XUSD Swap here
    }
    
    /** 
        Allows A User To Erase Their Holdings From Supply 
        DOES NOT REDEEM UNDERLYING ASSET FOR USER
        @param amount Number of XUSD Tokens To Burn
    */
    function burn(uint256 amount) external override notEntered {
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
    
    /** Purchases xUSD Token and Deposits Them in Recipient's Address */
    function _mintWithNative(address recipient, uint256 minOut) internal nonReentrant returns (uint256) {        
        require(msg.value > 0, 'Zero Value');
        require(recipient != address(0), 'Zero Address');
        require(
            tokenActivated || canTransactPreLaunch[msg.sender],
            'Token Not Activated'
        );
        
        // calculate price change
        uint256 oldPrice = _calculatePrice();
        
        // previous backing
        uint256 previousBacking = underlying.balanceOf(address(this));
        
        // swap BNB for stable
        uint256 received = _swapForStable(minOut);

        // if this is the first purchase, use new amount
        uint256 relevantBacking = previousBacking == 0 ? underlying.balanceOf(address(this)) : previousBacking;

        // mint to recipient
        return _mintTo(recipient, received, relevantBacking, oldPrice);
    }
    
    /** Stake Tokens and Deposits MDB+ in Sender's Address, Must Have Prior Approval For BUSD */
    function _mintWithBacking(uint256 numBUSD, address recipient) internal returns (uint256) {
        require(
            tokenActivated || canTransactPreLaunch[msg.sender],
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
    
    /** Sells xUSD Tokens And Deposits Underlying Asset Tokens into Recipients's Address */
    function _sell(address seller, uint256 tokenAmount, address recipient) internal nonReentrant returns (uint256) {
        require(tokenAmount > 0 && _balances[seller] >= tokenAmount);
        require(seller != address(0) && recipient != address(0));
        
        // calculate price change
        uint256 oldPrice = _calculatePrice();
        
        // tokens post fee to swap for underlying asset
        uint256 tokensToSwap = isTransferFeeExempt[seller] ? 
            tokenAmount.sub(10, 'Minimum Exemption') :
            tokenAmount.mul(sellFee).div(feeDenominator);

        // value of taxed tokens
        uint256 amountUnderlyingAsset = amountOut(tokensToSwap);

        // Take XUSD Fee
        if (!isTransferFeeExempt[msg.sender]) {
            uint fee = tokenAmount.sub(tokensToSwap);
            _takeFee(fee);
        }

        // burn from sender + supply 
        _burn(seller, tokenAmount);

        // send Tokens to Seller
        require(
            underlying.transfer(recipient, amountUnderlyingAsset), 
            'Underlying Transfer Failure'
        );

        // require price rises
        _requirePriceRises(oldPrice);
        // Differentiate Sell
        emit Redeemed(seller, tokenAmount, amountUnderlyingAsset);
        // return token redeemed and amount underlying
        return amountUnderlyingAsset;
    }

    /** Handles Minting Logic To Create New Surge Tokens*/
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
        // require maximum holdings is not met
        require(
            getValueOfHoldings(recipient) <= max_holdings,
            'Value Exceeds Maximum Holdings'
        );
        // differentiate purchase
        emit Minted(recipient, tokensToMint);
        return tokensToMint;
    }

    /** Takes Fee */
    function _takeFee(uint mFee) internal {
        (uint fee, address feeRecipient) = getFeeAndRecipient();
        uint fFee;
        if (fee > 0) {
            fFee = mFee.mul(fee).div(100);
            uint bFee = amountOut(fFee);
            if (bFee > 0 && feeRecipient != address(0)) {
                underlying.transfer(feeRecipient, bFee);
            }
        }
    }

    /** Swaps `amount` BNB for `stable` utilizing the token fetcher contract */
    function _swapForStable(uint256 minOut) internal returns (uint256) {

        // previous amount of Tokens before we received any
        uint256 prevTokenAmount = underlying.balanceOf(address(this));

        // swap BNB For stable of choice
        router.swapETHForExactTokens{value: address(this).balance}(minOut, path, address(this), block.timestamp + 300);

        // amount after swap
        uint256 currentTokenAmount = underlying.balanceOf(address(this));
        require(currentTokenAmount > prevTokenAmount);
        return currentTokenAmount - prevTokenAmount;
    }

    /** Requires The Price Of XUSD To Rise For The Transaction To Conclude */
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
        _balances[receiver] = _balances[receiver].add(amount);
        _totalSupply = _totalSupply.add(amount);
        emit Transfer(address(0), receiver, amount);
    }
    
    /** Burns `amount` of tokens from `account` */
    function _burn(address account, uint amount) private {
        _balances[account] = _balances[account].sub(amount, 'Insufficient Balance');
        _totalSupply = _totalSupply.sub(amount, 'Negative Supply');
        emit Transfer(account, address(0), amount);
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
    
    ///////////////////////////////////
    //////    READ FUNCTIONS    ///////
    ///////////////////////////////////
    

    /** Price Of XUSD in BUSD With 18 Points Of Precision */
    function calculatePrice() external view override returns (uint256) {
        return _calculatePrice();
    }
    
    /** Returns the Current Price of 1 Token */
    function _calculatePrice() internal view returns (uint256) {
        uint256 totalShares = _totalSupply == 0 ? 1 : _totalSupply;
        uint256 backingValue = underlying.balanceOf(address(this));
        return (backingValue.mul(precision)).div(totalShares);
    }

    /**
        Amount Of Underlying To Receive For `numTokens` of XUSD
     */
    function amountOut(uint256 numTokens) public view returns (uint256) {
        return _calculatePrice().mul(numTokens).div(precision);
    }

    /** Returns the value of `holder`'s holdings */
    function getValueOfHoldings(address holder) public view override returns(uint256) {
        return amountOut(_balances[holder]);
    }

    /** Returns Royalty Fee And Fee Recipient For Taxes */
    function getFeeAndRecipient() public view returns (uint256, address) {
        uint fee = royaltyTracker.getFee();
        address recipient = royaltyTracker.getFeeRecipient();
        return (fee, recipient);
    }
    
    ///////////////////////////////////
    //////   OWNER FUNCTIONS    ///////
    ///////////////////////////////////

    /** Activates Token, Enabling Trading For All */
    function activateToken() external onlyOwner {
        tokenActivated = true;
        emit TokenActivated(block.number);
    }
    
    /** Registers List Of Addresses To Transact Before Token Goes Live */
    function registerUserToBuyPreLaunch(address[] calldata users) external onlyOwner {
        for (uint i = 0; i < users.length; i++) {
            canTransactPreLaunch[users[i]] = true;
        }
    }

    /** Updates The Address Of The Flashloan Provider */
    function setMaxHoldings(uint256 maxHoldings) external onlyOwner {
        require(maxHoldings >= min_max_holdings, 'Minimum Reached');
        max_holdings = maxHoldings;
        emit SetMaxHoldings(maxHoldings);
    }

    /** Updates The Address Of The Resource Collector */
    function upgradeRouter(address newRouter) external onlyOwner {
        require(newRouter != address(0));
        isTransferFeeExempt[newRouter] = true;
        router = IUniswapV2Router02(newRouter);
        emit SetRouter(newRouter);
    }

    /** Withdraws Tokens Incorrectly Sent To XUSD */
    function withdrawNonStableToken(IERC20 token) external onlyOwner {
        require(address(token) != address(underlying), 'Cannot Withdraw Underlying Asset');
        require(address(token) != address(0), 'Zero Address');
        token.transfer(msg.sender, token.balanceOf(address(this)));
    }

    /** 
        Situation Where Tokens Are Un-Recoverable
            Example Situations: 
                Lost Wallet Keys
                Broken Contract Without Withdraw Fuctionality
                Exchange Hot Wallet Without XUSD Support
        Will Redeem Stables Tax Free On Behalf of Wallet
        Will Prevent Incorrectly 'Burnt' or Locked Up Tokens From Continuously Appreciating
     */
    function redeemForLostAccount(address account, uint256 amount) external onlyOwner {
        require(account != address(0));
        require(_balances[account] > 0 && _balances[account] >= amount);
        require(
            getValueOfHoldings(account) >= max_holdings,
            'User Does Not Exceed Max Holdings'
        );

        // amount to sell to bring to max holdings
        uint256 amtToSellBUSD = getValueOfHoldings(account).sub(max_holdings);

        // convert to MDB+
        uint256 mdbPlusToSell = amtToSellBUSD.mul(precision).div(_calculatePrice());

        // sell tokens tax free on behalf of frozen wallet
        _sell(
            account,
            mdbPlusToSell, 
            account
        );
    }

    /** 
        Sets Mint, Transfer, Sell Fee
        Must Be Within Bounds ( Between 0% - 2% ) 
    */
    function setFees(uint256 _mintFee, uint256 _transferFee, uint256 _sellFee) external onlyOwner {
        require(_mintFee >= 97000);      // capped at 3% fee
        require(_transferFee >= 97000);  // capped at 3% fee
        require(_sellFee >= 97000);      // capped at 3% fee
        
        mintFee = _mintFee;
        transferFee = _transferFee;
        sellFee = _sellFee;
        emit SetFees(_mintFee, _transferFee, _sellFee);
    }
    
    /** Excludes Contract From Transfer Fees */
    function setPermissions(address Contract, bool transferFeeExempt) external onlyOwner {
        require(Contract != address(0) && Contract != PROMISE_USD);
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
    event PriceChange(uint256 previousPrice, uint256 currentPrice, uint256 totalSupply);
    event TokenActivated(uint blockNo);

    // Balance Tracking
    event Burn(address from, uint256 amountTokensErased);
    event GarbageCollected(uint256 amountTokensErased);
    event Redeemed(address seller, uint256 amountxUSD, uint256 assetsRedeemed);
    event Minted(address recipient, uint256 numTokens);

    // Upgradable Contract Tracking
    event SetMaxHoldings(uint256 maxHoldings);
    event SetRouter(address newRouter);

    // Governance Tracking
    event TransferOwnership(address newOwner);
    event SetPermissions(address Contract, bool feeExempt);
    event SetFees(uint mintFee, uint transferFee, uint sellFee);
}
