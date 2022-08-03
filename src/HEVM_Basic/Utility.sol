// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.6;


// User imports.
import "../users/Admin.sol";
import "../users/Blackhat.sol";
import "../users/Lender.sol";
import "../users/TrancheLiquidityProvider.sol";


// Core imports.
import "../ZivoeAmplifier.sol";
import "../ZivoeDAO.sol";
import "../ZivoeITO.sol";
import "../ZivoeToken.sol";
import "../ZivoeTrancheToken.sol";
import "../ZivoeVesting.sol";
import "../ZivoeYieldDistributionLocker.sol";

// Locker imports.
import "../ZivoeOCCLockers/OCC_Balloon_FRAX.sol";

// Non-core imports.
import { MultiRewards } from "../MultiRewards.sol";


// Test imports.
import "../../lib/forge-std/src/test.sol";


// Interface imports.
interface Hevm {
    function warp(uint256) external;
    function store(address,bytes32,bytes32) external;
}

interface User {
    function approve(address, uint256) external;
}


// Core test / "utility" contract.
contract Utility is DSTest {

    Hevm hevm;

    /***********************/
    /*** Protocol Actors ***/
    /***********************/
    Admin                         gov;
    Admin                         god;
    Blackhat                      bob;
    Lender                        len;
    TrancheLiquidityProvider      tom;
    TrancheLiquidityProvider      sam;

    /**********************************/
    /*** Mainnet Contract Addresses ***/
    /**********************************/
    address constant DAI   = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant USDC  = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant USDT  = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant FRAX  = 0x853d955aCEf822Db058eb8505911ED77F175b99e;
    address constant WETH  = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant WBTC  = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address constant TUSD  = 0x0000000000085d4780B73119b644AE5ecd22b376;

    IERC20 constant dai  = IERC20(DAI);
    IERC20 constant usdc = IERC20(USDC);
    IERC20 constant weth = IERC20(WETH);
    IERC20 constant wbtc = IERC20(WBTC);

    address constant UNISWAP_V2_ROUTER_02 = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D; // Uniswap V2 Router
    address constant UNISWAP_V2_FACTORY   = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f; // Uniswap V2 factory.

    
    /****************************/
    /*** Zivoe Core Contracts ***/
    /****************************/
    ZivoeAmplifier                  AMP;
    ZivoeToken                      ZVE;
    ZivoeDAO                        DAO;
    ZivoeITO                        ITO;
    ZivoeVesting                    VST;
    ZivoeTrancheToken               zSTT;
    ZivoeTrancheToken               zJTT;
    ZivoeYieldDistributionLocker    YDL;
    
    /*********************************/
    /*** Zivoe Periphery Contracts ***/
    /*********************************/
    MultiRewards    stJTT;
    MultiRewards    stSTT;
    MultiRewards    stZVE;

    OCC_Balloon_FRAX            OCC_B_Frax;

    /*****************/
    /*** Constants ***/
    /*****************/
    uint256 constant USD = 10 ** 6;  // USDC precision decimals
    uint256 constant BTC = 10 ** 8;  // WBTC precision decimals
    uint256 constant WAD = 10 ** 18;
    uint256 constant RAY = 10 ** 27;

    /*****************/
    /*** Utilities ***/
    /*****************/
    struct Token {
        address addr; // ERC20 Mainnet address
        uint256 slot; // Balance storage slot
        address orcl; // Chainlink oracle address
    }
 
    mapping (bytes32 => Token) tokens;

    struct TestObj {
        uint256 pre;
        uint256 post;
    }

    event Debug(string, uint256);
    event Debug(string, address);
    event Debug(string, bool);

    constructor() { hevm = Hevm(address(bytes20(uint160(uint256(keccak256("hevm cheat code")))))); }

    /**************************************/
    /*** Actor/Multisig Setup Functions ***/
    /**************************************/
    function createActors() public { 
        god = new Admin();
        gov = new Admin();
        bob = new Blackhat();
        len = new Lender();
        tom = new TrancheLiquidityProvider();
        sam = new TrancheLiquidityProvider();
    }

    /******************************/
    /*** Test Utility Functions ***/
    /******************************/
    function setUpTokens() public {

        tokens["USDC"].addr = USDC;
        tokens["USDC"].slot = 9;

        tokens["DAI"].addr = DAI;
        tokens["DAI"].slot = 2;

        tokens["FRAX"].addr = FRAX;
        tokens["FRAX"].slot = 0;

        tokens["USDT"].addr = USDT;
        tokens["USDT"].slot = 2;

        tokens["WETH"].addr = WETH;
        tokens["WETH"].slot = 3;

        tokens["WBTC"].addr = WBTC;
        tokens["WBTC"].slot = 0;
    }

    function setUpFundedDAO() public {

        // Run initial setup functions.
        createActors();
        setUpTokens();

        // (1) Deploy ZivoeToken.sol

        ZVE = new ZivoeToken(
            10000000 ether,   // 10 million supply
            18,
            'Zivoe',
            'ZVE',
            address(god)
        );

        // (2) Deploy ZivoeDAO.sol
        // (3) Deploy ZivoeVesting.sol
        // (x) Deploy ZivoeYieldDistributionLocker.sol

        DAO = new ZivoeDAO(address(god));
        VST = new ZivoeVesting(address(ZVE));

        // (5) Deploy "SeniorTrancheToken" through ZivoeTrancheToken.sol
        // (6) Deploy "JuniorTrancheToken" through ZivoeTrancheToken.sol

        zSTT = new ZivoeTrancheToken(
            18,
            'SeniorTrancheToken',
            'zSTT',
            address(god)
        );

        zJTT = new ZivoeTrancheToken(
            18,
            'JuniorTrancheToken',
            'zJTT',
            address(god)
        );

        // (7) Deploy ZivoeITO.sol

        ITO = new ZivoeITO(
            block.timestamp + 1000 seconds,
            block.timestamp + 5000 seconds,
            address(DAO),
            address(zSTT),
            address(zJTT),
            address(ZVE)
        );

        // (8)  Transfer 50% $ZVE to ZivoeDAO.sol
        // (9)  Transfer 40% $ZVE to ZivoeVesting.sol
        // (10) Transfer 10% $ZVE to ZivoeITO.sol

        god.transferToken(address(ZVE), address(DAO), 5000000 ether);   // 50% of $ZVE allocated to DAO
        god.transferToken(address(ZVE), address(VST), 4000000 ether);   // 40% of $ZVE allocated to Vesting
        god.transferToken(address(ZVE), address(ITO), 1000000 ether);   // 10% of $ZVE allocated to ITO

        // (11/12) Give ZivoeITO.sol minterRole() status over zJTT and zSTT for minting either during ITO

        god.try_changeMinterRole(address(zJTT), address(ITO), true);
        god.try_changeMinterRole(address(zSTT), address(ITO), true);

        // (13) Deposit 1mm of each DAI, FRAX, USDC, USDT into SeniorTranche
        // (14) Deposit 1mm of each DAI, FRAX, USDC, USDT into JuniorTranche

        simulateDepositsCoreUtility(1000000, 1000000);

        // // Initialize and whitelist MyAAVELocker.
    
        // MyAAVELocker = new OCY_AAVE(address(DAO), address(YDL));
        // god.try_modifyLockerWhitelist(address(DAO), address(MyAAVELocker), true);

        // (15 / 16 / 17) Deploy the three staking (RDT) contracts.

        stSTT = new MultiRewards(
            address(zSTT),
            address(god)
        );

        stJTT = new MultiRewards(
            address(zJTT),
            address(god)
        );

        stZVE = new MultiRewards(
            address(ZVE),
            address(god)
        );

        YDL = new ZivoeYieldDistributionLocker(
            address(gov),
            address(stSTT),
            address(stJTT),
            address(stZVE),
            address(god)    // TODO: Add in RET
        );

        god.try_addReward(address(stSTT), FRAX, address(YDL), 1 days);
        god.try_addReward(address(stJTT), FRAX, address(YDL), 1 days);
        god.try_addReward(address(stZVE), FRAX, address(YDL), 1 days);
    }

    function stakeTokens() public {

        // "tom" added to Junior tranche.
        tom.try_approveToken(address(zJTT), address(stJTT), IERC20(address(zJTT)).balanceOf(address(tom)));
        tom.try_approveToken(address(ZVE),  address(stZVE), IERC20(address(ZVE)).balanceOf(address(tom)));
        tom.try_stake(address(stJTT), IERC20(address(zJTT)).balanceOf(address(tom)));
        tom.try_stake(address(stZVE), IERC20(address(ZVE)).balanceOf(address(tom)));

        // "sam" added to Junior tranche.
        sam.try_approveToken(address(zSTT), address(stSTT), IERC20(address(zSTT)).balanceOf(address(sam)));
        sam.try_approveToken(address(ZVE),  address(stZVE), IERC20(address(ZVE)).balanceOf(address(sam)));
        sam.try_stake(address(stSTT), IERC20(address(zSTT)).balanceOf(address(sam)));
        sam.try_stake(address(stZVE), IERC20(address(ZVE)).balanceOf(address(sam)));
    }

    
    function fundAndRepayBalloonLoan() public {

        // Initialize and whitelist OCC_B_Frax locker.
        OCC_B_Frax = new OCC_Balloon_FRAX(address(DAO), address(YDL), address(gov));
        god.try_modifyLockerWhitelist(address(DAO), address(OCC_B_Frax), true);

        // Create new loan request and fund it.
        uint256 id = OCC_B_Frax.counterID();

        assert(bob.try_requestLoan(
            address(OCC_B_Frax),
            10000 ether,
            3000,
            1500,
            12,
            86400 * 14
        ));


        // Add more FRAX into contract.
        assert(god.try_push(address(DAO), address(OCC_B_Frax), address(USDC), 500000 * 10**6));

        // Fund loan (5 days later).
        hevm.warp(block.timestamp + 5 days);
        assert(gov.try_fundLoan(address(OCC_B_Frax), id));

        // Can't make payment on a Repaid loan (simulate many payments to end to reach Repaid state first).
        assert(bob.try_approveToken(address(FRAX), address(OCC_B_Frax), 20000 ether));

        mint("FRAX", address(bob), 20000 ether);

        // 12 payments.
        assert(bob.try_makePayment(address(OCC_B_Frax), id));
        assert(bob.try_makePayment(address(OCC_B_Frax), id));
        assert(bob.try_makePayment(address(OCC_B_Frax), id));
        assert(bob.try_makePayment(address(OCC_B_Frax), id));
        assert(bob.try_makePayment(address(OCC_B_Frax), id));
        
        assert(bob.try_makePayment(address(OCC_B_Frax), id));
        assert(bob.try_makePayment(address(OCC_B_Frax), id));
        assert(bob.try_makePayment(address(OCC_B_Frax), id));
        assert(bob.try_makePayment(address(OCC_B_Frax), id));
        assert(bob.try_makePayment(address(OCC_B_Frax), id));
        
        assert(bob.try_makePayment(address(OCC_B_Frax), id));
        assert(bob.try_makePayment(address(OCC_B_Frax), id));

    }

    // Simulates deposits for a junior and a senior tranche depositor.

    function simulateDepositsCoreUtility(uint256 seniorDeposit, uint256 juniorDeposit) public {

        // Warp to ITO start unix.
        hevm.warp(ITO.start());

        // ------------------------
        // "sam" => depositSenior()
        // ------------------------

        mint("DAI",  address(sam), seniorDeposit * 1 ether);
        mint("FRAX", address(sam), seniorDeposit * 1 ether);
        mint("USDC", address(sam), seniorDeposit * USD);
        mint("USDT", address(sam), seniorDeposit * USD);

        assert(sam.try_approveToken(DAI,  address(ITO), seniorDeposit * 1 ether));
        assert(sam.try_approveToken(FRAX, address(ITO), seniorDeposit * 1 ether));
        assert(sam.try_approveToken(USDC, address(ITO), seniorDeposit * USD));
        assert(sam.try_approveToken(USDT, address(ITO), seniorDeposit * USD));

        assert(sam.try_depositSenior(address(ITO), seniorDeposit * 1 ether, address(DAI)));
        assert(sam.try_depositSenior(address(ITO), seniorDeposit * 1 ether, address(FRAX)));
        assert(sam.try_depositSenior(address(ITO), seniorDeposit * USD, address(USDC)));
        assert(sam.try_depositSenior(address(ITO), seniorDeposit * USD, address(USDT)));

        // ------------------------
        // "tom" => depositJunior()
        // ------------------------

        mint("DAI",  address(tom), juniorDeposit * 1 ether);
        mint("FRAX", address(tom), juniorDeposit * 1 ether);
        mint("USDC", address(tom), juniorDeposit * USD);
        mint("USDT", address(tom), juniorDeposit * USD);

        assert(tom.try_approveToken(DAI,  address(ITO), juniorDeposit * 1 ether));
        assert(tom.try_approveToken(FRAX, address(ITO), juniorDeposit * 1 ether));
        assert(tom.try_approveToken(USDC, address(ITO), juniorDeposit * USD));
        assert(tom.try_approveToken(USDT, address(ITO), juniorDeposit * USD));

        assert(tom.try_depositJunior(address(ITO), juniorDeposit * 1 ether, address(DAI)));
        assert(tom.try_depositJunior(address(ITO), juniorDeposit * 1 ether, address(FRAX)));
        assert(tom.try_depositJunior(address(ITO), juniorDeposit * USD, address(USDC)));
        assert(tom.try_depositJunior(address(ITO), juniorDeposit * USD, address(USDT)));

        // Warp to end of ITO, call migrateDeposits() to ensure ZivoeDAO.sol receives capital.
        hevm.warp(ITO.end() + 1);
        ITO.migrateDeposits();

        // Have "tom" and "sam" claim their tokens from the contract.
        tom.try_claim(address(ITO));
        sam.try_claim(address(ITO));
    }

    // Manipulate mainnet ERC20 balance
    function mint(bytes32 symbol, address account, uint256 amt) public {
        address addr = tokens[symbol].addr;
        uint256 slot  = tokens[symbol].slot;
        uint256 bal = IERC20(addr).balanceOf(account);

        hevm.store(
            addr,
            keccak256(abi.encode(account, slot)), // Mint tokens
            bytes32(bal + amt)
        );

        assertEq(IERC20(addr).balanceOf(account), bal + amt); // Assert new balance
    }

    // Verify equality within accuracy decimals
    function withinPrecision(uint256 val0, uint256 val1, uint256 accuracy) public {
        uint256 diff  = val0 > val1 ? val0 - val1 : val1 - val0;
        if (diff == 0) return;

        uint256 denominator = val0 == 0 ? val1 : val0;
        bool check = ((diff * RAY) / denominator) < (RAY / 10 ** accuracy);

        if (!check){
            emit log_named_uint("Error: approx a == b not satisfied, accuracy digits ", accuracy);
            emit log_named_uint("  Expected", val0);
            emit log_named_uint("    Actual", val1);
            fail();
        }
    }

    // Verify equality within difference
    function withinDiff(uint256 val0, uint256 val1, uint256 expectedDiff) public {
        uint256 actualDiff = val0 > val1 ? val0 - val1 : val1 - val0;
        bool check = actualDiff <= expectedDiff;

        if (!check) {
            emit log_named_uint("Error: approx a == b not satisfied, accuracy difference ", expectedDiff);
            emit log_named_uint("  Expected", val0);
            emit log_named_uint("    Actual", val1);
            fail();
        }
    }

    function constrictToRange(uint256 val, uint256 min, uint256 max) public pure returns (uint256) {
        return constrictToRange(val, min, max, false);
    }

    function constrictToRange(uint256 val, uint256 min, uint256 max, bool nonZero) public pure returns (uint256) {
        if      (val == 0 && !nonZero) return 0;
        else if (max == min)           return max;
        else                           return val % (max - min) + min;
    }
    
}