pragma solidity >=0.6.8;
pragma experimental ABIEncoderV2;

import "./bep/Utils.sol";

import "@openzeppelin/contracts-ethereum-package/contracts/access/Ownable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/utils/EnumerableSet.sol";

contract PepeToken is
    IBEP20UpgradeSafe,
    OwnableUpgradeSafe,
    ReentrancyGuardUpgradeSafe
{
    using SafeMath for uint256;
    using Address for address;
    using EnumerableSet for EnumerableSet.AddressSet;

    mapping(address => uint256) private _rOwned;
    mapping(address => uint256) private _tOwned;
    mapping(address => mapping(address => uint256)) private _allowances;

    mapping(address => bool) private _isExcludedFromFee;

    mapping(address => bool) private _isExcluded;

    // address[] private _excluded;
    // Declare a set state variable
    EnumerableSet.AddressSet private _excluded;

    uint256 private constant MAX = ~uint256(0);
    uint8 private constant DECIMALS = 9;

    uint256 private _tTotal;
    uint256 private _rTotal;
    uint256 private _tFeeTotal;

    string private _name;
    string private _symbol;

    IPancakeRouter02 public pancakeRouter;
    address public pancakePair;

    bool inSwapAndLiquify;

    uint256 public rewardCycleBlock;
    uint256 public threshHoldTopUpRate; // 2 percent
    uint256 public _maxTxAmount; // should be 0.01% percent per transaction, will be set again at activateContract() function
    uint256 public disruptiveCoverageFee; // antiwhale
    mapping(address => uint256) public nextAvailableClaimDate;
    bool public swapAndLiquifyEnabled; // should be true
    uint256 public disruptiveTransferEnabledFrom;
    uint256 public disableEasyRewardFrom;
    uint256 public winningDoubleRewardPercentage;

    uint256 public _taxFee;
    uint256 private _previousTaxFee;

    uint256 public _liquidityFee; // 4% will be added pool, 4% will be converted to BNB
    uint256 private _previousLiquidityFee;
    uint256 public rewardThreshold;

    uint256 minTokenNumberToSell; // 0.01% max tx amount will trigger swap and add liquidity

    uint256 private _limitHoldPercentage; // Default is 0.5% mean 50 / 10000
    mapping(address => bool) public _blockAddress;

    address public _ethAddress;
    address public _btcAddress;

    event SwapAndLiquifyEnabledUpdated(bool enabled);
    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiquidity
    );

    event ClaimBNBSuccessfully(
        address recipient,
        uint256 ethReceived,
        uint256 nextAvailableClaimDate
    );

    event SetLiquidityFeePercent(uint256 liquidityFee);
    event SetTaxFeePercent(uint256 taxFee);
    event ExcludedFromFee(address excludedFromFeeAddress);
    event IncludedInFee(address includedInFeeAddress);
    event SetExcludeFromMaxTx(address excludedFromMaxTxAddress);
    event SetMaxTxPercent(uint256 maxTxAmount);
    event SetLimitHoldPercentage(uint256 limitHoldPercent);
    event SetBTCAddress(address btcAddress);
    event SetETHAddress(address ethAddress);

    modifier lockTheSwap {
        inSwapAndLiquify = true;
        _;
        inSwapAndLiquify = false;
    }

    function initialize(address payable routerAddress) public initializer {
        IBEP20UpgradeSafe.__ERC20_init("PEPE Community", "PEPE");
        IBEP20UpgradeSafe._setupDecimals(uint8(DECIMALS));
        OwnableUpgradeSafe.__Ownable_init();

        _tTotal = 1000000000 * 10**6 * 10**9;
        _rTotal = (MAX - (MAX % _tTotal));

        rewardCycleBlock = 7 days;
        threshHoldTopUpRate = 2; // 2 percent
        _maxTxAmount = _tTotal; // should be 0.01% percent per transaction, will be set again at activateContract() function
        disruptiveCoverageFee = 2 ether; // antiwhale

        swapAndLiquifyEnabled = false; // should be true
        disruptiveTransferEnabledFrom = 0;

        winningDoubleRewardPercentage = 1;

        _taxFee = 2;
        _previousTaxFee = _taxFee;

        _liquidityFee = 8; // 4% will be added pool, 4% will be converted to BNB
        _previousLiquidityFee = _liquidityFee;
        rewardThreshold = 1 ether;

        minTokenNumberToSell = _tTotal.mul(1).div(10000); // 0.01% max tx amount will trigger swap and add liquidity

        _limitHoldPercentage = 50; // Default is 0.5% mean 50 / 10000

        _rOwned[_msgSender()] = _rTotal;

        IPancakeRouter02 _pancakeRouter = IPancakeRouter02(routerAddress);
        // Create a pancake pair for this new token
        pancakePair = IPancakeFactory(_pancakeRouter.factory()).createPair(
            address(this),
            _pancakeRouter.WETH()
        );

        // set the rest of the contract variables
        pancakeRouter = _pancakeRouter;

        //exclude owner and this contract from fee
        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[address(this)] = true;

        emit Transfer(address(0), _msgSender(), _tTotal);
    }

    function totalSupply() public view override returns (uint256) {
        return _tTotal;
    }

    function balanceOf(address account) public view override returns (uint256) {
        if (_isExcluded[account]) return _tOwned[account];
        return tokenFromReflection(_rOwned[account]);
    }

    function transfer(address recipient, uint256 amount)
        public
        override
        returns (bool)
    {
        _transfer(_msgSender(), recipient, amount, 0);
        return true;
    }

    function allowance(address owner, address spender)
        public
        view
        override
        returns (uint256)
    {
        return _allowances[owner][spender];
    }

    function ETHAddress() public view returns (address) {
        return _ethAddress;
    }

    function BTCAddress() public view returns (address) {
        return _btcAddress;
    }

    function approve(address spender, uint256 amount)
        public
        override
        returns (bool)
    {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        _transfer(sender, recipient, amount, 0);
        _approve(
            sender,
            _msgSender(),
            _allowances[sender][_msgSender()].sub(
                amount,
                "BEP20: transfer amount exceeds allowance"
            )
        );
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue)
        public
        virtual
        override
        returns (bool)
    {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender].add(addedValue)
        );
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue)
        public
        virtual
        override
        returns (bool)
    {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender].sub(
                subtractedValue,
                "BEP20: decreased allowance below zero"
            )
        );
        return true;
    }

    function isExcludedFromReward(address account) public view returns (bool) {
        return _isExcluded[account];
    }

    function totalFees() public view returns (uint256) {
        return _tFeeTotal;
    }

    function deliver(uint256 tAmount) public {
        address sender = _msgSender();
        require(
            !_isExcluded[sender],
            "Excluded addresses cannot call this function"
        );
        (uint256 rAmount, , , , , ) = _getValues(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rTotal = _rTotal.sub(rAmount);
        _tFeeTotal = _tFeeTotal.add(tAmount);
    }

    function reflectionFromToken(uint256 tAmount, bool deductTransferFee)
        public
        view
        returns (uint256)
    {
        require(tAmount <= _tTotal, "Amount must be less than supply");
        if (!deductTransferFee) {
            (uint256 rAmount, , , , , ) = _getValues(tAmount);
            return rAmount;
        } else {
            (, uint256 rTransferAmount, , , , ) = _getValues(tAmount);
            return rTransferAmount;
        }
    }

    function tokenFromReflection(uint256 rAmount)
        public
        view
        returns (uint256)
    {
        require(
            rAmount <= _rTotal,
            "Amount must be less than total reflections"
        );
        uint256 currentRate = _getRate();
        return rAmount.div(currentRate);
    }

    function excludeFromReward(address account) public onlyOwner() {
        require(!_isExcluded[account], "Account is already excluded");
        if (_rOwned[account] > 0) {
            _tOwned[account] = tokenFromReflection(_rOwned[account]);
        }
        _isExcluded[account] = true;
        EnumerableSet.add(_excluded, account);
        // _excluded.push(account);
    }

    function includeInReward(address account) external onlyOwner() {
        require(_isExcluded[account], "Account is not excluded");
        if (EnumerableSet.contains(_excluded, account)) {
            _tOwned[account] = 0;
            _isExcluded[account] = false;
            EnumerableSet.remove(_excluded, account);
        }
    }

    function _transferBothExcluded(
        address sender,
        address recipient,
        uint256 tAmount
    ) private {
        (
            uint256 rAmount,
            uint256 rTransferAmount,
            uint256 rFee,
            uint256 tTransferAmount,
            uint256 tFee,
            uint256 tLiquidity
        ) = _getValues(tAmount);
        _tOwned[sender] = _tOwned[sender].sub(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _tOwned[recipient] = _tOwned[recipient].add(tTransferAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
        _takeLiquidity(tLiquidity);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function excludeFromFee(address account) public onlyOwner {
        _isExcludedFromFee[account] = true;
        emit ExcludedFromFee(account);
    }

    function includeInFee(address account) public onlyOwner {
        _isExcludedFromFee[account] = false;
        emit IncludedInFee(account);
    }

    function setTaxFeePercent(uint256 taxFee) external onlyOwner() {
        require(taxFee >= 0, "Tax fee must be greater than 0%");
        require(taxFee <= 15, "Tax fee must be lower than 15%");
        _taxFee = taxFee;
        emit SetTaxFeePercent(taxFee);
    }

    function setLiquidityFeePercent(uint256 liquidityFee) external onlyOwner() {
        require(liquidityFee >= 0, "Liquidity fee must be greater than 0%");
        require(liquidityFee <= 10, "Liquidity fee must be lower than 10%");
        _liquidityFee = liquidityFee;
        emit SetLiquidityFeePercent(liquidityFee);
    }

    function setSwapAndLiquifyEnabled(bool _enabled) public onlyOwner {
        swapAndLiquifyEnabled = _enabled;
        emit SwapAndLiquifyEnabledUpdated(_enabled);
    }

    function setBTCAddress(address btcAddress) public onlyOwner {
        _btcAddress = btcAddress;
        emit SetBTCAddress(btcAddress);
    }

    function setEthAddress(address ethAddress) public onlyOwner {
        _ethAddress = ethAddress;
        emit SetETHAddress(ethAddress);
    }

    //to receive BNB from pancakeRouter when swapping
    receive() external payable {}

    function _reflectFee(uint256 rFee, uint256 tFee) private {
        _rTotal = _rTotal.sub(rFee);
        _tFeeTotal = _tFeeTotal.add(tFee);
    }

    function _getValues(uint256 tAmount)
        private
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        (uint256 tTransferAmount, uint256 tFee, uint256 tLiquidity) =
            _getTValues(tAmount);
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee) =
            _getRValues(tAmount, tFee, tLiquidity, _getRate());
        return (
            rAmount,
            rTransferAmount,
            rFee,
            tTransferAmount,
            tFee,
            tLiquidity
        );
    }

    function _getTValues(uint256 tAmount)
        private
        view
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        uint256 tFee = calculateTaxFee(tAmount);
        uint256 tLiquidity = calculateLiquidityFee(tAmount);
        uint256 tTransferAmount = tAmount.sub(tFee).sub(tLiquidity);
        return (tTransferAmount, tFee, tLiquidity);
    }

    function _getRValues(
        uint256 tAmount,
        uint256 tFee,
        uint256 tLiquidity,
        uint256 currentRate
    )
        private
        pure
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        uint256 rAmount = tAmount.mul(currentRate);
        uint256 rFee = tFee.mul(currentRate);
        uint256 rLiquidity = tLiquidity.mul(currentRate);
        uint256 rTransferAmount = rAmount.sub(rFee).sub(rLiquidity);
        return (rAmount, rTransferAmount, rFee);
    }

    function _getRate() private view returns (uint256) {
        (uint256 rSupply, uint256 tSupply) = _getCurrentSupply();
        return rSupply.div(tSupply);
    }

    function _getCurrentSupply() private view returns (uint256, uint256) {
        uint256 rSupply = _rTotal;
        uint256 tSupply = _tTotal;
        for (uint256 i = 0; i < EnumerableSet.length(_excluded); i++) {
            if (
                _rOwned[EnumerableSet.at(_excluded, i)] > rSupply ||
                _tOwned[EnumerableSet.at(_excluded, i)] > tSupply
            ) return (_rTotal, _tTotal);
            rSupply = rSupply.sub(_rOwned[EnumerableSet.at(_excluded, i)]);
            tSupply = tSupply.sub(_tOwned[EnumerableSet.at(_excluded, i)]);
        }
        if (rSupply < _rTotal.div(_tTotal)) return (_rTotal, _tTotal);
        return (rSupply, tSupply);
    }

    function _takeLiquidity(uint256 tLiquidity) private {
        uint256 currentRate = _getRate();
        uint256 rLiquidity = tLiquidity.mul(currentRate);
        _rOwned[address(this)] = _rOwned[address(this)].add(rLiquidity);
        if (_isExcluded[address(this)])
            _tOwned[address(this)] = _tOwned[address(this)].add(tLiquidity);
    }

    function calculateTaxFee(uint256 _amount) private view returns (uint256) {
        return _amount.mul(_taxFee).div(10**2);
    }

    function calculateLiquidityFee(uint256 _amount)
        private
        view
        returns (uint256)
    {
        return _amount.mul(_liquidityFee).div(10**2);
    }

    function removeAllFee() private {
        if (_taxFee == 0 && _liquidityFee == 0) return;

        _previousTaxFee = _taxFee;
        _previousLiquidityFee = _liquidityFee;

        _taxFee = 0;
        _liquidityFee = 0;
    }

    function restoreAllFee() private {
        _taxFee = _previousTaxFee;
        _liquidityFee = _previousLiquidityFee;
    }

    function isExcludedFromFee(address account) public view returns (bool) {
        return _isExcludedFromFee[account];
    }

    function _transfer(
        address from,
        address to,
        uint256 amount,
        uint256 value
    ) private {
        require(from != address(0), "BEP20: transfer from the zero address");
        require(to != address(0), "BEP20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");

        ensureMaxTxAmount(from, to, amount, value);
        ensureMaxHoldPercentage(from, to, amount);
        ensureIsNotBlockedAddress(from);
        ensureIsNotBlockedAddress(to);

        // swap and liquify
        swapAndLiquify(from, to);

        //indicates if fee should be deducted from transfer
        bool takeFee = true;

        //if any account belongs to _isExcludedFromFee account then remove the fee
        if (_isExcludedFromFee[from] || _isExcludedFromFee[to]) {
            takeFee = false;
        }

        //transfer amount, it will take tax, burn, liquidity fee
        _tokenTransfer(from, to, amount, takeFee);
    }

    //this method is responsible for taking all fee, if takeFee is true
    function _tokenTransfer(
        address sender,
        address recipient,
        uint256 amount,
        bool takeFee
    ) private {
        if (!takeFee) removeAllFee();

        // top up claim cycle
        topUpClaimCycleAfterTransfer(recipient, amount);

        if (_isExcluded[sender] && !_isExcluded[recipient]) {
            _transferFromExcluded(sender, recipient, amount);
        } else if (!_isExcluded[sender] && _isExcluded[recipient]) {
            _transferToExcluded(sender, recipient, amount);
        } else if (_isExcluded[sender] && _isExcluded[recipient]) {
            _transferBothExcluded(sender, recipient, amount);
        } else {
            _transferStandard(sender, recipient, amount);
        }

        if (!takeFee) restoreAllFee();
    }

    function _transferStandard(
        address sender,
        address recipient,
        uint256 tAmount
    ) private {
        (
            uint256 rAmount,
            uint256 rTransferAmount,
            uint256 rFee,
            uint256 tTransferAmount,
            uint256 tFee,
            uint256 tLiquidity
        ) = _getValues(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
        _takeLiquidity(tLiquidity);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _transferToExcluded(
        address sender,
        address recipient,
        uint256 tAmount
    ) private {
        (
            uint256 rAmount,
            uint256 rTransferAmount,
            uint256 rFee,
            uint256 tTransferAmount,
            uint256 tFee,
            uint256 tLiquidity
        ) = _getValues(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _tOwned[recipient] = _tOwned[recipient].add(tTransferAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
        _takeLiquidity(tLiquidity);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function _transferFromExcluded(
        address sender,
        address recipient,
        uint256 tAmount
    ) private {
        (
            uint256 rAmount,
            uint256 rTransferAmount,
            uint256 rFee,
            uint256 tTransferAmount,
            uint256 tFee,
            uint256 tLiquidity
        ) = _getValues(tAmount);
        _tOwned[sender] = _tOwned[sender].sub(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
        _takeLiquidity(tLiquidity);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    function blockAddress(address account) public onlyOwner() {
        _blockAddress[account] = true;
    }

    function isBlockedAddress(address account) public view returns (bool) {
        return _blockAddress[account];
    }

    function setMaxTxPercent(uint256 maxTxPercent) public onlyOwner() {
        require(maxTxPercent > 0, "Max Tx Percent must be greater than 1%");
        require(maxTxPercent < 500, "Max Tx Percent must be lower than 10%");
        _maxTxAmount = _tTotal.mul(maxTxPercent).div(10**4);
        emit SetMaxTxPercent(_maxTxAmount);
    }

    function limitHoldPercentage() public view returns (uint256) {
        return _limitHoldPercentage;
    }

    function setLimitHoldPercentage(uint256 limitHoldPercent)
        public
        onlyOwner()
    {
        require(limitHoldPercent > 0, "Max Tx Percent must be greater than 0%");
        require(
            limitHoldPercent < 1000,
            "Max Tx Percent must be lower than 10%"
        );
        _limitHoldPercentage = limitHoldPercent;
        emit SetLimitHoldPercentage(limitHoldPercent);
    }

    function getHoldPercentage(address ofAddress)
        public
        view
        returns (uint256)
    {
        return balanceOf(ofAddress).mul(10000).div(_tTotal);
    }


    function withdrawErc20(address tokenAddress) public onlyOwner {
        ERC20UpgradeSafe _tokenInstance = ERC20UpgradeSafe(tokenAddress);
        _tokenInstance.transfer(msg.sender, _tokenInstance.balanceOf(address(this)));
    }

    function calculateBNBReward(address ofAddress)
        public
        view
        returns (uint256)
    {
        uint256 totalSupply =
            uint256(_tTotal).sub(balanceOf(address(0))).sub(
                balanceOf(0x000000000000000000000000000000000000dEaD)
            );

        return
            Utils.calculateBNBReward(
                _tTotal,
                balanceOf(address(ofAddress)),
                address(this).balance,
                winningDoubleRewardPercentage,
                totalSupply,
                ofAddress
            );
    }

    function calculateETHReward(address ofAddress)
        public
        view
        returns (uint256)
    {
        uint256 _totalSupply =
            uint256(_tTotal).sub(balanceOf(address(0))).sub(
                balanceOf(0x000000000000000000000000000000000000dEaD)
            );

        return
            Utils.calculateETHReward(
                _tTotal,
                balanceOf(address(ofAddress)),
                address(this).balance,
                winningDoubleRewardPercentage,
                _totalSupply,
                ofAddress,
                address(pancakeRouter),
                _ethAddress
            );
    }

    function calculateBTCReward(address ofAddress)
        public
        view
        returns (uint256)
    {
        uint256 _totalSupply =
            uint256(_tTotal).sub(balanceOf(address(0))).sub(
                balanceOf(0x000000000000000000000000000000000000dEaD)
            );

        return
            Utils.calculateETHReward(
                _tTotal,
                balanceOf(address(ofAddress)),
                address(this).balance,
                winningDoubleRewardPercentage,
                _totalSupply,
                ofAddress,
                address(pancakeRouter),
                _btcAddress
            );
    }

    function getRewardCycleBlock() public view returns (uint256) {
        return rewardCycleBlock;
    }

    function claimBNBReward() public nonReentrant {
        require(
            nextAvailableClaimDate[msg.sender] <= block.timestamp,
            "Error: next available not reached"
        );
        require(
            balanceOf(msg.sender) > 0,
            "Error: must own PEPE to claim reward"
        );

        uint256 reward = calculateBNBReward(msg.sender);

        // reward threshold
        if (reward >= rewardThreshold) {
            Utils.swapETHForTokens(
                address(pancakeRouter),
                address(0x000000000000000000000000000000000000dEaD),
                reward.div(3)
            );
            reward = reward.sub(reward.div(3));
        }

        // update rewardCycleBlock
        nextAvailableClaimDate[msg.sender] =
            block.timestamp +
            getRewardCycleBlock();
        emit ClaimBNBSuccessfully(
            msg.sender,
            reward,
            nextAvailableClaimDate[msg.sender]
        );

        // fixed reentrancy bug
        (bool sent, ) = address(msg.sender).call{value: reward}("");
        require(sent, "Error: Cannot withdraw reward");
    }

    function claimETHReward() public {
        require(
            nextAvailableClaimDate[msg.sender] <= block.timestamp,
            "Error: next available not reached"
        );
        require(
            balanceOf(msg.sender) > 0,
            "Error: must own PEPE to claim reward"
        );

        uint256 reward = calculateBNBReward(msg.sender);
        _approve(msg.sender, address(pancakeRouter), reward);
        // reward threshold
        if (reward >= rewardThreshold) {
            Utils.swapETHForTokens(
                address(pancakeRouter),
                address(0x000000000000000000000000000000000000dEaD),
                reward.div(3)
            );
            reward = reward.sub(reward.div(3));
        }

        // update rewardCycleBlock
        nextAvailableClaimDate[msg.sender] =
            block.timestamp +
            getRewardCycleBlock();
        emit ClaimBNBSuccessfully(
            msg.sender,
            reward,
            nextAvailableClaimDate[msg.sender]
        );
        Utils.swapBNBForWETH(
            address(pancakeRouter),
            _ethAddress,
            address(msg.sender),
            reward
        );
    }

    function claimBTCReward() public {
        require(
            nextAvailableClaimDate[msg.sender] <= block.timestamp,
            "Error: next available not reached"
        );
        require(
            balanceOf(msg.sender) > 0,
            "Error: must own PEPE to claim reward"
        );

        uint256 reward = calculateBNBReward(msg.sender);
        _approve(msg.sender, address(pancakeRouter), reward);
        // reward threshold
        if (reward >= rewardThreshold) {
            Utils.swapETHForTokens(
                address(pancakeRouter),
                address(0x000000000000000000000000000000000000dEaD),
                reward.div(3)
            );
            reward = reward.sub(reward.div(3)); // 33% 
        }

        // update rewardCycleBlock
        nextAvailableClaimDate[msg.sender] =
            block.timestamp +
            getRewardCycleBlock();
        emit ClaimBNBSuccessfully(
            msg.sender,
            reward,
            nextAvailableClaimDate[msg.sender]
        );
        Utils.swapBNBForBTC(
            address(pancakeRouter),
            _btcAddress,
            address(msg.sender),
            reward
        );
    }

    function topUpClaimCycleAfterTransfer(address recipient, uint256 amount)
        private
    {
        uint256 currentRecipientBalance = balanceOf(recipient);
        uint256 basedRewardCycleBlock = getRewardCycleBlock();

        nextAvailableClaimDate[recipient] =
            nextAvailableClaimDate[recipient] +
            Utils.calculateTopUpClaim(
                currentRecipientBalance,
                basedRewardCycleBlock,
                threshHoldTopUpRate,
                amount
            );
    }

    function ensureMaxTxAmount(
        address from,
        address to,
        uint256 amount,
        uint256 value
    ) private {
        if (
            from != owner() &&
            to != owner() &&
            to != address(0) &&
            to != address(0x000000000000000000000000000000000000dEaD)
        ) {
            if (
                value < disruptiveCoverageFee &&
                block.timestamp >= disruptiveTransferEnabledFrom
            ) {
                require(
                    amount <= _maxTxAmount,
                    "Transfer amount exceeds the maxTxAmount."
                );
            }
        }
    }

    function ensureMaxHoldPercentage(
        address from,
        address to,
        uint256 amount
    ) private {
        if (
            from != owner() &&
            to != owner() &&
            to != address(0) &&
            to != address(0x000000000000000000000000000000000000dEaD)
        ) {
            require(
                getHoldPercentage(to).add(amount.mul(10000).div(_tTotal)) <=
                    _limitHoldPercentage,
                "Holder can not hold more than limit hold percentage"
            );
        }
    }

    function ensureIsNotBlockedAddress(address account) private {
        require(!_blockAddress[account], "Address is blocked");
    }

    function disruptiveTransfer(address recipient, uint256 amount)
        public
        payable
        returns (bool)
    {
        _transfer(_msgSender(), recipient, amount, msg.value);
        return true;
    }

    function swapAndLiquify(address from, address to) private {
        // is the token balance of this contract address over the min number of
        // tokens that we need to initiate a swap + liquidity lock?
        // also, don't get caught in a circular liquidity event.
        // also, don't swap & liquify if sender is pancake pair.
        uint256 contractTokenBalance = balanceOf(address(this));

        if (contractTokenBalance >= _maxTxAmount) {
            contractTokenBalance = _maxTxAmount;
        }

        bool shouldSell = contractTokenBalance >= minTokenNumberToSell;

        if (
            !inSwapAndLiquify &&
            shouldSell &&
            from != pancakePair &&
            swapAndLiquifyEnabled &&
            !(from == address(this) && to == address(pancakePair)) // swap 1 time
        ) {
            // only sell for minTokenNumberToSell, decouple from _maxTxAmount
            contractTokenBalance = minTokenNumberToSell;

            // add liquidity
            // split the contract balance into 3 pieces
            uint256 pooledBNB = contractTokenBalance.div(2);
            uint256 piece = contractTokenBalance.sub(pooledBNB).div(2);
            uint256 otherPiece = contractTokenBalance.sub(piece);

            uint256 tokenAmountToBeSwapped = pooledBNB.add(piece);

            uint256 initialBalance = address(this).balance;

            // now is to lock into staking pool
            Utils.swapTokensForEth(
                address(pancakeRouter),
                tokenAmountToBeSwapped
            );

            // how much BNB did we just swap into?

            // capture the contract's current BNB balance.
            // this is so that we can capture exactly the amount of BNB that the
            // swap creates, and not make the liquidity event include any BNB that
            // has been manually sent to the contract
            uint256 deltaBalance = address(this).balance.sub(initialBalance);

            uint256 bnbToBeAddedToLiquidity = deltaBalance.div(3);

            // add liquidity to pancake
            Utils.addLiquidity(
                address(pancakeRouter),
                owner(),
                otherPiece,
                bnbToBeAddedToLiquidity
            );

            emit SwapAndLiquify(piece, deltaBalance, otherPiece);
        }
    }

    function activateContract() public onlyOwner {
        // reward claim
        rewardCycleBlock = 7 days;

        // protocol
        disruptiveTransferEnabledFrom = block.timestamp;
        setMaxTxPercent(5); // 0.05% per transaction
        setSwapAndLiquifyEnabled(true);

        // approve contract
        _approve(address(this), address(pancakeRouter), 2**256 - 1);
    }

    function activateTestnet() public onlyOwner {
        // reward claim
        rewardCycleBlock = 5 minutes;

        // protocol
        disruptiveTransferEnabledFrom = block.timestamp;
        setMaxTxPercent(5); // 0.05% per transaction
        setSwapAndLiquifyEnabled(true);

        // approve contract
        _approve(address(this), address(pancakeRouter), 2**256 - 1);
    }
}
