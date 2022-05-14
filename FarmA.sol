// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./helpers/ERC20.sol";
import "./libraries/Address.sol";
import "./libraries/SafeERC20.sol";
import "./libraries/EnumerableSet.sol";
import "./helpers/Ownable.sol";
import "./helpers/ReentrancyGuard.sol";
import "./interfaces/IWBNB.sol";
import "./interfaces/IERC20.sol";

contract FarmA is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // address public stakeTokenAddr = 0xa7192A84959727aA4868a6d57a29B694d585277D;
    // address public rewardTokenAddr = 0x2b7CBcB48a938811AA36D64764d395981f0F63f8;

    address public stakeTokenAddr = 0x9F9c48970C5C6CA6E555A265Beaa2ee2787B85d3;
    address public rewardTokenAddr = 0x6e5B9FEbE03362dE87078b51f97DD256CBC538c0;

    // Info of each user.
    struct UserInfo {
        uint256 stakeAmount; 
        uint256 stakeReward;
        uint256 totalAmount;
        uint256 releaseAmount;
        uint256 amountPerBlock;
        uint256 stakeType; 
        uint256 stakeBlock; 
        uint256 lastRewardBlock;
        uint256 nextRewardBlock;
    }

    mapping(address => UserInfo) public userInfo; 

    event Deposit(address indexed user, uint256 stakeType, uint256 amount);
    event Claim(address indexed user, uint256 stakeType, uint256 amount);

    constructor() public {}

    function deposit(uint256 stakeType, uint256 amount) public payable nonReentrant {
        require(stakeType == 12, "stakeType error");
       
        IERC20(stakeTokenAddr).transferFrom(address(msg.sender), address(this), amount);
        
        UserInfo storage user = userInfo[msg.sender];
        user.stakeAmount += amount;
        user.stakeReward += amount * stakeType/100;
        user.totalAmount = user.stakeAmount + user.stakeReward;
        user.amountPerBlock = (user.totalAmount - user.releaseAmount) / (28800 * 30 * stakeType);
        user.stakeType = stakeType; 
        user.stakeBlock = block.number; 
        user.lastRewardBlock = block.number;

        emit Deposit(msg.sender, stakeType, amount);
    }

    function claim() public nonReentrant {
        UserInfo storage user = userInfo[msg.sender];
        require(block.number >= user.nextRewardBlock, "24 hour only claim 1 times");

        uint256 blockNum = block.number - user.lastRewardBlock;
        uint256 reward = blockNum * user.amountPerBlock;
        user.releaseAmount += reward;
        user.lastRewardBlock = block.number;
        user.nextRewardBlock = block.number + 28800;

        require(user.releaseAmount <= user.totalAmount, "releaseAmount must be <= totalAmount");
        if(reward > 0) {
            safeTransfer(msg.sender, reward);
        }

        emit Claim(msg.sender, user.stakeType, reward);
    }

    function getAmountInfo(address owner) public view returns (uint256 pendingReward, uint256 lockAmount, uint256 nextRewardBlock) {
        UserInfo storage user = userInfo[owner];
        
        uint256 blockNum = block.number - user.lastRewardBlock;
        pendingReward = blockNum * user.amountPerBlock;
        lockAmount = user.totalAmount - user.releaseAmount - pendingReward;
        nextRewardBlock = user.nextRewardBlock;
    }

    function safeTransfer(address _to, uint256 amount) internal {
        uint256 bal = IERC20(rewardTokenAddr).balanceOf(address(this));
        if (amount > bal) {
            IERC20(rewardTokenAddr).transfer(_to, bal);
        } else {
            IERC20(rewardTokenAddr).transfer(_to, amount);
        }
    }
}
