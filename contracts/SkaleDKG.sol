// SPDX-License-Identifier: AGPL-3.0-only

/*
    SkaleDKG.sol - SKALE Manager
    Copyright (C) 2018-Present SKALE Labs
    @author Artem Payvin

    SKALE Manager is free software: you can redistribute it and/or modify
    it under the terms of the GNU Affero General Public License as published
    by the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    SKALE Manager is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU Affero General Public License for more details.

    You should have received a copy of the GNU Affero General Public License
    along with SKALE Manager.  If not, see <https://www.gnu.org/licenses/>.
*/

pragma solidity 0.6.10;
pragma experimental ABIEncoderV2;
import "./Permissions.sol";
import "./delegation/Punisher.sol";
import "./SlashingTable.sol";
import "./Schains.sol";
import "./SchainsInternal.sol";
import "./utils/FieldOperations.sol";
import "./NodeRotation.sol";
import "./KeyStorage.sol";
import "./interfaces/ISkaleDKG.sol";
import "./ECDH.sol";
import "./utils/Precompiled.sol";

contract SkaleDKG is Permissions, ISkaleDKG {
    using Fp2Operations for Fp2Operations.Fp2Point;
    using G2Operations for G2Operations.G2Point;

    struct Channel {
        bool active;
        uint n;
        uint startedBlockTimestamp;
    }

    struct ProcessDKG {
        uint numberOfBroadcasted;
        uint numberOfCompleted;
        bool[] broadcasted;
        bool[] completed;
        uint startAlrightTimestamp;
    }

    struct ComplaintData {
        uint nodeToComplaint;
        uint fromNodeToComplaint;
        uint startComplaintBlockTimestamp;
    }

    uint public constant COMPLAINT_TIMELIMIT = 1800;

    mapping(bytes32 => Channel) public channels;

    mapping(bytes32 => uint) public lastSuccesfulDKG;

    mapping(bytes32 => ProcessDKG) public dkgProcess;

    mapping(bytes32 => ComplaintData) public complaints;

    mapping(bytes32 => uint) public startAlrightTimestamp;

    mapping(bytes32 => mapping(uint => bytes32)) hashedData;

    event ChannelOpened(bytes32 groupIndex);

    event ChannelClosed(bytes32 groupIndex);

    event BroadcastAndKeyShare(
        bytes32 indexed groupIndex,
        uint indexed fromNode,
        G2Operations.G2Point[] verificationVector,
        KeyStorage.KeyShare[] secretKeyContribution
    );

    event AllDataReceived(bytes32 indexed groupIndex, uint nodeIndex);
    event SuccessfulDKG(bytes32 indexed groupIndex);
    event BadGuy(uint nodeIndex);
    event FailedDKG(bytes32 indexed groupIndex);
    event ComplaintSent(bytes32 indexed groupIndex, uint indexed fromNodeIndex, uint indexed toNodeIndex);
    event NewGuy(uint nodeIndex);
    event ComplaintError(string error);

    modifier correctGroup(bytes32 groupIndex) {
        require(channels[groupIndex].active, "Group is not created");
        _;
    }

    modifier correctGroupWithoutRevert(bytes32 groupIndex) {
        if (!channels[groupIndex].active) {
            emit ComplaintError("Group is not created");
        } else {
            _;
        }
    }

    modifier correctNode(bytes32 groupIndex, uint nodeIndex) {
        uint index = _nodeIndexInSchain(groupIndex, nodeIndex);
        require(
            index < channels[groupIndex].n,
            "Node is not in this group");
        _;
    }

    function openChannel(bytes32 groupIndex) external override allowTwo("Schains","NodeRotation") {
        _openChannel(groupIndex);
    }

    function deleteChannel(bytes32 groupIndex) external override allow("SchainsInternal") {
        require(channels[groupIndex].active, "Channel is not created");
        delete channels[groupIndex];
        delete dkgProcess[groupIndex];
        delete complaints[groupIndex];
        KeyStorage(contractManager.getContract("KeyStorage")).deleteKey(groupIndex);
    }

    function broadcast(
        bytes32 groupIndex,
        uint nodeIndex,
        G2Operations.G2Point[] calldata verificationVector,
        KeyStorage.KeyShare[] calldata secretKeyContribution
    )
        external
        correctGroup(groupIndex)
    {
        require(_isNodeByMessageSender(nodeIndex, msg.sender), "Node does not exist for message sender");
        uint n = channels[groupIndex].n;
        require(verificationVector.length == getT(n), "Incorrect number of verification vectors");
        require(
            secretKeyContribution.length == n,
            "Incorrect number of secret key shares"
        );
        uint index = _nodeIndexInSchain(groupIndex, nodeIndex);
        require(index < channels[groupIndex].n, "Node is not in this group");
        require(!dkgProcess[groupIndex].broadcasted[index], "This node is already broadcasted");
        dkgProcess[groupIndex].broadcasted[index] = true;
        dkgProcess[groupIndex].numberOfBroadcasted++;
        if (dkgProcess[groupIndex].numberOfBroadcasted == channels[groupIndex].n) {
            startAlrightTimestamp[groupIndex] = now;
        }

        // _saveBroadcast(
        //     groupIndex,
        //     nodeIndex,
        //     secretKeyContribution,
        //     verificationVector
        // );
        hashedData[groupIndex][index] = _hashData(secretKeyContribution, verificationVector);
        KeyStorage keyStorage = KeyStorage(contractManager.getContract("KeyStorage"));
        keyStorage.adding(groupIndex, verificationVector[0]);
        keyStorage.computePublicValues(groupIndex, verificationVector);
        emit BroadcastAndKeyShare(
            groupIndex,
            nodeIndex,
            verificationVector,
            secretKeyContribution
        );
    }

    function complaint(bytes32 groupIndex, uint fromNodeIndex, uint toNodeIndex)
        external
        correctGroupWithoutRevert(groupIndex)
        correctNode(groupIndex, fromNodeIndex)
        correctNode(groupIndex, toNodeIndex)
    {
        require(_isNodeByMessageSender(fromNodeIndex, msg.sender), "Node does not exist for message sender");
        bool broadcasted = _isBroadcasted(groupIndex, toNodeIndex);
        if (broadcasted && complaints[groupIndex].nodeToComplaint == uint(-1)) {
            // incorrect data or missing alright
            if (
                isEveryoneBroadcasted(groupIndex) &&
                startAlrightTimestamp[groupIndex].add(COMPLAINT_TIMELIMIT) <= block.timestamp &&
                !isAllDataReceived(groupIndex, toNodeIndex)
            ) {
                // missing alright
                _finalizeSlashing(groupIndex, toNodeIndex);
            } else {
                // incorrect data
                complaints[groupIndex].nodeToComplaint = toNodeIndex;
                complaints[groupIndex].fromNodeToComplaint = fromNodeIndex;
                complaints[groupIndex].startComplaintBlockTimestamp = block.timestamp;
                emit ComplaintSent(groupIndex, fromNodeIndex, toNodeIndex);
            }
        } else if (broadcasted && complaints[groupIndex].nodeToComplaint == toNodeIndex) {
            // 30 min after incorrect data complaint
            if (complaints[groupIndex].startComplaintBlockTimestamp.add(COMPLAINT_TIMELIMIT) <= block.timestamp) {
                _finalizeSlashing(groupIndex, complaints[groupIndex].nodeToComplaint);
            } else {
                emit ComplaintError("The same complaint rejected");
            }
        } else if (!broadcasted) {
            // not broadcasted in 30 min
            if (channels[groupIndex].startedBlockTimestamp.add(COMPLAINT_TIMELIMIT) <= block.timestamp) {
                _finalizeSlashing(groupIndex, toNodeIndex);
            } else {
                emit ComplaintError("Complaint sent too early");
            }
        } else {
            emit ComplaintError("One complaint is already sent");
        }
    }

    function response(
        bytes32 groupIndex,
        uint fromNodeIndex,
        uint secretNumber,
        G2Operations.G2Point calldata multipliedShare,
        G2Operations.G2Point[] calldata verificationVector,
        KeyStorage.KeyShare[] calldata secretKeyContribution
    )
        external
        correctGroup(groupIndex)
    {
        uint indexOnSchain = _nodeIndexInSchain(groupIndex, fromNodeIndex);
        require(indexOnSchain < channels[groupIndex].n, "Node is not in this group");
        require(complaints[groupIndex].nodeToComplaint == fromNodeIndex, "Not this Node");
        require(_isNodeByMessageSender(fromNodeIndex, msg.sender), "Node does not exist for message sender");
        require(hashedData[groupIndex][indexOnSchain] == _hashData(secretKeyContribution, verificationVector));
        uint index = _nodeIndexInSchain(groupIndex, complaints[groupIndex].fromNodeToComplaint);
        _verifyDataAndSlash(
            groupIndex,
            fromNodeIndex,
            indexOnSchain,
            secretNumber,
            multipliedShare,
            verificationVector,
            secretKeyContribution[index].share
         );
    }

    function alright(bytes32 groupIndex, uint fromNodeIndex)
        external
        correctGroup(groupIndex)
        correctNode(groupIndex, fromNodeIndex)
    {
        require(_isNodeByMessageSender(fromNodeIndex, msg.sender), "Node does not exist for message sender");
        uint index = _nodeIndexInSchain(groupIndex, fromNodeIndex);
        uint numberOfParticipant = channels[groupIndex].n;
        require(numberOfParticipant == dkgProcess[groupIndex].numberOfBroadcasted, "Still Broadcasting phase");
        require(!dkgProcess[groupIndex].completed[index], "Node is already alright");
        dkgProcess[groupIndex].completed[index] = true;
        dkgProcess[groupIndex].numberOfCompleted++;
        emit AllDataReceived(groupIndex, fromNodeIndex);
        if (dkgProcess[groupIndex].numberOfCompleted == numberOfParticipant) {
            _setSuccesfulDKG(groupIndex);
        }
    }

    function getChannelStartedTime(bytes32 groupIndex) external view returns (uint) {
        return channels[groupIndex].startedBlockTimestamp;
    }

    function getNumberOfBroadcasted(bytes32 groupIndex) external view returns (uint) {
        return dkgProcess[groupIndex].numberOfBroadcasted;
    }

    function getNumberOfCompleted(bytes32 groupIndex) external view returns (uint) {
        return dkgProcess[groupIndex].numberOfCompleted;
    }

    function getTimeOfLastSuccesfulDKG(bytes32 groupIndex) external view returns (uint) {
        return lastSuccesfulDKG[groupIndex];
    }

    function getComplaintData(bytes32 groupIndex) external view returns (uint, uint) {
        return (complaints[groupIndex].fromNodeToComplaint, complaints[groupIndex].nodeToComplaint);
    }

    function getComplaintStartedTime(bytes32 groupIndex) external view returns (uint) {
        return complaints[groupIndex].startComplaintBlockTimestamp;
    }

    function getAlrightStartedTime(bytes32 groupIndex) external view returns (uint) {
        return startAlrightTimestamp[groupIndex];
    }

    function isChannelOpened(bytes32 groupIndex) external override view returns (bool) {
        return channels[groupIndex].active;
    }

    function isLastDKGSuccesful(bytes32 groupIndex) external override view returns (bool) {
        return channels[groupIndex].startedBlockTimestamp <= lastSuccesfulDKG[groupIndex];
    }

    function isBroadcastPossible(bytes32 groupIndex, uint nodeIndex) external view returns (bool) {
        uint index = _nodeIndexInSchain(groupIndex, nodeIndex);
        return channels[groupIndex].active &&
            index <  channels[groupIndex].n &&
            _isNodeByMessageSender(nodeIndex, msg.sender) &&
            !dkgProcess[groupIndex].broadcasted[index];
    }

    function isComplaintPossible(
        bytes32 groupIndex,
        uint fromNodeIndex,
        uint toNodeIndex
    )
        external
        view
        returns (bool)
    {
        uint indexFrom = _nodeIndexInSchain(groupIndex, fromNodeIndex);
        uint indexTo = _nodeIndexInSchain(groupIndex, toNodeIndex);
        bool complaintSending = (
                complaints[groupIndex].nodeToComplaint == uint(-1) &&
                dkgProcess[groupIndex].broadcasted[indexTo]
            ) ||
            (
                dkgProcess[groupIndex].broadcasted[indexTo] &&
                complaints[groupIndex].startComplaintBlockTimestamp.add(COMPLAINT_TIMELIMIT) <= block.timestamp &&
                complaints[groupIndex].nodeToComplaint == toNodeIndex
            ) ||
            (
                !dkgProcess[groupIndex].broadcasted[indexTo] &&
                complaints[groupIndex].nodeToComplaint == uint(-1) &&
                channels[groupIndex].startedBlockTimestamp.add(COMPLAINT_TIMELIMIT) <= block.timestamp
            );
        return channels[groupIndex].active &&
            indexFrom < channels[groupIndex].n &&
            indexTo < channels[groupIndex].n &&
            _isNodeByMessageSender(fromNodeIndex, msg.sender) &&
            complaintSending;
    }

    function isAlrightPossible(bytes32 groupIndex, uint nodeIndex) external view returns (bool) {
        uint index = _nodeIndexInSchain(groupIndex, nodeIndex);
        return channels[groupIndex].active &&
            index < channels[groupIndex].n &&
            _isNodeByMessageSender(nodeIndex, msg.sender) &&
            channels[groupIndex].n == dkgProcess[groupIndex].numberOfBroadcasted &&
            !dkgProcess[groupIndex].completed[index];
    }

    function isResponsePossible(bytes32 groupIndex, uint nodeIndex) external view returns (bool) {
        uint index = _nodeIndexInSchain(groupIndex, nodeIndex);
        return channels[groupIndex].active &&
            index < channels[groupIndex].n &&
            _isNodeByMessageSender(nodeIndex, msg.sender) &&
            complaints[groupIndex].nodeToComplaint == nodeIndex;
    }

    function isNodeBroadcasted(bytes32 groupIndex, uint nodeIndex) external view returns (bool) {
        uint index = _nodeIndexInSchain(groupIndex, nodeIndex);
        return index < channels[groupIndex].n && dkgProcess[groupIndex].broadcasted[index];
    }

    function initialize(address contractsAddress) public override initializer {
        Permissions.initialize(contractsAddress);
    }

    function isEveryoneBroadcasted(bytes32 groupIndex) public view returns (bool) {
        return channels[groupIndex].n == dkgProcess[groupIndex].numberOfBroadcasted;
    }

    function isAllDataReceived(bytes32 groupIndex, uint nodeIndex) public view returns (bool) {
        uint index = _nodeIndexInSchain(groupIndex, nodeIndex);
        return dkgProcess[groupIndex].completed[index];
    }

    function getT(uint n) public pure returns (uint) {
        return n.mul(2).add(1).div(3);
    }

    function _setSuccesfulDKG(bytes32 groupIndex) internal {
        lastSuccesfulDKG[groupIndex] = now;
        channels[groupIndex].active = false;
        KeyStorage(contractManager.getContract("KeyStorage")).finalizePublicKey(groupIndex);
        emit SuccessfulDKG(groupIndex);
    }

    function _verifyDataAndSlash(
        bytes32 groupIndex,
        uint fromNodeIndex,
        uint indexOnSchain,
        uint secretNumber,
        G2Operations.G2Point calldata multipliedShare,
        G2Operations.G2Point[] calldata verificationVector,
        bytes32 share
    )
        internal
    {
        uint index = _nodeIndexInSchain(groupIndex, complaints[groupIndex].fromNodeToComplaint);

        uint secret = _decryptMessage(groupIndex, secretNumber, fromNodeIndex, complaints[groupIndex].fromNodeToComplaint, share);
        
        bool verificationResult = _checkCorrectMultipliedShare(multipliedShare, indexOnSchain, secret, verificationVector);

        uint badNode = (verificationResult ?
            complaints[groupIndex].fromNodeToComplaint : complaints[groupIndex].nodeToComplaint);
        _finalizeSlashing(groupIndex, badNode);
    }

    // function _verify(
    //     bytes32 groupIndex,
    //     uint nodeToComplaint,
    //     uint fromNodeToComplaint,
    //     uint secretNumber,
    //     G2Operations.G2Point memory multipliedShare
    // )
    //     internal
    //     view
    //     returns (bool)
    // {
    //     SchainsInternal schainsInternal = SchainsInternal(contractManager.getContract("SchainsInternal"));
    //     uint index = schainsInternal.getNodeIndexInGroup(groupIndex, nodeToComplaint);
    //     uint secret = _decryptMessage(groupIndex, secretNumber, nodeToComplaint, fromNodeToComplaint);

    //     G2Operations.G2Point[] memory verificationVector = _data[groupIndex][index].verificationVector;
    //     G2Operations.G2Point memory value = G2Operations.getG2Zero();
    //     G2Operations.G2Point memory tmp = G2Operations.getG2Zero();

    //     if (multipliedShare.isG2()) {
    //         for (uint i = 0; i < verificationVector.length; i++) {
    //             tmp = verificationVector[i].mulG2(index.add(1) ** i);
    //             value = tmp.addG2(value);
    //         }
    //         return value.isEqual(multipliedShare) &&
    //             _checkCorrectMultipliedShare(multipliedShare, secret);
    //     }
    //     return false;
    // }

    function _calculateBadNode(
        bytes32 groupIndex,
        uint fromNodeIndex,
        uint indexOnSchain,
        uint secretNumber,
        G2Operations.G2Point calldata multipliedShare,
        G2Operations.G2Point[] calldata verificationVector,
        bytes32 share
    )
        internal
        view
        returns (uint)
    {
        SchainsInternal schainsInternal = SchainsInternal(contractManager.getContract("SchainsInternal"));
        uint index = schainsInternal.getNodeIndexInGroup(groupIndex, complaints[groupIndex].fromNodeToComplaint);

        uint secret = _decryptMessage(groupIndex, secretNumber, fromNodeIndex, complaints[groupIndex].fromNodeToComplaint, share);
        
        bool verificationResult = _checkCorrectMultipliedShare(multipliedShare, indexOnSchain, secret, verificationVector);

        return (verificationResult ?
            complaints[groupIndex].fromNodeToComplaint : complaints[groupIndex].nodeToComplaint);
    }

    function _decryptMessage(
        bytes32 groupIndex,
        uint secretNumber,
        uint nodeToComplaint,
        uint fromNodeToComplaint,
        bytes32 share
    )
        internal
        view
        returns (uint)
    {

        bytes32 key = _getCommonPublicKey(secretNumber, fromNodeToComplaint);

        // Decrypt secret key contribution
        SchainsInternal schainsInternal = SchainsInternal(contractManager.getContract("SchainsInternal"));
        uint index = schainsInternal.getNodeIndexInGroup(groupIndex, fromNodeToComplaint);
        uint indexOfNode = schainsInternal.getNodeIndexInGroup(groupIndex, nodeToComplaint);
        uint secret = Decryption(contractManager.getContract("Decryption")).decrypt(
            share,
            key
        );
        return secret;
    }

    function _checkCorrectMultipliedShare(
        G2Operations.G2Point memory multipliedShare,
        uint indexOnSchain,
        uint secret,
        G2Operations.G2Point[] calldata verificationVector
    )
        private
        view
        returns (bool)
    {
        if (!multipliedShare.isG2()) {
            return false;
        }
        G2Operations.G2Point memory value = G2Operations.getG2Zero();
        G2Operations.G2Point memory tmp = G2Operations.getG2Zero();
        for (uint i = 0; i < verificationVector.length; i++) {
            tmp = verificationVector[i].mulG2(indexOnSchain.add(1) ** i);
            value = tmp.addG2(value);
        }
        tmp = multipliedShare;
        Fp2Operations.Fp2Point memory g1 = G2Operations.getG1();
        Fp2Operations.Fp2Point memory share = Fp2Operations.Fp2Point({
            a: 0,
            b: 0
        });
        (share.a, share.b) = Precompiled.bn256ScalarMul(g1.a, g1.b, secret);
        if (!(share.a == 0 && share.b == 0)) {
            share.b = Fp2Operations.P.sub((share.b % Fp2Operations.P));
        }

        require(G2Operations.isG1(share), "mulShare not in G1");

        G2Operations.G2Point memory g2 = G2Operations.getG2();
        require(G2Operations.isG2(tmp), "tmp not in g2");

        return value.isEqual(multipliedShare) && Precompiled.bn256Pairing(
            share.a, share.b,
            g2.x.b, g2.x.a, g2.y.b, g2.y.a,
            g1.a, g1.b,
            tmp.x.b, tmp.x.a, tmp.y.b, tmp.y.a);
    }

    function _getCommonPublicKey(
        uint256 secretNumber,
        uint fromNodeToComplaint
    )
        private
        view
        returns (bytes32)
    {
        bytes32[2] memory publicKey = Nodes(contractManager.getContract("Nodes")).getNodePublicKey(fromNodeToComplaint);
        uint256 pkX = uint(publicKey[0]);

        (pkX, ) = ECDH(contractManager.getContract("ECDH")).deriveKey(secretNumber, pkX, uint(publicKey[1]));

        return bytes32(pkX);
    }

    function _openChannel(bytes32 groupIndex) private {
        SchainsInternal schainsInternal = SchainsInternal(
            contractManager.getContract("SchainsInternal")
        );

        uint len = schainsInternal.getNumberOfNodesInGroup(groupIndex);
        channels[groupIndex].active = true;
        channels[groupIndex].n = len;
        delete dkgProcess[groupIndex].completed;
        delete dkgProcess[groupIndex].broadcasted;
        dkgProcess[groupIndex].broadcasted = new bool[](len);
        dkgProcess[groupIndex].completed = new bool[](len);
        complaints[groupIndex].fromNodeToComplaint = uint(-1);
        complaints[groupIndex].nodeToComplaint = uint(-1);
        delete complaints[groupIndex].startComplaintBlockTimestamp;
        delete dkgProcess[groupIndex].numberOfBroadcasted;
        delete dkgProcess[groupIndex].numberOfCompleted;
        channels[groupIndex].startedBlockTimestamp = now;
        KeyStorage(contractManager.getContract("KeyStorage")).initPublicKeyInProgress(groupIndex);

        emit ChannelOpened(groupIndex);
    }

    function _finalizeSlashing(bytes32 groupIndex, uint badNode) private {
        NodeRotation nodeRotation = NodeRotation(contractManager.getContract("NodeRotation"));
        SchainsInternal schainsInternal = SchainsInternal(
            contractManager.getContract("SchainsInternal")
        );
        emit BadGuy(badNode);
        emit FailedDKG(groupIndex);

        if (schainsInternal.isAnyFreeNode(groupIndex)) {
            uint newNode = nodeRotation.rotateNode(
                badNode,
                groupIndex,
                false
            );
            emit NewGuy(newNode);
        } else {
            _openChannel(groupIndex);
            schainsInternal.removeNodeFromSchain(
                badNode,
                groupIndex
            );
            channels[groupIndex].active = false;
        }
        Punisher(contractManager.getContract("Punisher")).slash(
            Nodes(contractManager.getContract("Nodes")).getValidatorId(badNode),
            SlashingTable(contractManager.getContract("SlashingTable")).getPenalty("FailedDKG")
        );
    }

    function _saveBroadcast(
        bytes32 groupIndex,
        uint nodeIndex,
        KeyStorage.KeyShare[] memory secretKeyContribution,
        G2Operations.G2Point[] memory verificationVector
    )
        private
    {
        uint index = _nodeIndexInSchain(groupIndex, nodeIndex);
        require(!dkgProcess[groupIndex].broadcasted[index], "This node is already broadcasted");
        dkgProcess[groupIndex].broadcasted[index] = true;
        dkgProcess[groupIndex].numberOfBroadcasted++;
        if (dkgProcess[groupIndex].numberOfBroadcasted == channels[groupIndex].n) {
            startAlrightTimestamp[groupIndex] = now;
        }
        // KeyStorage(contractManager.getContract("KeyStorage")).addBroadcastedData(
        //     groupIndex,
        //     index,
        //     secretKeyContribution,
        //     verificationVector
        // );
    }

    function _isBroadcasted(bytes32 groupIndex, uint nodeIndex) private view returns (bool) {
        uint index = _nodeIndexInSchain(groupIndex, nodeIndex);
        return dkgProcess[groupIndex].broadcasted[index];
    }

    function _nodeIndexInSchain(bytes32 schainId, uint nodeIndex) private view returns (uint) {
        return SchainsInternal(contractManager.getContract("SchainsInternal"))
            .getNodeIndexInGroup(schainId, nodeIndex);
    }

    function _isNodeByMessageSender(uint nodeIndex, address from) private view returns (bool) {
        Nodes nodes = Nodes(contractManager.getContract("Nodes"));
        return nodes.isNodeExist(from, nodeIndex);
    }

    function _hashData(
        KeyStorage.KeyShare[] memory secretKeyContribution,
        G2Operations.G2Point[] memory verificationVector
    )
        private
        view
        returns (bytes32)
    {
        bytes memory data;
        for (uint i = 0; i < secretKeyContribution.length; i++) {
            data = abi.encodePacked(data, secretKeyContribution[i].publicKey, secretKeyContribution[i].share);
        }
        for (uint i = 0; i < verificationVector.length; i++) {
            data = abi.encodePacked(
                data,
                verificationVector[i].x.a,
                verificationVector[i].x.b,
                verificationVector[i].y.a,
                verificationVector[i].y.b
            );
        }
        return keccak256(data);
    }
}