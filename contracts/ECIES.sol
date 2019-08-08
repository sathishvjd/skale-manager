pragma solidity ^0.5.0;

contract AES {
    
        // SBOX
        // 0x63, 0x7c, 0x77, 0x7b, 0xf2, 0x6b, 0x6f, 0xc5, 0x30, 0x01, 0x67, 0x2b, 0xfe, 0xd7, 0xab, 0x76, 
        // 0xca, 0x82, 0xc9, 0x7d, 0xfa, 0x59, 0x47, 0xf0, 0xad, 0xd4, 0xa2, 0xaf, 0x9c, 0xa4, 0x72, 0xc0, 
        // 0xb7, 0xfd, 0x93, 0x26, 0x36, 0x3f, 0xf7, 0xcc, 0x34, 0xa5, 0xe5, 0xf1, 0x71, 0xd8, 0x31, 0x15, 
        // 0x04, 0xc7, 0x23, 0xc3, 0x18, 0x96, 0x05, 0x9a, 0x07, 0x12, 0x80, 0xe2, 0xeb, 0x27, 0xb2, 0x75, 
        // 0x09, 0x83, 0x2c, 0x1a, 0x1b, 0x6e, 0x5a, 0xa0, 0x52, 0x3b, 0xd6, 0xb3, 0x29, 0xe3, 0x2f, 0x84, 
        // 0x53, 0xd1, 0x00, 0xed, 0x20, 0xfc, 0xb1, 0x5b, 0x6a, 0xcb, 0xbe, 0x39, 0x4a, 0x4c, 0x58, 0xcf, 
        // 0xd0, 0xef, 0xaa, 0xfb, 0x43, 0x4d, 0x33, 0x85, 0x45, 0xf9, 0x02, 0x7f, 0x50, 0x3c, 0x9f, 0xa8, 
        // 0x51, 0xa3, 0x40, 0x8f, 0x92, 0x9d, 0x38, 0xf5, 0xbc, 0xb6, 0xda, 0x21, 0x10, 0xff, 0xf3, 0xd2, 
        // 0xcd, 0x0c, 0x13, 0xec, 0x5f, 0x97, 0x44, 0x17, 0xc4, 0xa7, 0x7e, 0x3d, 0x64, 0x5d, 0x19, 0x73, 
        // 0x60, 0x81, 0x4f, 0xdc, 0x22, 0x2a, 0x90, 0x88, 0x46, 0xee, 0xb8, 0x14, 0xde, 0x5e, 0x0b, 0xdb, 
        // 0xe0, 0x32, 0x3a, 0x0a, 0x49, 0x06, 0x24, 0x5c, 0xc2, 0xd3, 0xac, 0x62, 0x91, 0x95, 0xe4, 0x79, 
        // 0xe7, 0xc8, 0x37, 0x6d, 0x8d, 0xd5, 0x4e, 0xa9, 0x6c, 0x56, 0xf4, 0xea, 0x65, 0x7a, 0xae, 0x08, 
        // 0xba, 0x78, 0x25, 0x2e, 0x1c, 0xa6, 0xb4, 0xc6, 0xe8, 0xdd, 0x74, 0x1f, 0x4b, 0xbd, 0x8b, 0x8a, 
        // 0x70, 0x3e, 0xb5, 0x66, 0x48, 0x03, 0xf6, 0x0e, 0x61, 0x35, 0x57, 0xb9, 0x86, 0xc1, 0x1d, 0x9e, 
        // 0xe1, 0xf8, 0x98, 0x11, 0x69, 0xd9, 0x8e, 0x94, 0x9b, 0x1e, 0x87, 0xe9, 0xce, 0x55, 0x28, 0xdf, 
        // 0x8c, 0xa1, 0x89, 0x0d, 0xbf, 0xe6, 0x42, 0x68, 0x41, 0x99, 0x2d, 0x0f, 0xb0, 0x54, 0xbb, 0x16
        
        // INVSBOX
        // 0x52, 0x09, 0x6a, 0xd5, 0x30, 0x36, 0xa5, 0x38, 0xbf, 0x40, 0xa3, 0x9e, 0x81, 0xf3, 0xd7, 0xfb,
        // 0x7c, 0xe3, 0x39, 0x82, 0x9b, 0x2f, 0xff, 0x87, 0x34, 0x8e, 0x43, 0x44, 0xc4, 0xde, 0xe9, 0xcb,
        // 0x54, 0x7b, 0x94, 0x32, 0xa6, 0xc2, 0x23, 0x3d, 0xee, 0x4c, 0x95, 0x0b, 0x42, 0xfa, 0xc3, 0x4e,
        // 0x08, 0x2e, 0xa1, 0x66, 0x28, 0xd9, 0x24, 0xb2, 0x76, 0x5b, 0xa2, 0x49, 0x6d, 0x8b, 0xd1, 0x25,
        // 0x72, 0xf8, 0xf6, 0x64, 0x86, 0x68, 0x98, 0x16, 0xd4, 0xa4, 0x5c, 0xcc, 0x5d, 0x65, 0xb6, 0x92,
        // 0x6c, 0x70, 0x48, 0x50, 0xfd, 0xed, 0xb9, 0xda, 0x5e, 0x15, 0x46, 0x57, 0xa7, 0x8d, 0x9d, 0x84,
        // 0x90, 0xd8, 0xab, 0x00, 0x8c, 0xbc, 0xd3, 0x0a, 0xf7, 0xe4, 0x58, 0x05, 0xb8, 0xb3, 0x45, 0x06,
        // 0xd0, 0x2c, 0x1e, 0x8f, 0xca, 0x3f, 0x0f, 0x02, 0xc1, 0xaf, 0xbd, 0x03, 0x01, 0x13, 0x8a, 0x6b,
        // 0x3a, 0x91, 0x11, 0x41, 0x4f, 0x67, 0xdc, 0xea, 0x97, 0xf2, 0xcf, 0xce, 0xf0, 0xb4, 0xe6, 0x73,
        // 0x96, 0xac, 0x74, 0x22, 0xe7, 0xad, 0x35, 0x85, 0xe2, 0xf9, 0x37, 0xe8, 0x1c, 0x75, 0xdf, 0x6e,
        // 0x47, 0xf1, 0x1a, 0x71, 0x1d, 0x29, 0xc5, 0x89, 0x6f, 0xb7, 0x62, 0x0e, 0xaa, 0x18, 0xbe, 0x1b,
        // 0xfc, 0x56, 0x3e, 0x4b, 0xc6, 0xd2, 0x79, 0x20, 0x9a, 0xdb, 0xc0, 0xfe, 0x78, 0xcd, 0x5a, 0xf4,
        // 0x1f, 0xdd, 0xa8, 0x33, 0x88, 0x07, 0xc7, 0x31, 0xb1, 0x12, 0x10, 0x59, 0x27, 0x80, 0xec, 0x5f,
        // 0x60, 0x51, 0x7f, 0xa9, 0x19, 0xb5, 0x4a, 0x0d, 0x2d, 0xe5, 0x7a, 0x9f, 0x93, 0xc9, 0x9c, 0xef,
        // 0xa0, 0xe0, 0x3b, 0x4d, 0xae, 0x2a, 0xf5, 0xb0, 0xc8, 0xeb, 0xbb, 0x3c, 0x83, 0x53, 0x99, 0x61,
        // 0x17, 0x2b, 0x04, 0x7e, 0xba, 0x77, 0xd6, 0x26, 0xe1, 0x69, 0x14, 0x63, 0x55, 0x21, 0x0c, 0x7d
        
    struct Box {
        bytes32[8] lines;
    }
    
    Box sbox;
    Box invSbox;
    
    uint8 Nr;
    uint8 Nk;
    uint8 Nb = 4;
    
    bytes10 rcon = 0x01020408102040801b36;
    
    address owner;
    
    constructor(uint16 typeOfAES) public {
        owner = msg.sender;
        if (typeOfAES == 128) {
            Nr = 10;
            Nk = 4;
        } else if (typeOfAES == 192) {
            Nr = 12;
            Nk = 6;
        } else if (typeOfAES == 256) {
            Nr = 14;
            Nk = 8;
        } else {
            revert("Incorrect type of AES");
        }
    }
    
    function setSbox() public {
        sbox.lines[0] = 0x637c777bf26b6fc53001672bfed7ab76ca82c97dfa5947f0add4a2af9ca472c0;
        sbox.lines[1] = 0xb7fd9326363ff7cc34a5e5f171d8311504c723c31896059a071280e2eb27b275;
        sbox.lines[2] = 0x09832c1a1b6e5aa0523bd6b329e32f8453d100ed20fcb15b6acbbe394a4c58cf;
        sbox.lines[3] = 0xd0efaafb434d338545f9027f503c9fa851a3408f929d38f5bcb6da2110fff3d2;
        sbox.lines[4] = 0xcd0c13ec5f974417c4a77e3d645d197360814fdc222a908846eeb814de5e0bdb;
        sbox.lines[5] = 0xe0323a0a4906245cc2d3ac629195e479e7c8376d8dd54ea96c56f4ea657aae08;
        sbox.lines[6] = 0xba78252e1ca6b4c6e8dd741f4bbd8b8a703eb5664803f60e613557b986c11d9e;
        sbox.lines[7] = 0xe1f8981169d98e949b1e87e9ce5528df8ca1890dbfe6426841992d0fb054bb16;
    }
    
    function setInvSbox() public {
        invSbox.lines[0] = 0x52096ad53036a538bf40a39e81f3d7fb7ce339829b2fff87348e4344c4dee9cb;
        invSbox.lines[1] = 0x547b9432a6c2233dee4c950b42fac34e082ea16628d924b2765ba2496d8bd125;
        invSbox.lines[2] = 0x72f8f66486689816d4a45ccc5d65b6926c704850fdedb9da5e154657a78d9d84;
        invSbox.lines[3] = 0x90d8ab008cbcd30af7e45805b8b34506d02c1e8fca3f0f02c1afbd0301138a6b;
        invSbox.lines[4] = 0x3a9111414f67dcea97f2cfcef0b4e67396ac7422e7ad3585e2f937e81c75df6e;
        invSbox.lines[5] = 0x47f11a711d29c5896fb7620eaa18be1bfc563e4bc6d279209adbc0fe78cd5af4;
        invSbox.lines[6] = 0x1fdda8338807c731b11210592780ec5f60517fa919b54a0d2de57a9f93c99cef;
        invSbox.lines[7] = 0xa0e03b4dae2af5b0c8ebbb3c83539961172b047eba77d626e169146355210c7d;
    }
    
    function getByteFromSbox(bytes1 input) public view returns (bytes1) {
        uint8 numberFromInput = uint8(input);
        return sbox.lines[numberFromInput / 32][numberFromInput % 32];
    }
    
    function getByteFromInvSbox(bytes1 input) public view returns (bytes1) {
        uint8 numberFromInput = uint8(input);
        return invSbox.lines[numberFromInput / 32][numberFromInput % 32];
    }
    
    function KeyExpansion(bytes memory cipherKey) public view returns (bytes memory keySchedule) {
        require(cipherKey.length == 4 * Nk, "Incorrect data");
        keySchedule = new bytes(4 * Nk * (Nr + 1));
        for (uint8 i = 0; i < cipherKey.length; i++) {
            keySchedule[i] = cipherKey[i];
        }
        for (uint8 i = Nk; i < Nb * (Nr + 1); i++) {
            if (i % Nk == 0) {
                bytes memory firstTerm = new bytes(4);
                bytes memory secondTerm = new bytes(4);
                for (uint j = 0; j < 4; j++) {
                    firstTerm[j] = keySchedule[i * 4 - 4 * Nk + j * Nk];
                    secondTerm[j] = getByteFromSbox(keySchedule[i * 4 - 4 * Nk + (j * Nk + (Nk - 1) + Nk) % (4 * Nk)]);
                }
                keySchedule[i * 4] = firstTerm[0] ^ secondTerm[0] ^ rcon[i / Nk - 1];
                keySchedule[i * 4 + Nk] = firstTerm[1] ^ secondTerm[1] ^ 0x00;
                keySchedule[i * 4 + 2 * Nk] = firstTerm[2] ^ secondTerm[2] ^ 0x00;
                keySchedule[i * 4 + 3 * Nk] = firstTerm[3] ^ secondTerm[3] ^ 0x00;
            } else {
                keySchedule[i * 4] = getByteFromSbox(keySchedule[i * 4 - 4 * Nk]) ^ keySchedule[i * 4 - 4 * Nk + Nk - 1];
                keySchedule[i * 4 + Nk] = getByteFromSbox(keySchedule[i * 4 - 4 * Nk + Nk]) ^ keySchedule[i * 4 - 4 * Nk + Nk + Nk - 1];
                keySchedule[i * 4 + 2 * Nk] = getByteFromSbox(keySchedule[i * 4 - 4 * Nk + 2 * Nk]) ^ keySchedule[i * 4 - 4 * Nk + 2 * Nk + Nk - 1];
                keySchedule[i * 4 + 3 * Nk] = getByteFromSbox(keySchedule[i * 4 - 4 * Nk + 3 * Nk]) ^ keySchedule[i * 4 - 4 * Nk + 3 * Nk + Nk - 1];
            }
        }
    }
    
    function AddRoundKey() public {}
    
    function SubBytes(bytes memory input) public view returns (bytes memory output) {
        require(input.length == 4 * Nb, "Incorrect data");
        output = new bytes(4 * Nb);
        for (uint8 i = 0; i < 4 * Nb; i++) {
            output[i] = getByteFromSbox(input[i]);
        }
    }
    
    function invSubBytes(bytes memory input) public view returns (bytes memory output) {
        require(input.length == 4 * Nb, "Incorrect data");
        output = new bytes(4 * Nb);
        for (uint8 i = 0; i < 4 * Nb; i++) {
            output[i] = getByteFromInvSbox(input[i]);
        }
    }
    
    function ShiftRows(bytes memory input) public view returns (bytes memory output) {
        require(input.length == 4 * Nb, "Incorrect data");
        output = new bytes(4 * Nb);
        for (uint i = 0; i < Nb; i++) {
            for (uint j = 0; j < Nb; j++) {
                uint num = (Nb + j - i) % 4;
                output[i * Nb + num] = input[i * Nb + j];
            }
        }
    }
    
    function invShiftRows(bytes memory input) public view returns (bytes memory output) {
        require(input.length == 4 * Nb, "Incorrect data");
        output = new bytes(4 * Nb);
        for (uint i = 0; i < Nb; i++) {
            for (uint j = 0; j < Nb; j++) {
                uint num = (Nb + j + i) % 4;
                output[i * Nb + num] = input[i * Nb + j];
            }
        }
    }
    
    function MixColumns(bytes memory input) public view returns (bytes memory output) {
        require(input.length == 4 * Nb, "Incorrect data");
        output = new bytes(4 * Nb);
        for (uint i = 0; i < Nb; i++) {
            output[i] = mul_by_02(input[i])^mul_by_03(input[Nb + i])^input[2 * Nb + i]^input[3 * Nb + i];
            output[Nb + i] = input[i]^mul_by_02(input[Nb + i])^mul_by_03(input[2 * Nb + i])^input[3 * Nb + i];
            output[2 * Nb + i] = input[i]^input[Nb + i]^mul_by_02(input[2 * Nb + i])^mul_by_03(input[3 * Nb + i]);
            output[3 * Nb + i] = mul_by_03(input[i])^input[Nb + i]^input[2 * Nb + i]^mul_by_02(input[3 * Nb + i]);
        }
    }
    
    function invMixColumns(bytes memory input) public view returns (bytes memory output) {
        require(input.length == 4 * Nb, "Incorrect data");
        output = new bytes(4 * Nb);
        for (uint i = 0; i < Nb; i++) {
            output[i] = mul_by_0e(input[i])^mul_by_0b(input[Nb + i])^mul_by_0d(input[2 * Nb + i])^mul_by_09(input[3 * Nb + i]);
            output[Nb + i] = mul_by_09(input[i])^mul_by_0e(input[Nb + i])^mul_by_0b(input[2 * Nb + i])^mul_by_0d(input[3 * Nb + i]);
            output[2 * Nb + i] = mul_by_0d(input[i])^mul_by_09(input[Nb + i])^mul_by_0e(input[2 * Nb + i])^mul_by_0b(input[3 * Nb + i]);
            output[3 * Nb + i] = mul_by_0b(input[i])^mul_by_0d(input[Nb + i])^mul_by_09(input[2 * Nb + i])^mul_by_0e(input[3 * Nb + i]);
        }
    }
    
    function mul_by_02(bytes1 input) internal pure returns (bytes1) {
        bytes2 output;
        if (input < 0x80) {
            output = (input<<1);
        } else {
            output = (input<<1)^0x1b;
        }
        output = bytes1(uint8(uint16(output) % 256));
    }
    
    function mul_by_03(bytes1 input) internal pure returns (bytes1) {
        return mul_by_02(input)^input;
    }
    
    function mul_by_09(bytes1 input) internal pure returns (bytes1) {
        return mul_by_02(mul_by_02(mul_by_02(input)))^input;
    }
    
    function mul_by_0b(bytes1 input) internal pure returns (bytes1) {
        return mul_by_02(mul_by_02(mul_by_02(input)))^mul_by_02(input)^input;
    }
    
    function mul_by_0d(bytes1 input) internal pure returns (bytes1) {
        return mul_by_02(mul_by_02(mul_by_02(input)))^mul_by_02(mul_by_02(input))^input;
    }
    
    function mul_by_0e(bytes1 input) internal pure returns (bytes1) {
        return mul_by_02(mul_by_02(mul_by_02(input)))^mul_by_02(mul_by_02(input))^mul_by_02(input);
    }
}