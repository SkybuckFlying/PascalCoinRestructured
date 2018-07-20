unit UOperationBlock;

interface

uses
  UAccountKey, URawBytes;

type
  TOperationBlock = Record
    block: Cardinal;
    account_key: TAccountKey;
    reward: UInt64;
    fee: UInt64;
    protocol_version: Word;     // Protocol version
    protocol_available: Word;   // Used to upgrade protocol
    timestamp: Cardinal;        // Timestamp creation
    compact_target: Cardinal;   // Target in compact form
    nonce: Cardinal;            // Random value to generate a new P-o-W
    block_payload : TRawBytes;  // RAW Payload that a miner can include to a blockchain
    initial_safe_box_hash: TRawBytes; // RAW Safe Box Hash value (32 bytes, it's a Sha256)
    operations_hash: TRawBytes; // RAW sha256 (32 bytes) of Operations
    proof_of_work: TRawBytes;   // RAW Double Sha256
  end;

var
  CT_OperationBlock_NUL : TOperationBlock; // initialized in initilization section

implementation

initialization
  Initialize(CT_OperationBlock_NUL);

end.
