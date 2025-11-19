// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {IRebaseToken} from "./interface/IRebaseToken.sol";

contract Vault {
    IRebaseToken private immutable i_rebaseToken; // Type will be interface

    event Deposit(address indexed user, uint256 amount);
    event Redeem(address indexed user, uint256 amount);

    error Vault_RedeemFailed();
    error Vault_DepositAmountIsZero();

    constructor(IRebaseToken _rebaseToken) {
        // Parameter type will be interface
        i_rebaseToken = _rebaseToken;
    }

    receive() external payable {}

    function deposit() external payable {
        uint256 amountToMint = msg.value;
        if (amountToMint == 0) {
            revert Vault_DepositAmountIsZero(); // Consider adding a custom error
        }
        i_rebaseToken.mint(msg.sender, amountToMint,i_rebaseToken.getInterestRate());
        emit Deposit(msg.sender, amountToMint);
    }

    function redeem(uint256 _amount) external {
        i_rebaseToken.burn(msg.sender, _amount);
        (bool success, ) = payable(msg.sender).call{value: _amount}("");

        // Check if the ETH transfer succeeded
        if (!success) {
            revert Vault_RedeemFailed(); // Use the custom error
        }

        // Emit an event logging the redemption
        emit Redeem(msg.sender, _amount);
    }

    /**
     * @notice Gets the address of the RebaseToken contract associated with this vault.
     * @return The address of the RebaseToken.
     */
    function getRebaseTokenAddress() external view returns (address) {
        return address(i_rebaseToken); // Cast to address for return
    }
}
