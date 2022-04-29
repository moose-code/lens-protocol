// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.10;

import {IFollowModule} from '../../../interfaces/IFollowModule.sol';
import {ILensHub} from '../../../interfaces/ILensHub.sol';
import {Errors} from '../../../libraries/Errors.sol';
import {FeeModuleBase} from '../FeeModuleBase.sol';
import {ModuleBase} from '../ModuleBase.sol';
import {FollowValidatorFollowModuleBase} from './FollowValidatorFollowModuleBase.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {IERC721} from '@openzeppelin/contracts/token/ERC721/IERC721.sol';

struct ProfileData {
    address currency;
    uint256 amount;
    uint256 lengthOfStaking;
}

contract StakeFollowModule is FeeModuleBase, FollowValidatorFollowModuleBase {
    using SafeERC20 for IERC20;

    mapping(uint256 => ProfileData) internal _dataByProfile;

    // profileID -> address -> timestamp to withdraw
    mapping(uint256 => mapping(address => uint256)) public timestampEligibleForWithdraw;
    mapping(uint256 => mapping(address => bool)) public hasWithdrawnStake;

    constructor(address hub, address moduleGlobals) FeeModuleBase(moduleGlobals) ModuleBase(hub) {}

    function initializeFollowModule(uint256 profileId, bytes calldata data)
        external
        override
        onlyHub
        returns (bytes memory)
    {
        (uint256 amount, address currency, uint256 lengthOfStaking) = abi.decode(
            data,
            (uint256, address, uint256)
        );
        if (!_currencyWhitelisted(currency) || lengthOfStaking == 0 || amount == 0)
            revert Errors.InitParamsInvalid();

        _dataByProfile[profileId].amount = amount;
        _dataByProfile[profileId].currency = currency;
        _dataByProfile[profileId].lengthOfStaking = lengthOfStaking;
        return data;
    }

    function processFollow(
        address follower,
        uint256 profileId,
        bytes calldata data
    ) external override onlyHub {
        uint256 amount = _dataByProfile[profileId].amount;
        address currency = _dataByProfile[profileId].currency;
        _validateDataIsExpected(data, currency, amount);

        timestampEligibleForWithdraw[profileId][follower] =
            block.timestamp +
            _dataByProfile[profileId].lengthOfStaking;

        IERC20(currency).safeTransferFrom(follower, address(this), amount);
    }

    function redeemStake(uint256 profileId) external {
        uint256 withdrawTime = timestampEligibleForWithdraw[profileId][msg.sender];
        require(
            block.timestamp >= withdrawTime && withdrawTime != 0,
            'not eligible to withdraw yet or not staked'
        );
        require(!hasWithdrawnStake[profileId][msg.sender], 'already withdrawn');

        hasWithdrawnStake[profileId][msg.sender] = true;

        // process return.
        IERC20(_dataByProfile[profileId].currency).transfer(
            msg.sender,
            _dataByProfile[profileId].amount
        );
    }

    /**
     * @dev We don't need to execute any additional logic on transfers in this follow module.
     */
    function followModuleTransferHook(
        uint256 profileId,
        address from,
        address to,
        uint256 followNFTTokenId
    ) external override {
        timestampEligibleForWithdraw[profileId][to] = timestampEligibleForWithdraw[profileId][from];
        timestampEligibleForWithdraw[profileId][from] = 0;

        hasWithdrawnStake[profileId][to] = hasWithdrawnStake[profileId][from];
        hasWithdrawnStake[profileId][from] = false;
    }

    /**
     * @notice Returns the profile data for a given profile, or an empty struct if that profile was not initialized
     * with this module.
     *
     * @param profileId The token ID of the profile to query.
     *
     * @return ProfileData The ProfileData struct mapped to that profile.
     */
    function getProfileData(uint256 profileId) external view returns (ProfileData memory) {
        return _dataByProfile[profileId];
    }
}
