// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "./Token.sol";

/**
 * @title Automated Market Maker (AMM)
 * @dev Implements a constant product market maker (x * y = k) for two ERC20 tokens
 * Allows users to:
 * - Provide liquidity to the pool
 * - Swap between the two tokens
 * - Remove liquidity from the pool
 */
contract AutomatedMarketMaker {
    // Token contracts
    Token public tokenA;
    Token public tokenB;

    // Pool reserves
    uint256 public tokenAReserve;
    uint256 public tokenBReserve;
    uint256 public constantProduct; // The k in the x * y = k formula

    // Liquidity tracking
    uint256 public totalLiquidityShares;
    mapping(address => uint256) public userLiquidityShares;
    uint256 constant PRECISION = 10**18; // Used for precision in share calculations

    
    // @dev Emitted when a token swap occurs
    event Swap(
        address indexed user,
        address tokenProvided,
        uint256 amountProvided,
        address tokenReceived,
        uint256 amountReceived,
        uint256 newTokenAReserve,
        uint256 newTokenBReserve,
        uint256 timestamp
    );

    
    // @dev Initializes the AMM with two token contracts
    // @param _tokenA The first token in the trading pair
    // @param _tokenB The second token in the trading pair
    constructor(Token _tokenA, Token _tokenB) {
        tokenA = _tokenA;
        tokenB = _tokenB;
    }

    // @dev Adds liquidity to the pool
    // @param _tokenAAmount Amount of tokenA to deposit
    // @param _tokenBAmount Amount of tokenB to deposit
    // @notice For the first deposit, any ratio is accepted. For subsequent deposits,
    // the ratio must match the current pool ratio to avoid price manipulation.
    function addLiquidity(uint256 _tokenAAmount, uint256 _tokenBAmount) external {
        // Transfer tokens from user to the contract
        require(
            tokenA.transferFrom(msg.sender, address(this), _tokenAAmount),
            "Failed to transfer tokenA to the pool"
        );
        require(
            tokenB.transferFrom(msg.sender, address(this), _tokenBAmount),
            "Failed to transfer tokenB to the pool"
        );

        // Calculate liquidity shares to mint
        uint256 sharesToMint;

        // If first time adding liquidity, initialize with 100 shares
        if (totalLiquidityShares == 0) {
            sharesToMint = 100 * PRECISION;
        } else {
            // Calculate shares based on the proportion of existing reserves being added
            uint256 sharesBasedOnTokenA = (totalLiquidityShares * _tokenAAmount) / tokenAReserve;
            uint256 sharesBasedOnTokenB = (totalLiquidityShares * _tokenBAmount) / tokenBReserve;
            
            // Ensure proportional deposits (allowing for small rounding errors)
            require(
                (sharesBasedOnTokenA / 10**3) == (sharesBasedOnTokenB / 10**3),
                "Must provide tokens in the current pool ratio"
            );
            sharesToMint = sharesBasedOnTokenA;
        }

        // Update pool state
        tokenAReserve += _tokenAAmount;
        tokenBReserve += _tokenBAmount;
        constantProduct = tokenAReserve * tokenBReserve;

        // Update liquidity shares
        totalLiquidityShares += sharesToMint;
        userLiquidityShares[msg.sender] += sharesToMint;
    }

    // @dev Calculates how much tokenB should be deposited given an amount of tokenA
    // @param _tokenAAmount Amount of tokenA to deposit
    // @return requiredTokenBAmount Amount of tokenB required to maintain the current ratio
    function calculateTokenBDeposit(uint256 _tokenAAmount)
        public
        view
        returns (uint256 requiredTokenBAmount)
    {
        requiredTokenBAmount = (tokenBReserve * _tokenAAmount) / tokenAReserve;
    }

    // @dev Calculates how much tokenA should be deposited given an amount of tokenB
    // @param _tokenBAmount Amount of tokenB to deposit
    // @return requiredTokenAAmount Amount of tokenA required to maintain the current ratio
    function calculateTokenADeposit(uint256 _tokenBAmount)
        public
        view
        returns (uint256 requiredTokenAAmount)
    {
        requiredTokenAAmount = (tokenAReserve * _tokenBAmount) / tokenBReserve;
    }

    // @dev Calculates how much tokenB will be received when swapping tokenA
    // @param _tokenAAmount Amount of tokenA to swap
    // @return tokenBOutput Amount of tokenB that will be received
    // @notice Uses the constant product formula: x * y = k
    function calculateTokenASwap(uint256 _tokenAAmount)
        public
        view
        returns (uint256 tokenBOutput)
    {
        uint256 tokenAAfterSwap = tokenAReserve + _tokenAAmount;
        uint256 tokenBAfterSwap = constantProduct / tokenAAfterSwap;
        tokenBOutput = tokenBReserve - tokenBAfterSwap;

        // Safety check: Don't drain the entire pool
        if (tokenBOutput == tokenBReserve) {
            tokenBOutput--;
        }

        require(tokenBOutput < tokenBReserve, "Swap amount too large for pool reserves");
    }

    // @dev Swaps tokenA for tokenB
    // @param _tokenAAmount Amount of tokenA to swap
    // @return tokenBOutput Amount of tokenB received from the swap
    function swapTokenA(uint256 _tokenAAmount)
        external
        returns(uint256 tokenBOutput)
    {
        // Calculate the amount of tokenB to be received
        tokenBOutput = calculateTokenASwap(_tokenAAmount);

        // Execute the swap
        tokenA.transferFrom(msg.sender, address(this), _tokenAAmount);
        tokenAReserve += _tokenAAmount;
        tokenBReserve -= tokenBOutput;
        tokenB.transfer(msg.sender, tokenBOutput);

        // Emit swap event
        emit Swap(
            msg.sender,
            address(tokenA),
            _tokenAAmount,
            address(tokenB),
            tokenBOutput,
            tokenAReserve,
            tokenBReserve,
            block.timestamp
        );
    }

    
    // @dev Calculates how much tokenA will be received when swapping tokenB
    // @param _tokenBAmount Amount of tokenB to swap
    // @return tokenAOutput Amount of tokenA that will be received
    // @notice Uses the constant product formula: x * y = k
    function calculateTokenBSwap(uint256 _tokenBAmount)
        public
        view
        returns (uint256 tokenAOutput)
    {
        uint256 tokenBAfterSwap = tokenBReserve + _tokenBAmount;
        uint256 tokenAAfterSwap = constantProduct / tokenBAfterSwap;
        tokenAOutput = tokenAReserve - tokenAAfterSwap;

        // Safety check: Don't drain the entire pool
        if (tokenAOutput == tokenAReserve) {
            tokenAOutput--;
        }

        require(tokenAOutput < tokenAReserve, "Swap amount too large for pool reserves");
    }

    // @dev Swaps tokenB for tokenA
    // @param _tokenBAmount Amount of tokenB to swap
    // @return tokenAOutput Amount of tokenA received from the swap
    function swapTokenB(uint256 _tokenBAmount)
        external
        returns(uint256 tokenAOutput)
    {
        // Calculate the amount of tokenA to be received
        tokenAOutput = calculateTokenBSwap(_tokenBAmount);

        // Execute the swap
        tokenB.transferFrom(msg.sender, address(this), _tokenBAmount);
        tokenBReserve += _tokenBAmount;
        tokenAReserve -= tokenAOutput;
        tokenA.transfer(msg.sender, tokenAOutput);

        // Emit swap event
        emit Swap(
            msg.sender,
            address(tokenB),
            _tokenBAmount,
            address(tokenA),
            tokenAOutput,
            tokenAReserve,
            tokenBReserve,
            block.timestamp
        );
    }

    // Calculates how many tokens will be withdrawn for a given amount of shares
    // @param _sharesToWithdraw Number of liquidity shares to withdraw
    // @return tokenAAmount Amount of tokenA to be withdrawn
    // @return tokenBAmount Amount of tokenB to be withdrawn
    function calculateWithdrawAmount(uint256 _sharesToWithdraw)
        public
        view
        returns (uint256 tokenAAmount, uint256 tokenBAmount)
    {
        require(_sharesToWithdraw <= totalLiquidityShares, "Cannot withdraw more than total shares");
        
        // Calculate withdrawal amounts proportional to shares
        tokenAAmount = (_sharesToWithdraw * tokenAReserve) / totalLiquidityShares;
        tokenBAmount = (_sharesToWithdraw * tokenBReserve) / totalLiquidityShares;
    }

    // Removes liquidity from the pool
    // @param _sharesToWithdraw Number of liquidity shares to withdraw
    // @return tokenAAmount Amount of tokenA withdrawn
    // @return tokenBAmount Amount of tokenB withdrawn
    function removeLiquidity(uint256 _sharesToWithdraw)
        external
        returns(uint256 tokenAAmount, uint256 tokenBAmount)
    {
        require(
            _sharesToWithdraw <= userLiquidityShares[msg.sender],
            "Cannot withdraw more shares than you own"
        );

        // Calculate token amounts to withdraw
        (tokenAAmount, tokenBAmount) = calculateWithdrawAmount(_sharesToWithdraw);

        // Update state
        userLiquidityShares[msg.sender] -= _sharesToWithdraw;
        totalLiquidityShares -= _sharesToWithdraw;

        tokenAReserve -= tokenAAmount;
        tokenBReserve -= tokenBAmount;
        constantProduct = tokenAReserve * tokenBReserve;

        // Transfer tokens to user
        tokenA.transfer(msg.sender, tokenAAmount);
        tokenB.transfer(msg.sender, tokenBAmount);
    }
}