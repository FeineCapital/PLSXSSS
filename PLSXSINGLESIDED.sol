// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts@4.8.3/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts@4.8.3/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts@4.8.3/access/Ownable.sol";
import "@openzeppelin/contracts@4.8.3/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts@4.8.3/utils/math/SafeMath.sol";

/**
 * @title SimplePLSXStaking
 * @dev Simplified contract for staking PLSX tokens with fees
 */
contract SimplePLSXStaking is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // The PLSX token contract
    IERC20 public plsxToken;
    
    // Reward rate - tokens distributed per second
    uint256 public rewardRate;
    
    // Last time rewards were updated
    uint256 public lastUpdateTime;
    
    // Reward per token stored
    uint256 public rewardPerTokenStored;
    
    // Total staked tokens
    uint256 public totalStaked;
    
    // Minimum stake amount
    uint256 public minimumStake;
    
    // Maximum APR (annual percentage rate) as basis points (1% = 100)
    uint256 public maxAPR;
    
    // Fee percentages (in basis points, 1% = 100)
    uint256 public constant TOTAL_FEE = 90; // 0.9%
    uint256 public constant REWARD_POOL_FEE = 50; // 0.5%
    uint256 public constant DEV_WALLET_FEE = 30; // 0.3%
    uint256 public constant FEE_DENOMINATOR = 10000; // Basis points denominator
    
    // Dev wallet address
    address public constant DEV_WALLET = 0x5D4ec8b4f491f8Ca6cC2800a995A27E28ea561A8;
    
    // User rewards per token paid
    mapping(address => uint256) public userRewardPerTokenPaid;
    
    // Accumulated rewards for user
    mapping(address => uint256) public rewards;
    
    // User staking balances
    mapping(address => uint256) public balances;
    
    // Events
    event Staked(address indexed user, uint256 amount, uint256 fee);
    event Withdrawn(address indexed user, uint256 amount, uint256 fee);
    event RewardPaid(address indexed user, uint256 reward);
    event FeeDistributed(uint256 totalFee, uint256 rewardPoolFee, uint256 devWalletFee);

    /**
     * @dev Constructor - simple version with hardcoded defaults
     * @param _plsxToken Address of the PLSX token
     */
    constructor(address _plsxToken) {
        require(_plsxToken != address(0), "Invalid token address");
        plsxToken = IERC20(_plsxToken);
        rewardRate = 1000000000000; // 0.000001 PLSX per second (smaller default)
        minimumStake = 1000000000000000; // 0.001 PLSX (smaller default)
        maxAPR = 3000; // 30%
        lastUpdateTime = block.timestamp;
    }

    /**
     * @dev Returns the latest reward per token
     * @return Calculated reward per token
     */
    function rewardPerToken() public view returns (uint256) {
        if (totalStaked == 0) {
            return rewardPerTokenStored;
        }
        
        return rewardPerTokenStored.add(
            block.timestamp.sub(lastUpdateTime).mul(rewardRate).mul(1e18).div(totalStaked)
        );
    }

    /**
     * @dev Returns the earned rewards for a user
     * @param account User address
     * @return Earned rewards
     */
    function earned(address account) public view returns (uint256) {
        return balances[account].mul(
            rewardPerToken().sub(userRewardPerTokenPaid[account])
        ).div(1e18).add(rewards[account]);
    }

    /**
     * @dev Calculate fee for a given amount
     * @param amount Amount to calculate fee on
     * @return totalFee, rewardPoolFee, devWalletFee
     */
    function calculateFees(uint256 amount) public pure returns (uint256, uint256, uint256) {
        uint256 totalFee = amount.mul(TOTAL_FEE).div(FEE_DENOMINATOR);
        uint256 rewardPoolFee = amount.mul(REWARD_POOL_FEE).div(FEE_DENOMINATOR);
        uint256 devWalletFee = amount.mul(DEV_WALLET_FEE).div(FEE_DENOMINATOR);
        return (totalFee, rewardPoolFee, devWalletFee);
    }

    /**
     * @dev Updates reward calculations
     * @param account User address
     */
    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = block.timestamp;
        
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    /**
     * @dev Stakes tokens
     * @param amount Amount to stake
     */
    function stake(uint256 amount) external nonReentrant updateReward(msg.sender) {
        require(amount >= minimumStake, "Cannot stake less than minimum");
        
        // Calculate and deduct fee
        (uint256 totalFee, uint256 rewardPoolFee, uint256 devWalletFee) = calculateFees(amount);
        
        // Amount after fee
        uint256 stakeAmount = amount.sub(totalFee);
        
        // Update state
        totalStaked = totalStaked.add(stakeAmount);
        balances[msg.sender] = balances[msg.sender].add(stakeAmount);
        
        // Transfer tokens from user
        plsxToken.safeTransferFrom(msg.sender, address(this), amount);
        
        // Distribute fees
        if (devWalletFee > 0) {
            plsxToken.safeTransfer(DEV_WALLET, devWalletFee);
        }
        
        emit Staked(msg.sender, stakeAmount, totalFee);
        emit FeeDistributed(totalFee, rewardPoolFee, devWalletFee);
    }

    /**
     * @dev Withdraws staked tokens
     * @param amount Amount to withdraw
     */
    function withdraw(uint256 amount) external nonReentrant updateReward(msg.sender) {
        require(amount > 0, "Cannot withdraw 0");
        require(balances[msg.sender] >= amount, "Not enough staked tokens");
        
        // Calculate fee
        (uint256 totalFee, uint256 rewardPoolFee, uint256 devWalletFee) = calculateFees(amount);
        
        // Amount after fee
        uint256 withdrawAmount = amount.sub(totalFee);
        
        // Update state
        totalStaked = totalStaked.sub(amount);
        balances[msg.sender] = balances[msg.sender].sub(amount);
        
        // Transfer tokens to user
        plsxToken.safeTransfer(msg.sender, withdrawAmount);
        
        // Distribute fees
        if (devWalletFee > 0) {
            plsxToken.safeTransfer(DEV_WALLET, devWalletFee);
        }
        
        emit Withdrawn(msg.sender, withdrawAmount, totalFee);
        emit FeeDistributed(totalFee, rewardPoolFee, devWalletFee);
    }

    /**
     * @dev Claims rewards
     */
    function getReward() external nonReentrant updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            plsxToken.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    /**
     * @dev Updates reward rate (owner only)
     * @param _rewardRate New reward rate
     */
    function setRewardRate(uint256 _rewardRate) external onlyOwner updateReward(address(0)) {
        rewardRate = _rewardRate;
    }

    /**
     * @dev Updates minimum stake amount (owner only)
     * @param _minimumStake New minimum stake
     */
    function setMinimumStake(uint256 _minimumStake) external onlyOwner {
        minimumStake = _minimumStake;
    }

    /**
     * @dev Updates maximum APR (owner only)
     * @param _maxAPR New maximum APR in basis points
     */
    function setMaxAPR(uint256 _maxAPR) external onlyOwner {
        maxAPR = _maxAPR;
    }

    /**
     * @dev Allows owner to recover any ERC20 tokens sent to the contract by mistake
     * @param tokenAddress Address of the token
     * @param tokenAmount Amount to recover
     */
    function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyOwner {
        // Cannot recover staked token
        require(tokenAddress != address(plsxToken), "Cannot recover staked token");
        
        IERC20(tokenAddress).safeTransfer(owner(), tokenAmount);
    }

    /**
     * @dev Allows owner to add rewards manually
     * @param amount Amount to add to reward pool
     */
    function addRewards(uint256 amount) external {
        plsxToken.safeTransferFrom(msg.sender, address(this), amount);
    }
}