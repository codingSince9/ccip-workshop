// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {OwnerIsCreator} from "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";
import {IERC20} from "@chainlink/contracts-ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.0/token/ERC20/IERC20.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";

contract TicTacToe is CCIPReceiver, OwnerIsCreator {
    LinkTokenInterface link;
    IRouterClient router;

    struct Game {
        bytes32 id;
        address player1;
        address player2;
        uint8[9] player1Status;
        uint8[9] player2Status;
        address turn;
        address winner;
    }
    mapping(bytes32 => Game) public games;
    bytes32[] public gameIds;
    uint8[9] initialState = [0, 0, 0, 0, 0, 0, 0, 0, 0];

    function getPlayer1Status(bytes32 _sessionId) external view returns (uint8[9] memory){
        return gameSessions[_sessionId].player1Status;
    }
    function getPlayer2Status(bytes32 _sessionId) external view returns (uint8[9] memory){
        return gameSessions[_sessionId].player2Status;
    }

    constructor(address _router, address _link) CCIPReceiver(_router) {
        router = IRouterClient(_router);
        link = LinkTokenInterface(_link);
    }

    function start(uint64 _destChain, address _target) external {
        bytes32 id = keccak256(abi.encodePacked(block.timestamp, msg.sender));
        gameIds.push(id);
        games[id] = Game(
            id,
            msg.sender,
            address(0),
            initialState,
            initialState,
            msg.sender,
            address(0)
        );

        sendMessage(games[id], _target, _destChain);
    }

    function sendMessage(Game memory _game, address _target, uint64 _destChain) internal {
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(_target),
            data: abi.encode(_game),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: "",
            feeToken: address(link)
        });
        uint256 fees = router.getFee(_destChain, message);
        link.approve(address(router), fees);
        router.ccipSend(_destChain, message);
    }

    function move(uint8 _x, uint8 _y, uint256 _player, bytes32 _gameId, uint64 _destChain, address _target) public {
        Game memory game = games[_gameId];
        require(_player == 1 || _player == 2, "Must be player1 or player2.");
        require(game.winner == address(0), "Game is over.");
        require(game.player1 != address(0), "Game is not set up yet.");

        uint256 position = _x*3 + _y;
        if (_player == 1) {
            require(game.player1 == msg.sender && game.turn == msg.sender, "Not your turn");
            if (game.player1Status[position] == 0 && game.player2Status[position] == 0) {
                game.player1Status[position] = 1;
                // check if game resolved
                if (checkWin(game.player1Status)) game.winner = game.player1;
                else game.turn = game.player2;

                sendMessage(game, _target, _destChain);
            } else {
                revert("Place already taken");
            }
        } else if (_player == 2) {
            require((game.player2 == msg.sender && game.turn == msg.sender) || game.player2 == address(0), "Not your turn");
            if (game.player2 == address(0)) game.player2 = msg.sender;
            if (game.player1Status[position] == 0 && game.player2Status[position] == 0) {
                game.player2Status[position] = 1;
                // check if game resolved
                if (checkWin(game.player2Status)) game.winner = game.player2;
                else game.turn = game.player1;

                sendMessage(game, _target, _destChain);
            } else {
                revert("Place already taken");
            }
        }
    }

    function _ccipReceive(Client.Any2EVMMessage memory message) internal override {
        Game memory game = abi.decode(message.data, (Game));
        games[game.id] = game;
        gameIds.push(game.id);
    }

    function checkWin(uint8[9] memory _playerStatus) public pure returns (bool _result) {
        // horizontal
        if (_playerStatus[0] == 1 && _playerStatus[1] == 1 && _playerStatus[2] == 1) return true;
        if (_playerStatus[3] == 1 && _playerStatus[4] == 1 && _playerStatus[5] == 1) return true;
        if (_playerStatus[6] == 1 && _playerStatus[7] == 1 && _playerStatus[8] == 1) return true;
        // vertical
        if (_playerStatus[0] == 1 && _playerStatus[3] == 1 && _playerStatus[6] == 1) return true;
        if (_playerStatus[1] == 1 && _playerStatus[4] == 1 && _playerStatus[7] == 1) return true;
        if (_playerStatus[2] == 1 && _playerStatus[5] == 1 && _playerStatus[8] == 1) return true;
        // diagonal
        if (_playerStatus[0] == 1 && _playerStatus[4] == 1 && _playerStatus[8] == 1) return true;
        if (_playerStatus[2] == 1 && _playerStatus[4] == 1 && _playerStatus[6] == 1) return true;
        // no winner
        return false;
    }

    function withdrawToken(
        address _beneficiary,
        address _token
    ) public onlyOwner {
        uint256 amount = IERC20(_token).balanceOf(address(this));
        require(amount > 0, "Nothing to withdraw");        
        IERC20(_token).transfer(_beneficiary, amount);
    }
}