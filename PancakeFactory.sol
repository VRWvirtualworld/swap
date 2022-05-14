/**
 *Submitted for verification at BscScan.com on 2020-09-19
*/
// contract 0x989511E7aFcB0cFec605fd9c3707780C27091Bb8
pragma solidity =0.5.16;


interface IPancakeFactory {
    event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    function feeTo() external view returns (address);
    function feeToSetter() external view returns (address);

    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function allPairs(uint) external view returns (address pair);
    function allPairsLength() external view returns (uint);

    function createPair(address tokenA, address tokenB, uint initPrice, uint lowPrice, uint floatPrice) external returns (address pair);

    function setFeeTo(address) external;
    function setFeeToSetter(address) external;
}

interface IPancakePair {
    event Swap(address indexed sender, address tokenA, address tokenB, uint coinNum, uint prePrice, uint nowPrice);
    event RemovePair(address indexed sender, address token0, address token1, uint balance0, uint balance1, address to);

    function MINIMUM_LIQUIDITY() external pure returns (uint);
    function factory() external view returns (address);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function initPrice() external view returns (uint);
    function lowPrice() external view returns (uint);
    function nowPrice() external view returns (uint);
    function floatPrice() external view returns (uint);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(address tokenA, address tokenB, uint256 coinNum, address to) external;
    function update() external;
    // function removePair(address to) external returns (uint amount0, uint amount1);
    function initialize(address _token0, address _token1, uint _initPrice, uint _lowPrice, uint _floatPrice) external;
}

// a library for performing overflow-safe math, courtesy of DappHub (https://github.com/dapphub/ds-math)
library SafeMath {
    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x, 'ds-math-add-overflow');
    }

    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x, 'ds-math-sub-underflow');
    }

    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x, 'ds-math-mul-overflow');
    }
}

