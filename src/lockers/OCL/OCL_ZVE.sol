// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.17;

import "../../ZivoeLocker.sol";

import "../../../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";

interface IZivoeGlobals_OCL_ZVE {
    /// @notice Returns the address of the Timelock contract.
    function TLC() external view returns (address);

    /// @notice Returns the address of the ZivoeYDL contract.
    function YDL() external view returns (address);

    /// @notice Returns the address of the ZivoeToken contract.
    function ZVE() external view returns (address);

    /// @notice Returns true if an address is whitelisted as a keeper.
    /// @return keeper Equals "true" if address is a keeper, "false" if not.
    function isKeeper(address) external view returns (bool keeper);
}

interface IZivoeYDL_OCL_ZVE {
    /// @notice Returns the "stablecoin" that will be distributed via YDL.
    /// @return asset The address of the "stablecoin" that will be distributed via YDL.
    function distributedAsset() external view returns (address asset);
}

interface IRouter_OCL_ZVE {
    /// @notice Adds liquidity in a pool with both ERC20 tokens A and B.
    /// @param tokenA A pool token.
    /// @param tokenB A pool token.
    /// @param amountADesired The amount of tokenA to add as liquidity if the B/A price is <= amountBDesired/amountADesired (A depreciates).
    /// @param amountBDesired The amount of tokenB to add as liquidity if the A/B price is <= amountADesired/amountBDesired (B depreciates).
    /// @param amountAMin Bounds the extent to which the B/A price can go up before the transaction reverts. Must be <= amountADesired.
    /// @param amountBMin Bounds the extent to which the A/B price can go up before the transaction reverts. Must be <= amountBDesired.
    /// @param to Recipient of the liquidity tokens.
    /// @param deadline Unix timestamp after which the transaction will revert.
    /// @return amountA The amount of tokenA sent to the pool.
    /// @return amountB The amount of tokenB sent to the pool.
    /// @return liquidity The amount of liquidity tokens minted.
    function addLiquidity(
        address tokenA, address tokenB, uint256 amountADesired, uint256 amountBDesired, uint256 amountAMin, uint256 amountBMin, address to, uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);

    /// @notice Removes liquidity in a pool with both ERC20 tokens A and B.
    /// @param tokenA A pool token.
    /// @param tokenB A pool token.
    /// @param liquidity The amount of liquidity tokens to remove.
    /// @param amountAMin The minimum amount of tokenA that must be received for the transaction not to revert.
    /// @param amountBMin The minimum amount of tokenB that must be received for the transaction not to revert.
    /// @param to Recipient of the underlying assets.
    /// @param deadline Unix timestamp after which the transaction will revert.
    /// @return amountA The amount of tokenA received.
    /// @return amountB The amount of tokenB received.
    function removeLiquidity(
        address tokenA, address tokenB, uint256 liquidity, uint256 amountAMin, uint256 amountBMin, address to, uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB);
}

interface IFactory_OCL_ZVE {
    /// @notice Returns the address of the pair for tokenA and tokenB, if it has been created, else address(0).
    /// @param tokenA Address of one of pair's tokens.
    /// @param tokenB Address of pair's other token.
    /// @return pair The address of the pair.
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}



