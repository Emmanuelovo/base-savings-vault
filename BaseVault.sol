// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// ============================================================
//  BaseVault.sol - ETH + USDC Savings Vault
//  NETWORK: Base Mainnet (chainId 8453)
//
//  Assets saved:
//  - ETH  (Base native token - no approve needed)
//  - USDC (approve ONCE with max amount - deposit forever)
//
//  How USDC approve once works:
//  - First time only: approve max uint256 on USDC contract
//  - After that: deposit USDC as many times as you want
//  - Never need to approve again
//
//  USDC on Base Mainnet:
//  0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913
// ============================================================

interface IERC20 {
    function transfer(address to, uint256 amount)
        external returns (bool);
    function transferFrom(address from, address to, uint256 amount)
        external returns (bool);
    function balanceOf(address account)
        external view returns (uint256);
    function allowance(address owner, address spender)
        external view returns (uint256);
}

contract BaseVault {

    // â”€â”€ USDC CONTRACT â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    // Official Circle USDC on Base Mainnet
    // Hardcoded - cannot be changed after deployment
    // Verify at: basescan.org/token/0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913
    address public constant USDC_ADDRESS =
        0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    IERC20 public constant USDC = IERC20(USDC_ADDRESS);

    // Max uint256 - used for unlimited approve
    // This number means "approve everything forever"
    // You approve this once and never approve again
    uint256 public constant MAX_APPROVAL =
        115792089237316195423570985008687907853269984665640564039457584007913129639935;

    // â”€â”€ IMMUTABLE STATE â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    // Set once at deployment - locked forever
    address public immutable owner;
    uint256 public immutable unlockTime;
    string  public vaultName;

    // â”€â”€ TRACKING â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    uint256 public totalEthDeposited;
    uint256 public totalUsdcDeposited;
    uint256 public ethDepositCount;
    uint256 public usdcDepositCount;

    // â”€â”€ EVENTS â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    event EthDeposited(
        address indexed from,
        uint256 amount,
        uint256 newBalance,
        uint256 timestamp
    );

    event UsdcDeposited(
        address indexed from,
        uint256 usdcAmount,
        uint256 newUsdcBalance,
        uint256 timestamp
    );

    event EthWithdrawn(
        address indexed to,
        uint256 amount,
        uint256 timestamp
    );

    event UsdcWithdrawn(
        address indexed to,
        uint256 amount,
        uint256 timestamp
    );

    event VaultCreated(
        address indexed owner,
        uint256 unlockTime,
        string  name,
        uint256 timestamp
    );

    // â”€â”€ CONSTRUCTOR â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    // Deploy once with your chosen lock duration
    //
    // _lockDurationSeconds:
    //   300        = 5 minutes  (testing)
    //   86400      = 1 day      (testing)
    //   259200     = 3 days     (short save)
    //   2592000    = 1 month
    //   31536000   = 1 year
    //   157680000  = 5 years
    //
    // _vaultName example: "OvoWorks Base Vault 2031"
    //
    constructor(
        uint256 _lockDurationSeconds,
        string memory _vaultName
    ) {
        require(
            _lockDurationSeconds >= 60,
            "Minimum lock is 60 seconds"
        );
        require(
            bytes(_vaultName).length > 0,
            "Vault needs a name"
        );
        require(
            bytes(_vaultName).length <= 100,
            "Name max 100 characters"
        );

        owner      = msg.sender;
        unlockTime = block.timestamp + _lockDurationSeconds;
        vaultName  = _vaultName;

        emit VaultCreated(
            msg.sender,
            unlockTime,
            _vaultName,
            block.timestamp
        );
    }

    // â”€â”€ MODIFIERS â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    modifier onlyOwner() {
        require(
            msg.sender == owner,
            "Only vault owner can do this"
        );
        _;
    }

    modifier isUnlocked() {
        require(
            block.timestamp >= unlockTime,
            "Vault is still locked"
        );
        _;
    }

    // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    //  ETH FUNCTIONS
    //  No approve needed - ETH is native token
    //  Just send ETH with the transaction
    // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

    // Deposit ETH - set Value field in Remix before clicking
    function depositEth() external payable {
        require(msg.value > 0, "Send some ETH");
        totalEthDeposited += msg.value;
        ethDepositCount   += 1;
        emit EthDeposited(
            msg.sender,
            msg.value,
            address(this).balance,
            block.timestamp
        );
    }

    // Accept plain ETH transfers from MetaMask/Rabby directly
    receive() external payable {
        require(msg.value > 0, "Send some ETH");
        totalEthDeposited += msg.value;
        ethDepositCount   += 1;
        emit EthDeposited(
            msg.sender,
            msg.value,
            address(this).balance,
            block.timestamp
        );
    }

    // Withdraw ALL ETH after unlock
    function withdrawAllEth() external onlyOwner isUnlocked {
        uint256 balance = address(this).balance;
        require(balance > 0, "No ETH in vault");
        (bool success, ) = payable(owner).call{value: balance}("");
        require(success, "ETH withdrawal failed");
        emit EthWithdrawn(owner, balance, block.timestamp);
    }

    // Withdraw SPECIFIC amount of ETH after unlock
    function withdrawEth(
        uint256 _amount
    ) external onlyOwner isUnlocked {
        require(_amount > 0, "Amount must be greater than 0");
        require(
            _amount <= address(this).balance,
            "Not enough ETH in vault"
        );
        (bool success, ) = payable(owner).call{value: _amount}("");
        require(success, "ETH withdrawal failed");
        emit EthWithdrawn(owner, _amount, block.timestamp);
    }

    // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    //  USDC FUNCTIONS
    //
    //  ONE TIME SETUP (do this once, never again):
    //  1. Go to USDC contract on Basescan
    //  2. Call approve(THIS_VAULT_ADDRESS, MAX_APPROVAL_AMOUNT)
    //     MAX_APPROVAL_AMOUNT = 115792089237316195423570985008687907853269984665640564039457584007913129639935
    //  3. Confirm in Rabby
    //  4. Done forever - deposit USDC anytime without approving again
    //
    //  USDC amounts use 6 decimal places:
    //  $1    = 1000000
    //  $10   = 10000000
    //  $100  = 100000000
    //  $1000 = 1000000000
    // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

    // Check if unlimited approval is already set
    // Call this to see if you need to approve or not
    function isApproved() external view returns (bool) {
        uint256 allowance = USDC.allowance(msg.sender, address(this));
        return allowance >= MAX_APPROVAL / 2;
        // â˜ï¸ If allowance is at least half of max
        //    we consider it an unlimited approval
    }

    // Deposit USDC - no approve needed after first time
    // _amount in USDC units (6 decimals):
    //   $1   = 1000000
    //   $100 = 100000000
    function depositUsdc(uint256 _amount) external {
        require(_amount > 0, "Amount must be greater than 0");

        // Check allowance - gives helpful error if not approved yet
        uint256 allowance = USDC.allowance(
            msg.sender,
            address(this)
        );
        require(
            allowance >= _amount,
            "Please approve USDC first - do this once on Basescan"
        );

        bool success = USDC.transferFrom(
            msg.sender,
            address(this),
            _amount
        );
        require(success, "USDC transfer failed");

        totalUsdcDeposited += _amount;
        usdcDepositCount   += 1;

        emit UsdcDeposited(
            msg.sender,
            _amount,
            USDC.balanceOf(address(this)),
            block.timestamp
        );
    }

    // Withdraw ALL USDC after unlock
    function withdrawAllUsdc() external onlyOwner isUnlocked {
        uint256 balance = USDC.balanceOf(address(this));
        require(balance > 0, "No USDC in vault");
        bool success = USDC.transfer(owner, balance);
        require(success, "USDC withdrawal failed");
        emit UsdcWithdrawn(owner, balance, block.timestamp);
    }

    // Withdraw SPECIFIC amount of USDC after unlock
    function withdrawUsdc(
        uint256 _amount
    ) external onlyOwner isUnlocked {
        require(_amount > 0, "Amount must be greater than 0");
        uint256 balance = USDC.balanceOf(address(this));
        require(_amount <= balance, "Not enough USDC in vault");
        bool success = USDC.transfer(owner, _amount);
        require(success, "USDC withdrawal failed");
        emit UsdcWithdrawn(owner, _amount, block.timestamp);
    }

    // Withdraw BOTH ETH and USDC in one transaction
    function withdrawAll() external onlyOwner isUnlocked {
        // Withdraw ETH if any
        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            (bool ethOk, ) = payable(owner).call{
                value: ethBalance
            }("");
            require(ethOk, "ETH withdrawal failed");
            emit EthWithdrawn(owner, ethBalance, block.timestamp);
        }

        // Withdraw USDC if any
        uint256 usdcBalance = USDC.balanceOf(address(this));
        if (usdcBalance > 0) {
            bool usdcOk = USDC.transfer(owner, usdcBalance);
            require(usdcOk, "USDC withdrawal failed");
            emit UsdcWithdrawn(
                owner,
                usdcBalance,
                block.timestamp
            );
        }
    }

    // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    //  READ FUNCTIONS - Free to call, no gas needed
    // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

    function getEthBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function getUsdcBalance() external view returns (uint256) {
        return USDC.balanceOf(address(this));
    }

    // Returns USDC balance in whole dollars (easy to read)
    function getUsdcInDollars()
        external
        view
        returns (uint256 dollars, uint256 cents)
    {
        uint256 raw = USDC.balanceOf(address(this));
        dollars = raw / 1_000_000;
        cents   = (raw % 1_000_000) / 10_000;
    }

    function getTimeRemaining() external view returns (uint256) {
        if (block.timestamp >= unlockTime) return 0;
        return unlockTime - block.timestamp;
    }

    function getDaysRemaining() external view returns (uint256) {
        if (block.timestamp >= unlockTime) return 0;
        return (unlockTime - block.timestamp) / 1 days;
    }

    function isLocked() external view returns (bool) {
        return block.timestamp < unlockTime;
    }

    // Returns everything about the vault in one call
    function getVaultInfo() external view returns (
        address _owner,
        string  memory _name,
        uint256 _ethBalance,
        uint256 _usdcBalance,
        uint256 _usdcDollars,
        uint256 _unlockTime,
        uint256 _daysRemaining,
        bool    _isLocked,
        uint256 _totalEthDeposited,
        uint256 _totalUsdcDeposited
    ) {
        uint256 usdcBal = USDC.balanceOf(address(this));
        uint256 days_   = block.timestamp >= unlockTime
            ? 0
            : (unlockTime - block.timestamp) / 1 days;

        return (
            owner,
            vaultName,
            address(this).balance,
            usdcBal,
            usdcBal / 1_000_000,
            unlockTime,
            days_,
            block.timestamp < unlockTime,
            totalEthDeposited,
            totalUsdcDeposited
        );
    }
}
