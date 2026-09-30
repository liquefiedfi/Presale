// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./PresaleLAERO.sol";

/// @title Presale
/// @notice Sells pLAERO for AERO at a fixed bonus; PresaleClaim later settles it 1:1 for LAERO.
///         100 AERO at a 9% bonus buys 109 pLAERO.
/// @dev - Deploys its own pLAERO and is its only minter, so nothing mints outside the presale.
///      - Deposits go straight to `treasury`; this contract holds no AERO.
///      - Cap, bonus and dates are fixed at deployment. The presale closes when `presaleEnd` passes,
///        `cap` is reached, or the owner ends it. Closing is one-way; PresaleClaim relies on it.
///      - A deposit is filled in full or reverts, and mints a known amount: there is no price.
///      - A referral adds 1% for the buyer and is recorded in `Deposited`; referrer rewards are
///        calculated from those events and airdropped in LAERO after launch.
contract Presale is Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice 100% in basis points.
    uint16 public constant bps = 10_000;
    /// @notice Extra for a buyer who uses a referral. 100 = 1%.
    uint16 public constant referredBuyerBps = 100;
    /// @notice Upper bound on `bonusBps`, so a typo cannot deploy a presale that mints far too much.
    uint16 public constant maxBonusBps = 2_000;

    /// @notice What buyers pay with: AERO.
    IERC20 public immutable paymentToken;
    /// @notice Where deposits go: the Safe.
    address public immutable treasury;
    /// @notice What buyers receive: the pLAERO this presale deployed.
    PresaleLAERO public immutable receiptToken;

    /// @notice AERO the presale accepts.
    uint128 public immutable cap;
    /// @notice The bonus in bps. 900 = 9%.
    uint16 public immutable bonusBps;
    /// @notice When deposits open.
    uint64 public immutable presaleStart;
    /// @notice When the presale closes, unless it closes earlier.
    uint64 public immutable presaleEnd;

    /// @notice AERO accepted so far.
    uint128 public raised;
    /// @notice When the owner ended the presale early, or zero.
    uint64 public endedAt;

    /// @notice Every purchase, with its referrer (zero for none).
    event Deposited(address indexed buyer, address indexed referrer, uint256 paid, uint256 received);
    event PresaleEnded(uint64 at);
    event Swept(address indexed token, address indexed to, uint256 amount);

    error NotStarted();
    error PresaleOver();
    error ExceedsRemaining();
    error BadSchedule();
    error BadCap();
    error BonusTooHigh();
    error ZeroAddress();
    error BadTreasury();
    error ZeroAmount();
    error NothingToSweep();
    error RenounceDisabled();

    /// @param _paymentToken AERO.
    /// @param _treasury Where deposits go; the Safe.
    /// @param _owner The Safe; can only end the presale early and sweep.
    /// @param _cap AERO the presale accepts.
    /// @param _bonusBps The bonus in bps; at most `maxBonusBps`.
    /// @param _presaleStart When deposits open; a past time opens the presale at once.
    /// @param _presaleEnd When the presale closes; must be in the future.
    /// @param _receiptName "Presale Liquefied AERO" on mainnet.
    /// @param _receiptSymbol "pLAERO" on mainnet.
    constructor(
        address _paymentToken,
        address _treasury,
        address _owner,
        uint128 _cap,
        uint16 _bonusBps,
        uint64 _presaleStart,
        uint64 _presaleEnd,
        string memory _receiptName,
        string memory _receiptSymbol
    ) Ownable(_owner) {
        if (_paymentToken == address(0) || _treasury == address(0)) revert ZeroAddress();
        if (_treasury == address(this)) revert BadTreasury();
        if (_cap == 0) revert BadCap();
        if (_bonusBps > maxBonusBps) revert BonusTooHigh();
        if (_presaleEnd <= _presaleStart || _presaleEnd <= block.timestamp) revert BadSchedule();

        paymentToken = IERC20(_paymentToken);
        treasury = _treasury;
        cap = _cap;
        bonusBps = _bonusBps;
        presaleStart = _presaleStart;
        presaleEnd = _presaleEnd;
        receiptToken = new PresaleLAERO(_receiptName, _receiptSymbol, address(this));
    }

    /// @notice Buy pLAERO at the presale's bonus.
    /// @param amount AERO to spend. More than `remaining()` reverts.
    /// @param referrer The referrer, or the zero address. Adds 1% unless it is the buyer.
    function deposit(uint256 amount, address referrer) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (block.timestamp < presaleStart) revert NotStarted();
        if (isClosed()) revert PresaleOver();
        if (amount > remaining()) revert ExceedsRemaining();

        uint256 received = _received(amount, referrer, msg.sender);
        raised += uint128(amount);
        paymentToken.safeTransferFrom(msg.sender, treasury, amount);
        receiptToken.mint(msg.sender, received);
        emit Deposited(msg.sender, referrer, amount, received);
    }

    /// @notice Close the presale for good. Owner only. Before the start, this cancels it.
    function endPresale() external onlyOwner {
        if (isClosed()) revert PresaleOver();
        endedAt = uint64(block.timestamp);
        emit PresaleEnded(endedAt);
    }

    /// @notice Recover a token sent here by mistake, in full. Owner only.
    function sweep(IERC20 token, address to) external onlyOwner {
        uint256 balance = token.balanceOf(address(this));
        if (balance == 0) revert NothingToSweep();
        token.safeTransfer(to, balance);
        emit Swept(address(token), to, balance);
    }

    /// @notice Disabled: only the owner can stop the presale early.
    function renounceOwnership() public pure override {
        revert RenounceDisabled();
    }

    /// @notice The largest deposit the presale still accepts.
    function remaining() public view returns (uint256) {
        return isClosed() ? 0 : cap - raised;
    }

    /// @notice True once the presale has closed. Never reverts to false.
    function isClosed() public view returns (bool) {
        return endedAt != 0 || block.timestamp >= presaleEnd || raised >= cap;
    }

    /// @notice True while deposits are possible.
    function isOpen() external view returns (bool) {
        return block.timestamp >= presaleStart && !isClosed();
    }

    /// @notice The pLAERO a deposit of `amount` by `buyer` would mint now, or zero if it would
    ///         revert. Pass the zero address for no referrer.
    function quote(uint256 amount, address referrer, address buyer) external view returns (uint256) {
        if (amount == 0 || amount > remaining() || block.timestamp < presaleStart) return 0;
        return _received(amount, referrer, buyer);
    }

    /// @dev The bonus, plus 1% for a referrer who is not the buyer. Rounds down.
    function _received(uint256 amount, address referrer, address buyer) internal view returns (uint256) {
        uint256 referral = referrer != address(0) && referrer != buyer ? referredBuyerBps : 0;
        return (amount * (bps + bonusBps + referral)) / bps;
    }
}