/// @notice This contract manages liquidity provisioning for a Uniswap v2 or Sushi pool.
///         This contract has the following responsibilities:
///           - Allocate capital to a $ZVE/pairAsset pool.
///           - Remove capital from a $ZVE/pairAsset pool.
///           - Forward yield (profits) every 30 days to the YDL with compounding mechanisms.
contract OCL_ZVE is ZivoeLocker, ReentrancyGuard {

    using SafeERC20 for IERC20;
    
    // ---------------------
    //    State Variables
    // ---------------------

    address public immutable GBL;               /// @dev The ZivoeGlobals contract.

    address public immutable pairAsset;         /// @dev ERC20 that will be paired with $ZVE for Sushi pool.
    address public immutable router;            /// @dev Address for the Router (Uniswap v2 or Sushi).
    address public immutable factory;           /// @dev Aaddress for the Factory (Uniswap v2 or Sushi).

    address public OCT_YDL;                     /// @dev The contract that facilitates swaps and forwards distributedAsset() to YDL.
    
    uint256 public basis;                       /// @dev The basis used for forwardYield() accounting.
    uint256 public nextYieldDistribution;       /// @dev Determines next available forwardYield() call.
    
    uint256 public compoundingRateBIPS = 5000;  /// @dev The % of returns to retain, in BIPS.

    uint256 private constant BIPS = 10000;



    // -----------------
    //    Constructor
    // -----------------

    /// @notice Initializes the OCL_ZVE contract.
    /// @param DAO The administrator of this contract (intended to be ZivoeDAO).
    /// @param _GBL The ZivoeGlobals contract.
    /// @param _pairAsset ERC20 that will be paired with $ZVE for pool.
    /// @param  _OCT_YDL The contract that facilitates swaps and forwards distributedAsset() to YDL.
    constructor(address DAO, address _GBL, address _pairAsset, address _router, address _factory, address _OCT_YDL) {
        transferOwnership(DAO);
        GBL = _GBL;
        pairAsset = _pairAsset;
        router = _router;
        factory = _factory;
        OCT_YDL = _OCT_YDL;
    }



    // ------------
    //    Events   
    // ------------

    /// @notice This event is emitted when updateCompoundingRateBIPS() is called.
    /// @param  oldValue The old value of compoundingRateBIPS.
    /// @param  newValue The new value of compoundingRateBIPS.
    event UpdatedCompoundingRateBIPS(uint256 oldValue, uint256 newValue);

    /// @notice Emitted during forwardYield().
    /// @param  asset The "asset" being distributed.
    /// @param  amount The amount distributed.
    event YieldForwarded(address indexed asset, uint256 amount);



    // ---------------
    //    Functions
    // ---------------

    /// @notice Permission for owner to call pushToLocker().
    function canPush() public override pure returns (bool) { return true; }

    /// @notice Permission for owner to call pushToLockerMulti().
    function canPushMulti() public override pure returns (bool) { return true; }

    /// @notice Permission for owner to call pullFromLocker().
    function canPull() public override pure returns (bool) { return true; }

    /// @notice Permission for owner to call pullFromLockerPartial().
    function canPullPartial() public override pure returns (bool) { return true; }

    /// @notice Migrates specific amount of ERC20 from owner() to locker.
    /// @param  asset The asset to migrate.
    /// @param  amount The amount of "asset" to migrate.
    /// @param  data Accompanying transaction data.
    function pushToLocker(address asset, uint256 amount, bytes calldata data) external override onlyOwner {
        require(
            asset == pairAsset || asset == IZivoeGlobals_OCL_ZVE(GBL).ZVE(),
            "asset != pairAsset && asset != IZivoeGlobals_OCL_ZVE(GBL).ZVE()"
        );
        IERC20(asset).safeTransferFrom(owner(), address(this), amount);

        // TODO: Implement addLiqudiity() for pairAsset

        // TODO: Implement addLiquidity() for ZVE
    }

    /// @notice This pulls capital from the DAO and adds liquidity into a $ZVE/pairAsset pool.
    /// @param  assets The assets to pull from the DAO.
    /// @param  amounts The amount to pull of each asset respectively.
    /// @param  data Accompanying transaction data.
    function pushToLockerMulti(address[] calldata assets, uint256[] calldata amounts, bytes[] calldata data) external override onlyOwner nonReentrant {
        require(
            assets[0] == pairAsset && assets[1] == IZivoeGlobals_OCL_ZVE(GBL).ZVE(),
            "OCL_ZVE::pushToLockerMulti() assets[0] != pairAsset || assets[1] != IZivoeGlobals_OCL_ZVE(GBL).ZVE()"
        );

        for (uint256 i = 0; i < 2; i++) {
            require(amounts[i] >= 10 * 10**6, "OCL_ZVE::pushToLockerMulti() amounts[i] < 10 * 10**6");
            IERC20(assets[i]).safeTransferFrom(owner(), address(this), amounts[i]);
        }

        if (nextYieldDistribution == 0) { nextYieldDistribution = block.timestamp + 30 days; }

        uint256 preBasis;
        if (basis != 0) { (preBasis,) = fetchBasis(); }

        // Router addLiquidity() endpoint.
        IERC20(pairAsset).safeApprove(router, IERC20(pairAsset).balanceOf(address(this)));
        IERC20(IZivoeGlobals_OCL_ZVE(GBL).ZVE()).safeApprove(router, IERC20(IZivoeGlobals_OCL_ZVE(GBL).ZVE()).balanceOf(address(this)));
        IRouter_OCL_ZVE(router).addLiquidity(
            pairAsset, IZivoeGlobals_OCL_ZVE(GBL).ZVE(), IERC20(pairAsset).balanceOf(address(this)),
            IERC20(IZivoeGlobals_OCL_ZVE(GBL).ZVE()).balanceOf(address(this)), IERC20(pairAsset).balanceOf(address(this)),
            IERC20(IZivoeGlobals_OCL_ZVE(GBL).ZVE()).balanceOf(address(this)), address(this), block.timestamp + 14 days
        );
        assert(IERC20(pairAsset).allowance(address(this), router) == 0);
        assert(IERC20(IZivoeGlobals_OCL_ZVE(GBL).ZVE()).allowance(address(this), router) == 0);

        // Increase basis.
        (uint256 postBasis,) = fetchBasis();
        require(postBasis > preBasis, "OCL_ZVE::pushToLockerMulti() postBasis <= preBasis");
        basis = postBasis - preBasis;
    }

    /// @notice This burns LP tokens from the $ZVE/pairAsset pool and returns them to the DAO.
    /// @param  asset The asset to burn.
    /// @param  data Accompanying transaction data.
    function pullFromLocker(address asset, bytes calldata data) external override onlyOwner nonReentrant {
        address pair = IFactory_OCL_ZVE(factory).getPair(pairAsset, IZivoeGlobals_OCL_ZVE(GBL).ZVE());
        
        // "pair" represents the liquidity pool token (minted, burned).
        // "pairAsset" represents the stablecoin paired against $ZVE.
        if (asset == pair) {
            IERC20(pair).safeApprove(router, IERC20(pair).balanceOf(address(this)));
            IRouter_OCL_ZVE(router).removeLiquidity(
                pairAsset, IZivoeGlobals_OCL_ZVE(GBL).ZVE(), IERC20(pair).balanceOf(address(this)), 
                0, 0, address(this), block.timestamp + 14 days
            );
            assert(IERC20(pair).allowance(address(this), router) == 0);

            IERC20(pairAsset).safeTransfer(owner(), IERC20(pairAsset).balanceOf(address(this)));
            IERC20(IZivoeGlobals_OCL_ZVE(GBL).ZVE()).safeTransfer(owner(), IERC20(IZivoeGlobals_OCL_ZVE(GBL).ZVE()).balanceOf(address(this)));
            basis = 0;
        }
        else {
            IERC20(asset).safeTransfer(owner(), IERC20(asset).balanceOf(address(this)));
        }
    }

    /// @notice This burns LP tokens from the $ZVE/pairAsset pool and returns them to the DAO.
    /// @param  asset The asset to burn.
    /// @param  amount The amount of "asset" to burn.
    /// @param  data Accompanying transaction data.
    function pullFromLockerPartial(address asset, uint256 amount, bytes calldata data) external override onlyOwner nonReentrant {
        address pair = IFactory_OCL_ZVE(factory).getPair(pairAsset, IZivoeGlobals_OCL_ZVE(GBL).ZVE());
        
        // "pair" represents the liquidity pool token (minted, burned).
        // "pairAsset" represents the stablecoin paired against $ZVE.
        if (asset == pair) {
            IERC20(pair).safeApprove(router, amount);
            IRouter_OCL_ZVE(router).removeLiquidity(
                pairAsset, IZivoeGlobals_OCL_ZVE(GBL).ZVE(), amount, 0, 0, address(this), block.timestamp + 14 days
            );
            assert(IERC20(pair).allowance(address(this), router) == 0);
            
            IERC20(pairAsset).safeTransfer(owner(), IERC20(pairAsset).balanceOf(address(this)));
            IERC20(IZivoeGlobals_OCL_ZVE(GBL).ZVE()).safeTransfer(owner(), IERC20(IZivoeGlobals_OCL_ZVE(GBL).ZVE()).balanceOf(address(this)));
            (basis,) = fetchBasis();
        }
        else {
            IERC20(asset).safeTransfer(owner(), amount);
        }
    }

    /// @notice Updates the compounding rate of this contract.
    /// @dev    A value of 2,000 represent 20% of the earnings stays in this contract, compounding.
    /// @param  _compoundingRateBIPS The new compounding rate value.
    function updateCompoundingRateBIPS(uint256 _compoundingRateBIPS) external {
        require(
            _msgSender() == IZivoeGlobals_OCL_ZVE(GBL).TLC(), 
            "OCL_ZVE::updateCompoundingRateBIPS() _msgSender() != IZivoeGlobals_OCL_ZVE(GBL).TLC()"
        );
        require(_compoundingRateBIPS <= BIPS, "OCL_ZVE::updateCompoundingRateBIPS() ratio > BIPS");

        emit UpdatedCompoundingRateBIPS(compoundingRateBIPS, _compoundingRateBIPS);
        compoundingRateBIPS = _compoundingRateBIPS;
    }

    /// @notice This forwards yield in excess of the basis.
    function forwardYield() external {
        if (IZivoeGlobals_OCL_ZVE(GBL).isKeeper(_msgSender())) {
            require(
                block.timestamp > nextYieldDistribution - 12 hours, 
                "OCL_ZVE::forwardYield() block.timestamp <= nextYieldDistribution - 12 hours"
            );
        }
        else {
            require(block.timestamp > nextYieldDistribution, "OCL_ZVE::forwardYield() block.timestamp <= nextYieldDistribution");
        }

        (uint256 amount, uint256 lp) = fetchBasis();
        require(amount > basis, "OCL_ZVE::forwardYield() amount <= basis");
        nextYieldDistribution += 30 days;
        _forwardYield(amount, lp);
    }

    /// @notice This forwards yield to the YDL in the form of pairAsset.
    /// @dev    Private function, only callable via forwardYield().
    /// @param  amount Current pairAsset harvestable.
    /// @param  lp Current ZVE/pairAsset LP tokens.
    function _forwardYield(uint256 amount, uint256 lp) private nonReentrant {
        uint256 lpBurnable = (amount - basis) * lp / amount * compoundingRateBIPS / BIPS;
        address pair = IFactory_OCL_ZVE
        (factory).getPair(pairAsset, IZivoeGlobals_OCL_ZVE(GBL).ZVE());
        IERC20(pair).safeApprove(router, lpBurnable);
        IRouter_OCL_ZVE(router).removeLiquidity(
            pairAsset, IZivoeGlobals_OCL_ZVE(GBL).ZVE(), lpBurnable, 0, 0, address(this), block.timestamp + 14 days
        );
        assert(IERC20(pair).allowance(address(this), router) == 0);
        if (pairAsset != IZivoeYDL_OCL_ZVE(IZivoeGlobals_OCL_ZVE(GBL).YDL()).distributedAsset()) {
            IERC20(pairAsset).safeTransferFrom(_msgSender(), address(OCT_YDL), IERC20(pairAsset).balanceOf(address(this)));
        }
        else {
            emit YieldForwarded(pairAsset, IERC20(pairAsset).balanceOf(address(this)));
            IERC20(pairAsset).safeTransfer(IZivoeGlobals_OCL_ZVE(GBL).YDL(), IERC20(pairAsset).balanceOf(address(this)));
        }
        IERC20(IZivoeGlobals_OCL_ZVE(GBL).ZVE()).safeTransfer(owner(), IERC20(IZivoeGlobals_OCL_ZVE(GBL).ZVE()).balanceOf(address(this)));
        (basis,) = fetchBasis();
    }

    /// @notice Returns amount of pairAsset redeemable with current LP position.
    /// @dev    The withdrawal mechanism is ZVE/pairAsset_LP => pairAsset.
    /// @return amount Current pairAsset harvestable.
    /// @return lp Current ZVE/pairAsset LP tokens.
    function fetchBasis() public view returns (uint256 amount, uint256 lp) {
        address pool = IFactory_OCL_ZVE(factory).getPair(pairAsset, IZivoeGlobals_OCL_ZVE(GBL).ZVE());
        uint256 pairAssetBalance = IERC20(pairAsset).balanceOf(pool);
        uint256 poolTotalSupply = IERC20(pool).totalSupply();
        lp = IERC20(pool).balanceOf(address(this));
        amount = lp * pairAssetBalance / poolTotalSupply;
    }   
}