// a library for performing various math operations
library Math {
    function min(uint x, uint y) internal pure returns (uint z) {
        z = x < y ? x : y;
    }

    // babylonian method (https://en.wikipedia.org/wiki/Methods_of_computing_square_roots#Babylonian_method)
    function sqrt(uint y) internal pure returns (uint z) {
        if (y > 3) {
            z = y;
            uint x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
}

// a library for handling binary fixed point numbers (https://en.wikipedia.org/wiki/Q_(number_format))
// range: [0, 2**112 - 1]
// resolution: 1 / 2**112
library UQ112x112 {
    uint224 constant Q112 = 2**112;

    // encode a uint112 as a UQ112x112
    function encode(uint112 y) internal pure returns (uint224 z) {
        z = uint224(y) * Q112; // never overflows
    }

    // divide a UQ112x112 by a uint112, returning a UQ112x112
    function uqdiv(uint224 x, uint112 y) internal pure returns (uint224 z) {
        z = x / uint224(y);
    }
}

interface IERC20 {
    event Approval(address indexed owner, address indexed spender, uint value);
    event Transfer(address indexed from, address indexed to, uint value);

    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint);
    function balanceOf(address owner) external view returns (uint);
    function allowance(address owner, address spender) external view returns (uint);

    function approve(address spender, uint value) external returns (bool);
    function transfer(address to, uint value) external returns (bool);
    function transferFrom(address from, address to, uint value) external returns (bool);
}

interface IPancakeCallee {
    function pancakeCall(address sender, uint amount0, uint amount1, bytes calldata data) external;
}

contract PancakePair is IPancakePair {
    using SafeMath  for uint;
    using UQ112x112 for uint224;

    uint public constant MINIMUM_LIQUIDITY = 10**3;
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes('transfer(address,uint256)')));

    address public factory;
    address public token0;
    address public token1;

    uint112 private reserve0;           // uses single storage slot, accessible via getReserves
    uint112 private reserve1;           // uses single storage slot, accessible via getReserves
    uint32  private blockTimestampLast; // uses single storage slot, accessible via getReserves

    uint public nowPrice;
    uint public initPrice;
    uint public lowPrice;
    uint public floatPrice;
    address public feeAddress;
    uint256 public allfee;
    uint256 public maxfee = 1000000000000000000000;
    uint256 public curfee = 30; 
    //address public usdtAddress = address(0xF789506206D50e9D31e0EDaB289A89b8095D1Ec5);
    //address public usdtAddress = address(0x2AF1F68531B093f6bF1266BF5fD81eB1C3f5F05a);
    address public usdtAddress = address(0x55d398326f99059fF775485246999027B3197955); 

    uint private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, 'Pancake: LOCKED');
        unlocked = 0;
        _;
        unlocked = 1;
    }

    function getReserves() public view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    function _safeTransfer(address token, address to, uint value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'Pancake: TRANSFER_FAILED');
    }

    event Swap(address indexed sender, address tokenIn, address tokenOut, uint amountIn, uint amountOut, uint prePrice, uint nowPrice);
    event RemovePair(address indexed sender, address token0, address token1, uint balance0, uint balance1, address to);

    constructor() public {
        factory = msg.sender;
    }

    function initialize(address _token0, address _token1, uint _initPrice, uint _lowPrice, uint _floatPrice) external {
        require(msg.sender == factory, 'Pancake: FORBIDDEN'); // sufficient check
        token0 = _token0;
        token1 = _token1;
        nowPrice = _initPrice;
        initPrice = _initPrice;
        lowPrice = _lowPrice;
        floatPrice = _floatPrice;
        feeAddress = IPancakeFactory(factory).feeTo();
    }

    // update reserves and, on the first call per block, price accumulators
    function _update(uint balance0, uint balance1, uint112 _reserve0, uint112 _reserve1) private {
        require(balance0 <= uint112(-1) && balance1 <= uint112(-1), 'Pancake: OVERFLOW');
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function update() external lock {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        address _token0 = token0;                                // gas savings
        address _token1 = token1;                                // gas savings
        uint balance0 = IERC20(_token0).balanceOf(address(this));
        uint balance1 = IERC20(_token1).balanceOf(address(this));

        _update(balance0, balance1, _reserve0, _reserve1);
        //emit Burn(msg.sender, amount0, amount1, to);
    }

    // function removePair(address to) external lock returns (uint amount0, uint amount1) {
    //     (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
    //     address _token0 = token0;                                // gas savings
    //     address _token1 = token1;                                // gas savings
    //     uint balance0 = IERC20(_token0).balanceOf(address(this));
    //     uint balance1 = IERC20(_token1).balanceOf(address(this));
    //     if(balance0 > 0) _safeTransfer(_token0, to, balance0);
    //     if(balance1 > 0) _safeTransfer(_token1, to, balance1);
    //     balance0 = IERC20(_token0).balanceOf(address(this));
    //     balance1 = IERC20(_token1).balanceOf(address(this));

    //     _update(balance0, balance1, _reserve0, _reserve1);
    //     emit RemovePair(msg.sender, token0, token1, balance0, balance1, to);
    // }

    function swap(address tokenA, address tokenB, uint256 coinNum, address to) external lock {
        uint256 usdtDecimal = IERC20(usdtAddress).decimals();
        if (tokenA == usdtAddress) {
            uint256 decimal = IERC20(tokenB).decimals();

            uint256 realNum = subFee(coinNum);
            uint getCoinNum = getGen1Y2C(nowPrice, floatPrice, realNum, decimal);
            uint256 changePrice = getStep(getCoinNum, decimal);
            uint256 prePrice = nowPrice;
            nowPrice += changePrice;

            IERC20(tokenB).transfer(to, getCoinNum);
            emit Swap(to, tokenA, tokenB, coinNum, getCoinNum, prePrice, nowPrice);
        } else if (tokenB == usdtAddress) {
            (uint256 baseNum, uint256 changePrice) = getBaseNumAndStep(tokenB, coinNum, usdtDecimal, 1);
            uint256 prePrice = nowPrice;
            nowPrice -= changePrice;
            require(nowPrice >= lowPrice);

            uint256 afterfee = subFee(baseNum);
            IERC20(usdtAddress).transfer(to, afterfee);

            emit Swap(to, tokenA, tokenB, coinNum, afterfee, prePrice, nowPrice);
        }
        if (allfee > maxfee) {
            sendFee();
        }
    }

    function subFee(uint256 all) private returns(uint256) {
        uint256 cfee = all * curfee / 10000;
        allfee += cfee;
        return all - cfee;
    }

    function sendFee() public {
        IERC20(usdtAddress).transfer(feeAddress, allfee);
        allfee = 0;
    }

    // coin addr & coin num & kind = 0 = buy, kind = 1 = sell
    function getBaseNumAndStep(address addr, uint256 coinNum, uint256 decimal, uint256 kind) 
    private view returns(uint256, uint256) {
        uint256 pStep = getStep(coinNum, decimal);
        uint256 pAvg;
        if (kind == 1) {pAvg = nowPrice - (pStep / 2);
        } else {pAvg = nowPrice + (pStep  / 2);}
        uint256 ttsAmount = coinNum * pAvg / 10 ** decimal;
        return (ttsAmount, pStep);
    }

    function getStep(uint256 coinNum, uint256 decimal) private view returns(uint256) {
        return coinNum * floatPrice / 10 ** decimal;
    }

    function getGen1Y2C(uint256 p, uint256 f, uint256 u, uint256 dot) 
    private pure returns(uint256) {
        uint256 gen2 = getGen2(4 * (p**2) + 8 * f * u);
        if (gen2 <= 2 * p) { return 0; }
        return (gen2 - 2 * p) * (10 ** dot) / (2 * f);
    }

    function getGen2(uint256 x) private pure returns(uint256) {
        uint256 z = (x+1)/2; uint256 y = x;
        while(z < y) {y = z; z = (x/z+z)/2;}
        return y;
    }
}

contract PancakeFactory is IPancakeFactory {
    bytes32 public INIT_CODE_PAIR_HASH = keccak256( abi.encodePacked(type(PancakePair).creationCode) );

    address public feeTo;
    address public feeToSetter;

    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    event PairCreated(address indexed token0, address indexed token1, address pair, uint);
    event InitCodePairHash(bytes32 hash);

    constructor(address _feeToSetter) public {
        feeToSetter = _feeToSetter;
        feeTo = _feeToSetter;
        emit InitCodePairHash(INIT_CODE_PAIR_HASH);
    }

    function allPairsLength() external view returns (uint) {
        return allPairs.length;
    }

    function createPair(address tokenA, address tokenB, uint initPrice, uint lowPrice, uint floatPrice) external returns (address pair) {
        require(tokenA != tokenB, 'Pancake: IDENTICAL_ADDRESSES');
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'Pancake: ZERO_ADDRESS');
        require(getPair[token0][token1] == address(0), 'Pancake: PAIR_EXISTS'); // single check is sufficient
        bytes memory bytecode = type(PancakePair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        IPancakePair(pair).initialize(token0, token1, initPrice, lowPrice, floatPrice);
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // populate mapping in the reverse direction
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    function setFeeTo(address _feeTo) external {
        require(msg.sender == feeToSetter, 'Pancake: FORBIDDEN');
        feeTo = _feeTo;
    }

    function setFeeToSetter(address _feeToSetter) external {
        require(msg.sender == feeToSetter, 'Pancake: FORBIDDEN');
        feeToSetter = _feeToSetter;
    }
}