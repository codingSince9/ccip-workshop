// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {OwnerIsCreator} from "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";
import {IERC20} from "@chainlink/contracts-ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.0/token/ERC20/IERC20.sol";

contract SendTokens is OwnerIsCreator {
    IRouterClient router;
    LinkTokenInterface link;

    mapping(uint64 => bool) public whitelistedChains;

    function whitelistChain(uint64 _chainId) external onlyOwner {
        whitelistedChains[_chainId] = true;
    }

    function unwhitelistChain(uint64 _chainId) external onlyOwner {
        whitelistedChains[_chainId] = false;
    }

    modifier onlyWhitelistedChains (uint64 _chainId) {
        require(whitelistedChains[_chainId], "Chain not whitelisted");
        _;
    } 

    constructor(address _router, address _link) {
        router = IRouterClient(_router);
        link = LinkTokenInterface(_link);
    }

    function send(
        address _receiver,
        address _token,
        uint256 _amount,
        uint64 _destChainSelector
    ) external onlyWhitelistedChains(_destChainSelector) {
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        Client.EVMTokenAmount memory tokenAmount = Client.EVMTokenAmount({
            token: _token,
            amount: _amount
        });
        tokenAmounts[0] = tokenAmount;

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(_receiver),
            data: "",
            tokenAmounts: tokenAmounts,
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV1({gasLimit: 0, strict: false})
            ),
            feeToken: address(link)
        });

        uint256 fees = router.getFee(_destChainSelector, message);
        require(link.balanceOf(address(this)) > fees, "Not enough LINK to cover the fees");
        link.approve(address(router), fees);
        IERC20(_token).approve(address(router), _amount);

        router.ccipSend(_destChainSelector, message);
    }

    function withdraw(address _receiver, address _token) public onlyOwner {
        uint256 amount = IERC20(_token).balanceOf(address(this));
        require(amount > 0, "Nothing to withdraw");
        IERC20(_token).transfer(_receiver, amount);
    }
}